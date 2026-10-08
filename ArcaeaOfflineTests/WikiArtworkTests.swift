import ArcaeaCore
import UIKit
import XCTest
@testable import ArcaeaOffline

@MainActor final class WikiArtworkTests: XCTestCase {
    func testFiveHundredPixelOriginalIsAcceptedWithoutUpscaling() throws {
        let chart = ChartID(songID: "lost-size-test-" + UUID().uuidString, difficulty: .future)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 500), format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 500, height: 500))
        }
        try LibraryResources.shared.saveWikiCover(XCTUnwrap(original.pngData()), chart: chart)
        XCTAssertEqual(LibraryResources.shared.image(chart: chart, officialIdentifier: nil)?.cgImage?.width, 500)
    }
    func testBeyondJacketIsNeverUsedForBaseChart() throws {
        let base = WikiJacket(filePage: "https://arcaea.miraheze.org/wiki/File:Songs_vexaria.jpg", difficulties: "Past/Present/Future")
        let beyond = WikiJacket(filePage: "https://arcaea.miraheze.org/wiki/File:Songs_vexaria_byd.jpg", difficulties: "Beyond")
        let article = WikiSongArticle(songID: "vexaria", jackets: [base, beyond, base, beyond])
        XCTAssertEqual(article.jacket(for: .future), base)
        XCTAssertEqual(article.jacket(for: .beyond), beyond)
        XCTAssertNil(article.jacket(for: .eternal))
        XCTAssertNil(WikiSongArticle(songID: "vexaria", jackets: [base]).jacket(for: .beyond))
    }
    func testSingleUnlabelledCoverAndAmbiguousVariants() throws {
        let base = WikiJacket(filePage: "base", difficulties: "")
        XCTAssertEqual(WikiSongArticle(songID: "testify", jackets: [base, base]).jacket(for: .beyond), base)
        let another = WikiJacket(filePage: "other", difficulties: "Beyond")
        let duplicate = WikiJacket(filePage: "different", difficulties: "Beyond")
        XCTAssertNil(WikiSongArticle(songID: "x", jackets: [another, duplicate]).jacket(for: .beyond))
    }
    func testOnlyOriginalWikiImageURLsAreAccepted() {
        XCTAssertNotNil(WikiArtwork.imageURL("https://static.wikitide.net/arcaeawiki/e/ef/Songs_vexaria.jpg"))
        for url in ["https://example.com/arcaeawiki/a.jpg", "https://static.wikitide.net/arcaeawiki/thumb/e/ef/a.jpg/256px-a.jpg", "http://static.wikitide.net/arcaeawiki/a.jpg", "https://user@static.wikitide.net/arcaeawiki/a.jpg"] { XCTAssertNil(WikiArtwork.imageURL(url)) }
        XCTAssertNil(WikiArtwork.wikiURL("https://arcaea.miraheze.org/wiki/Vexaria?action=edit"))
    }
    func testCachePreservesOriginalResolutionAndSeparatesDifficulty() throws {
        let id = "wiki-test-" + UUID().uuidString
        let base = ChartID(songID: id, difficulty: .future), beyond = ChartID(songID: id, difficulty: .beyond)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 768, height: 768), format: format).image { context in
            UIColor.purple.setFill(); context.fill(CGRect(x: 0, y: 0, width: 768, height: 768))
        }
        try LibraryResources.shared.saveWikiCover(XCTUnwrap(original.pngData()), chart: beyond)
        XCTAssertFalse(LibraryResources.shared.hasWikiCover(base))
        XCTAssertEqual(LibraryResources.shared.image(chart: beyond, officialIdentifier: nil)?.cgImage?.width, 768)
        XCTAssertThrowsError(try LibraryResources.shared.saveWikiCover(Data("bad".utf8), chart: beyond))
        XCTAssertEqual(LibraryResources.shared.image(chart: beyond, officialIdentifier: nil)?.cgImage?.width, 768)
    }
}
