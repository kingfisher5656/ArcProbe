import ArcaeaCore
import UIKit
import WebKit
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
    private func file(_ name: String, _ tab: String) -> WikiJacket {
        WikiJacket(filePage: "https://arcaea.miraheze.org/wiki/File:" + name, difficulties: tab)
    }
    private func chart(_ song: String, _ difficulty: Difficulty) -> ChartID { ChartID(songID: song, difficulty: difficulty) }
    func testBeyondJacketIsNeverUsedForBaseChart() throws {
        let base = file("Songs_vexaria.jpg", "Past/Present/Future"), beyond = file("Songs_vexaria_byd.jpg", "Beyond")
        let article = WikiSongArticle(songIDs: ["vexaria"], jackets: [base, beyond, base, beyond])
        XCTAssertEqual(article.jacket(for: chart("vexaria", .future)), base)
        XCTAssertEqual(article.jacket(for: chart("vexaria", .beyond)), beyond)
        XCTAssertNil(article.jacket(for: chart("vexaria", .eternal)))
        XCTAssertNil(WikiSongArticle(songIDs: ["vexaria"], jackets: [base]).jacket(for: chart("vexaria", .beyond)))
    }
    func testSingleUnlabelledCoverAndAmbiguousVariants() throws {
        let base = WikiJacket(filePage: "base", difficulties: "")
        XCTAssertEqual(WikiSongArticle(songIDs: ["testify"], jackets: [base, base]).jacket(for: chart("testify", .beyond)), base)
        let another = WikiJacket(filePage: "other", difficulties: "Beyond")
        let duplicate = WikiJacket(filePage: "different", difficulties: "Beyond")
        XCTAssertNil(WikiSongArticle(songIDs: ["x"], jackets: [another, duplicate]).jacket(for: chart("x", .beyond)))
    }
    // The three pages that used to be opened on every run because no tab names a difficulty.
    func testTabsNamedForSomethingOtherThanDifficulty() throws {
        let base = file("Songs_last.jpg", "Past/Present/Future"), moment = file("Songs_last_byd.jpg", "Moment"), eternity = file("Songs_lasteternity.jpg", "Eternity")
        let last = WikiSongArticle(songIDs: ["last", "lasteternity"], jackets: [base, moment, eternity, base, moment, eternity])
        XCTAssertEqual(last.jacket(for: chart("last", .past)), base)
        XCTAssertEqual(last.jacket(for: chart("last", .beyond)), moment)
        XCTAssertEqual(last.jacket(for: chart("lasteternity", .beyond)), eternity)
        XCTAssertNil(last.jacket(for: chart("last", .eternal)))
        let day = file("Songs_melodyoflove.jpg", "Day"), night = file("Songs_melodyoflove_night.jpg", "Night")
        let melody = WikiSongArticle(songIDs: ["melodyoflove"], jackets: [day, night])
        for difficulty in [Difficulty.past, .present, .future] { XCTAssertEqual(melody.jacket(for: chart("melodyoflove", difficulty)), day) }
        let english = file("Songs_solitarydream.jpg", "English"), japanese = file("Songs_solitarydream_ja.jpg", "Japanese")
        XCTAssertEqual(WikiSongArticle(songIDs: ["solitarydream"], jackets: [english, japanese]).jacket(for: chart("solitarydream", .future)), english)
        // Per-difficulty file names still lose to an explicit tab, and unknown variants stay unmatched.
        let renamed = file("Songs_ignotusafterburn.jpg", "Beyond")
        XCTAssertEqual(WikiSongArticle(songIDs: ["ignotus"], jackets: [file("Songs_ignotus.jpg", "Past/Present/Future"), renamed]).jacket(for: chart("ignotus", .beyond)), renamed)
        XCTAssertNil(WikiSongArticle(songIDs: ["x"], jackets: [file("Songs_x_a.jpg", "Day"), file("Songs_x_b.jpg", "Night")]).jacket(for: chart("x", .future)))
    }
    func testArticleScriptReadsEverySongIDOnThePage() async throws {
        final class Waiter: NSObject, WKNavigationDelegate {
            var done: CheckedContinuation<Void, Never>?
            func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done?.resume(); done = nil }
        }
        let html = #"""
        <div class="arcaeabox">
          <div class="tabber"><a role="tab" id="tabber-Moment-label">Moment</a>
            <article role="tabpanel" id="tabber-Moment" aria-labelledby="tabber-Moment-label"><div class="art-container"><a href="/wiki/File:Songs_last_byd.jpg">x</a></div></article></div>
          <div class="label">Song ID</div><div class="data">last</div><div class="data data-last">lasteternity</div>
          <div class="label">Artist</div><div class="data">onoken</div>
        </div>
        """#
        let view = WKWebView(frame: .zero), waiter = Waiter()
        view.navigationDelegate = waiter
        await withCheckedContinuation { waiter.done = $0; view.loadHTMLString(html, baseURL: URL(string: "https://arcaea.miraheze.org/wiki/Last")) }
        let result = try await view.evaluateJavaScript(WikiArtwork.articleScript)
        let json = try XCTUnwrap(result as? String)
        let article = try JSONDecoder().decode(WikiSongArticle.self, from: Data(json.utf8))
        XCTAssertEqual(article.songIDs, ["last", "lasteternity"])
        XCTAssertEqual(article.jackets, [WikiJacket(filePage: "https://arcaea.miraheze.org/wiki/File:Songs_last_byd.jpg", difficulties: "Moment")])
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
