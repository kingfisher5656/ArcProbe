import Foundation
import XCTest
import CSQLite
@testable import ArcaeaCore

final class TrackingTests: XCTestCase {
    private let configuration = RecentConfiguration(observer: otherAccount, target: testAccount, mode: .friendAccount)
    private func makeStore() throws -> (TrackingStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let store = try TrackingStore(url: url)
        try store.bind(configuration: configuration)
        return (store, url)
    }

    func testTwoConnectionsShareLeaseAndCooldown() throws {
        let (store, url) = try makeStore()
        let other = try TrackingStore(url: url)
        let now = Date()
        let lease = try store.acquire(now: now)
        XCTAssertThrowsError(try other.acquire(now: now.addingTimeInterval(1))) { XCTAssertEqual($0 as? TrackingError, .alreadyFetching) }
        try store.finish(lease: lease, status: .rateLimited, now: now, cooldownUntil: now.addingTimeInterval(300))
        XCTAssertThrowsError(try other.acquire(now: now.addingTimeInterval(120))) {
            XCTAssertEqual($0 as? TrackingError, .cooldown(until: now.addingTimeInterval(300)))
        }
        XCTAssertNoThrow(try other.acquire(now: now.addingTimeInterval(301)))
    }

    func testManualRequestsAreNotHeldToThePollInterval() throws {
        let (store, _) = try makeStore()
        let now = Date()
        let first = try store.acquire(now: now)
        try store.commit(lease: first, now: now) { 1 }
        let second = try store.acquire(now: now.addingTimeInterval(2))
        try store.commit(lease: second, now: now.addingTimeInterval(3)) { 0 }
        XCTAssertNil(try store.status().cooldownUntil)
    }

    func testAbandonedLeaseExpiresSoTrackingRecovers() throws {
        let (store, _) = try makeStore()
        let now = Date()
        let abandoned = try store.acquire(now: now, deadline: 20)
        XCTAssertThrowsError(try store.commit(lease: abandoned, now: now.addingTimeInterval(30)) { 1 }) {
            XCTAssertEqual($0 as? TrackingError, .expiredLease)
        }
        XCTAssertNoThrow(try store.acquire(now: now.addingTimeInterval(30)))
    }

    func testFailuresBackOffGraduallyAndSuccessResets() throws {
        let (store, _) = try makeStore()
        var now = Date()
        for expected in [60.0, 120, 240, 300, 300] {
            let lease = try store.acquire(now: now)
            try store.finish(lease: lease, status: .failed, now: now)
            XCTAssertEqual(try store.status().cooldownUntil, now.addingTimeInterval(expected))
            now.addTimeInterval(expected + 1)
        }
        let lease = try store.acquire(now: now)
        try store.commit(lease: lease, now: now) { 0 }
        XCTAssertEqual(try store.status().consecutiveFailures, 0)
        // Offline requests never reached the server, so they add no backoff.
        let offline = try store.acquire(now: now.addingTimeInterval(400))
        try store.finish(lease: offline, status: .offline, now: now.addingTimeInterval(400))
        XCTAssertNoThrow(try store.acquire(now: now.addingTimeInterval(401)))
    }

    func testPollWaitsForScheduleAndNewestSessionWins() throws {
        let (store, _) = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try store.start(now: now)
        XCTAssertEqual(try store.beginPoll(session: first, now: now), .fetch)
        XCTAssertEqual(try store.completePoll(session: first, status: .unchanged, now: now, interval: 70), .wait(seconds: 70))
        XCTAssertEqual(try store.beginPoll(session: first, now: now.addingTimeInterval(30)), .wait(seconds: 40))
        // Reopen: the schedule carries over to the new session.
        try store.stop(now: now.addingTimeInterval(31))
        let second = try store.start(now: now.addingTimeInterval(32))
        XCTAssertEqual(try store.beginPoll(session: second, now: now.addingTimeInterval(32)), .wait(seconds: 38))
        XCTAssertEqual(try store.beginPoll(session: first, now: now.addingTimeInterval(70)), .stop(.superseded))
        XCTAssertEqual(try store.completePoll(session: first, status: .success, now: now.addingTimeInterval(70)), .stop(.superseded))
        XCTAssertEqual(try store.beginPoll(session: second, now: now.addingTimeInterval(70)), .fetch)
        XCTAssertEqual(try store.beginPoll(session: UUID(), now: now.addingTimeInterval(70)), .stop(.superseded))
    }

    func testFirstPollAfterLongBreakFetchesImmediately() throws {
        let (store, _) = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = try store.start(now: now)
        _ = try store.completePoll(session: old, status: .unchanged, now: now, interval: 70)
        try store.stop(now: now.addingTimeInterval(10))
        let later = now.addingTimeInterval(86_400)
        let session = try store.start(now: later)
        XCTAssertEqual(try store.beginPoll(session: session, now: later), .fetch)
    }

    func testClosingCountsOnlyRequestsSentAfterClosing() throws {
        let (store, _) = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = try store.start(now: now)
        let early = try store.acquire(now: now)
        try store.commit(lease: early, now: now) { 0 }
        try store.stop(now: now.addingTimeInterval(5))
        // The request above started before closing, so it is not a closing check.
        XCTAssertEqual(try store.completePoll(session: session, status: .unchanged, now: now.addingTimeInterval(6)), .wait(seconds: 60))
        XCTAssertEqual(try store.status().closingPollsRemaining, 2)
        var time = now.addingTimeInterval(66)
        // A check that could not go out does not count either.
        XCTAssertEqual(try store.beginPoll(session: session, now: time), .fetch)
        XCTAssertEqual(try store.completePoll(session: session, status: .offline, now: time), .wait(seconds: 60))
        XCTAssertEqual(try store.status().closingPollsRemaining, 2)
        for remaining in [1, 0] {
            time.addTimeInterval(60)
            XCTAssertEqual(try store.beginPoll(session: session, now: time), .fetch)
            let lease = try store.acquire(now: time)
            try store.commit(lease: lease, now: time) { 0 }
            let decision = try store.completePoll(session: session, status: .unchanged, now: time)
            XCTAssertEqual(decision, remaining == 0 ? .stop(.finished) : .wait(seconds: 60))
        }
        XCTAssertEqual(try store.beginPoll(session: session, now: time.addingTimeInterval(60)), .stop(.finished))
    }

    func testClosingLoopGivesUpAfterLimit() throws {
        let (store, _) = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = try store.start(now: now)
        try store.stop(now: now)
        XCTAssertEqual(try store.beginPoll(session: session, now: now.addingTimeInterval(TrackingPolicy.closingLimit + 1)), .stop(.finished))
    }

    func testAttentionEndsSessionAndUnconfiguredAccountCannotPoll() throws {
        let (store, _) = try makeStore()
        let session = try store.start()
        XCTAssertEqual(try store.completePoll(session: session, status: .attentionRequired), .stop(.needsAttention))
        XCTAssertFalse(try store.status().isActive)
        try store.bind(configuration: nil)
        let unbound = try store.start()
        XCTAssertEqual(try store.beginPoll(session: unbound), .stop(.notConfigured))
    }

    func testStalledWhenLoopGoesQuietWhileOpen() throws {
        let (store, _) = try makeStore()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(try store.status().isStalled(now: now))
        let session = try store.start(now: now)
        _ = try store.beginPoll(session: session, now: now)
        _ = try store.completePoll(session: session, status: .unchanged, now: now, interval: 70)
        XCTAssertFalse(try store.status().isStalled(now: now.addingTimeInterval(100)))
        XCTAssertTrue(try store.status().isStalled(now: now.addingTimeInterval(70 + TrackingPolicy.stallGrace + 1)))
        try store.stop(now: now.addingTimeInterval(200))
        XCTAssertFalse(try store.status().isStalled(now: now.addingTimeInterval(1_000)))
    }

    func testSuccessfulDuplicateFetchDoesNotMoveLastNewPlay() throws {
        let (store, _) = try makeStore()
        let now = Date()
        let first = try store.acquire(now: now)
        try store.commit(lease: first, now: now, latestPlay: now.addingTimeInterval(-30)) { 1 }
        let second = try store.acquire(now: now.addingTimeInterval(70))
        try store.commit(lease: second, now: now.addingTimeInterval(70), latestPlay: now.addingTimeInterval(-30)) { 0 }
        XCTAssertEqual(try store.status().lastNewPlayAt, now.addingTimeInterval(-30))
        XCTAssertEqual(try store.status().lastStatus, .unchanged)
    }

    func testAccountReplacementEndsSessionButKeepsCooldown() throws {
        let (store, _) = try makeStore()
        let now = Date()
        let session = try store.start(now: now)
        let lease = try store.acquire(now: now)
        try store.finish(lease: lease, status: .rateLimited, now: now, cooldownUntil: now.addingTimeInterval(500))
        try store.bind(configuration: RecentConfiguration(observer: testAccount, target: testAccount, mode: .ownAccountTesting))
        let status = try store.status()
        XCTAssertFalse(status.isActive)
        XCTAssertNil(status.session)
        XCTAssertNil(status.lastSuccessAt)
        XCTAssertEqual(status.cooldownUntil, now.addingTimeInterval(500))
        XCTAssertEqual(try store.beginPoll(session: session, now: now), .stop(.superseded))
    }

    func testStateWrittenByOlderVersionStillLoads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        _ = try TrackingStore(url: url)
        // Shape written by 0.2.x, including a status that no longer exists.
        let legacy = #"{"observer":"observer-456","target":"main-123","isActive":true,"generation":"8E0D7A0E-7C1B-4C0B-9C39-2B0E5C1B7A11","lastAttemptAt":700000000,"nextEligibleAt":700000060,"savedMinimumIntervalEnabled":true,"protectedCooldownUntil":700000900,"lastStatus":"staleGeneration","consecutiveFailures":2}"#
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO tracking_state(id,payload) VALUES(1,?)", -1, &statement, nil), SQLITE_OK)
        let data = Data(legacy.utf8)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
        sqlite3_finalize(statement); sqlite3_close(database)
        let status = try TrackingStore(url: url).status()
        XCTAssertEqual(status.observer, otherAccount)
        XCTAssertEqual(status.target, testAccount)
        XCTAssertFalse(status.isActive)
        XCTAssertNil(status.lastStatus)
        XCTAssertEqual(status.cooldownUntil, Date(timeIntervalSinceReferenceDate: 700_000_900))
    }
}
