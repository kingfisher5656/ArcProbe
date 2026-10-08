import UIKit
import XCTest
@testable import ArcaeaOffline

@MainActor final class CoverImageLoaderTests: XCTestCase {
    func testDownsamplingFallbackCacheAndInvalidation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let loader = CoverImageLoader(folder: folder)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 768, height: 768), format: format).image { context in
            UIColor.purple.setFill(); context.fill(CGRect(x: 0, y: 0, width: 768, height: 768))
        }
        let data = try XCTUnwrap(image.pngData())
        let official = folder.appendingPathComponent(LibraryResources.coverKey("official") + ".jpg")
        try data.write(to: official)
        let first = await loader.image(identifiers: ["wiki:missing:3", "official"], pixels: 256, revision: 0)
        XCTAssertEqual(first?.cgImage?.width, 256)
        try FileManager.default.removeItem(at: official)
        let cached = await loader.image(identifiers: ["wiki:missing:3", "official"], pixels: 256, revision: 0)
        XCTAssertTrue(first === cached)
        let invalidated = await loader.image(identifiers: ["official"], pixels: 256, revision: 1)
        XCTAssertNil(invalidated)
        try data.write(to: official)
        let missingCached = await loader.image(identifiers: ["official"], pixels: 256, revision: 1)
        XCTAssertNil(missingCached)
        let refreshed = await loader.image(identifiers: ["official"], pixels: 512, revision: 2)
        XCTAssertEqual(refreshed?.cgImage?.width, 512)
    }
}
