import XCTest
import UIKit
@testable import ArcaeaOffline

private actor PortraitRequests {
    var count = 0
    func record() { count += 1 }
}

@MainActor final class PartnerArtworkTests: XCTestCase {
    func testPotentialRankBoundariesAndBundledBadges() {
        let cases: [(String, Int?)] = [("0.000", 0), ("3.499", 0), ("3.500", 1), ("6.999", 1), ("7.000", 2), ("9.999", 2), ("10.000", 3), ("10.999", 3), ("11.000", 4), ("11.999", 4), ("12.000", 5), ("12.499", 5), ("12.500", 6), ("12.999", 6), ("13.000", 7), ("13.999", 7), ("—", nil), ("-1", nil), ("nan", nil)]
        for (text, expected) in cases { XCTAssertEqual(B50PosterRenderer.potentialRank(text), expected, text) }
        for rank in (0...7).map(String.init) + ["off"] { XCTAssertNotNil(UIImage(named: "PotentialRank" + rank), rank) }
    }
    func testPortraitUsesOfficialURLAndPersistentCacheWithoutCrossPartnerFallback() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let data = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
        }.pngData())
        let requests = PortraitRequests()
        let loader = PartnerArtworkLoader(folder: folder) { url in
            XCTAssertEqual(url.absoluteString, "https://webassets.lowiro.com/chr/partner_awaken.png")
            await requests.record(); return data
        }
        let first = await loader.image(identifier: "partner_awaken")
        let cached = await loader.image(identifier: "partner_awaken")
        XCTAssertNotNil(first); XCTAssertNotNil(cached)
        let count = await requests.count; XCTAssertEqual(count, 1)
        let offline = PartnerArtworkLoader(folder: folder) { _ in throw URLError(.notConnectedToInternet) }
        let restored = await offline.image(identifier: "partner_awaken")
        let other = await offline.image(identifier: "another_partner")
        XCTAssertNotNil(restored); XCTAssertNil(other)
    }
    func testInvalidIdentifiersNeverFetchAndInvalidImagesAreNotCached() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let requests = PortraitRequests()
        let loader = PartnerArtworkLoader(folder: folder) { _ in await requests.record(); return Data("not an image".utf8) }
        for identifier in ["../secret", "https://example.com/token", "", "a/b", "a?x", String(repeating: "a", count: 257)] {
            let image = await loader.image(identifier: identifier); XCTAssertNil(image)
        }
        let count = await requests.count; XCTAssertEqual(count, 0)
        let bad = await loader.image(identifier: "valid_id"); XCTAssertNil(bad)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
}
