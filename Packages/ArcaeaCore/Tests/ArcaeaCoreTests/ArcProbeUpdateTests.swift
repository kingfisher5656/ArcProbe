import XCTest
@testable import ArcaeaCore

final class ArcProbeUpdateTests: XCTestCase {
    func testConstantsRefreshReplacesRemovedEntriesAndSurvivesReopen() throws {
        let url = temporaryArchiveURL()
        let id = ChartID(songID: "example", difficulty: .future)
        let removed = ChartID(songID: "removed", difficulty: .future)
        let bundled = ChartCatalog(charts: [ChartMetadata(id: id, constant: .init(tenths: 100), title: "Kept title", provenance: "bundled"), ChartMetadata(id: removed, constant: .init(tenths: 90), provenance: "bundled")])
        let store = try ArchiveStore(url: url, catalog: bundled)
        let data = Data(#"{"example":[null,null,{"constant":10.7,"old":false}]}"#.utf8)
        let snapshot = try ConstantSnapshot.parse(data)
        try store.replaceConstants(snapshot)
        let reopened = try ArchiveStore(url: url, catalog: bundled).chartCatalog()
        XCTAssertEqual(reopened[id]?.constant?.tenths, 107)
        XCTAssertEqual(reopened[id]?.title, "Kept title")
        XCTAssertNil(reopened[removed]?.usableConstant)
        XCTAssertThrowsError(try ConstantSnapshot.parse(Data(#"{"bad":[{"constant":10.75,"old":false}]}"#.utf8)))
        XCTAssertThrowsError(try ConstantSnapshot.parse(Data("{}".utf8)))
    }

    func testNotificationTokensAreDurableSingleUseAndStopInvalidatesThem() throws {
        let url = temporaryArchiveURL()
        let store = try NotificationPulseStore(url: url)
        try store.configure(minimum: 65, maximum: 80)
        XCTAssertThrowsError(try store.configure(minimum: 20, maximum: 80))
        let generation = UUID()
        let first = try store.start(generation: generation, now: testDate, randomDelay: 70)
        let reopened = try NotificationPulseStore(url: url)
        XCTAssertEqual(try reopened.state().token, first.token)
        let next = try reopened.advance(token: first.token!, generation: generation, now: testDate.addingTimeInterval(70), randomDelay: 75)
        XCTAssertNotEqual(next?.token, first.token)
        XCTAssertNil(try store.advance(token: first.token!, generation: generation, now: testDate.addingTimeInterval(70), randomDelay: 70))
        _ = try store.stop()
        XCTAssertNil(try reopened.advance(token: next!.token!, generation: generation, now: testDate.addingTimeInterval(150), randomDelay: 70))
        XCTAssertEqual(try reopened.state().minimumSeconds, 65)
    }

    func testNotificationGenerationAndCooldownPreventStaleOrEarlyCycles() throws {
        let store = try NotificationPulseStore(url: temporaryArchiveURL())
        let generation = UUID()
        let first = try store.start(generation: generation, now: testDate, randomDelay: 70)
        XCTAssertNil(try store.advance(token: first.token!, generation: UUID(), now: testDate.addingTimeInterval(70), randomDelay: 70))
        XCTAssertNil(try store.advance(token: first.token!, generation: generation, now: testDate, randomDelay: 70))
        let next = try store.advance(token: first.token!, generation: generation, now: testDate.addingTimeInterval(70), randomDelay: 70, notBefore: testDate.addingTimeInterval(600))
        XCTAssertEqual(next?.nextAt, testDate.addingTimeInterval(600))
        let replacement = try store.start(generation: UUID(), now: testDate, randomDelay: 75)
        _ = try store.stop(expectedToken: next!.token)
        XCTAssertEqual(try store.state().token, replacement.token)
    }
}
