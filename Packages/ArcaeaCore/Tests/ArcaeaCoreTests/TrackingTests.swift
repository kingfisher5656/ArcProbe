import Foundation
import XCTest
import CSQLite
@testable import ArcaeaCore

final class TrackingTests: XCTestCase {
    func testDisablingMinimumIsImmediateSharedAndReversible() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let store = try TrackingStore(url: url)
        let other = try TrackingStore(url: url)
        let now = Date()
        XCTAssertTrue(try store.status().minimumIntervalEnabled)
        let first = try store.acquire(generation: nil, now: now)
        try store.commit(lease: first, now: now) { 1 }
        try store.setMinimumIntervalEnabled(false)
        XCTAssertFalse(try other.status().minimumIntervalEnabled)
        XCTAssertNil(try other.status().nextEligibleAt)
        let second = try other.acquire(generation: nil, now: now.addingTimeInterval(1))
        XCTAssertThrowsError(try store.acquire(generation: nil, now: now.addingTimeInterval(2))) {
            XCTAssertEqual($0 as? TrackingError, .alreadyFetching)
        }
        try other.commit(lease: second, now: now.addingTimeInterval(2)) { 0 }
        try store.setMinimumIntervalEnabled(true)
        XCTAssertThrowsError(try other.acquire(generation: nil, now: now.addingTimeInterval(3))) {
            XCTAssertEqual($0 as? TrackingError, .cooldown(until: now.addingTimeInterval(61)))
        }
    }

    func testDisablingMinimumPreservesServerAndFailureBackoffAcrossAccountReplacement() throws {
        for status: FetchStatus in [.rateLimited, .offline] {
            let store = try TrackingStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite"))
            let now = Date()
            let lease = try store.acquire(generation: nil, now: now)
            let until = now.addingTimeInterval(status == .rateLimited ? 180 : 60)
            try store.finish(lease: lease, status: status, now: now, cooldownUntil: status == .rateLimited ? until : nil)
            try store.setMinimumIntervalEnabled(false)
            try store.bind(configuration: nil)
            XCTAssertFalse(try store.status().minimumIntervalEnabled)
            XCTAssertEqual(try store.status().nextEligibleAt, until)
            XCTAssertThrowsError(try store.acquire(generation: nil, now: now.addingTimeInterval(1))) {
                XCTAssertEqual($0 as? TrackingError, .cooldown(until: until))
            }
            _ = try store.acquire(generation: nil, now: until.addingTimeInterval(1))
        }
    }

    func testUpgradePreservesUnclassifiedOutstandingCooldown() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let until = Date().addingTimeInterval(180)
        // Older payload has no preference or separate cooldown provenance.
        let data = try JSONSerialization.data(withJSONObject: [
            "isActive": false, "consecutiveFailures": 0,
            "nextEligibleAt": until.timeIntervalSinceReferenceDate
        ])
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE tracking_state(id INTEGER PRIMARY KEY, payload BLOB NOT NULL)", nil, nil, nil), SQLITE_OK)
        let hex = data.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(sqlite3_exec(db, "INSERT INTO tracking_state VALUES(1, X'\(hex)')", nil, nil, nil), SQLITE_OK)
        let store = try TrackingStore(url: url)
        XCTAssertTrue(try store.status().minimumIntervalEnabled)
        try store.setMinimumIntervalEnabled(false)
        XCTAssertEqual(try store.status().nextEligibleAt, until)
        let reopened = try TrackingStore(url: url)
        XCTAssertFalse(try reopened.status().minimumIntervalEnabled)
        XCTAssertEqual(try reopened.status().nextEligibleAt, until)
    }

    func testTwoConnectionsEnforceLeaseRateLimitAndPersistCooldown() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let first = try TrackingStore(url: url)
        let second = try TrackingStore(url: url)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let lease = try first.acquire(generation: nil, now: now)
        XCTAssertThrowsError(try second.acquire(generation: nil, now: now)) { XCTAssertEqual($0 as? TrackingError, .alreadyFetching) }
        try first.finish(lease: lease, status: .rateLimited, now: now, cooldownUntil: now.addingTimeInterval(180))
        XCTAssertThrowsError(try second.acquire(generation: nil, now: now.addingTimeInterval(70))) { XCTAssertEqual($0 as? TrackingError, .cooldown(until: now.addingTimeInterval(180))) }
        XCTAssertEqual(try second.status().nextEligibleAt, now.addingTimeInterval(180))
    }

    func testGenerationStopRejectsCommitAndExpiredLeaseRecovers() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let store = try TrackingStore(url: url)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let generation = try store.start()
        let lease = try store.acquire(generation: generation, now: now)
        try store.stop()
        var committed = false
        XCTAssertThrowsError(try store.commit(lease: lease, now: now) { committed = true; return 1 })
        XCTAssertFalse(committed)
        let next = try store.start()
        XCTAssertThrowsError(try store.acquire(generation: generation, now: now.addingTimeInterval(70))) { XCTAssertEqual($0 as? TrackingError, .staleGeneration) }
        let recovered = try store.acquire(generation: next, now: now.addingTimeInterval(70))
        XCTAssertNotEqual(recovered.id, lease.id)
    }

    func testSuccessfulDuplicateFetchDoesNotMoveLastNewPlay() throws {
        let store = try TrackingStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite"))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try store.acquire(generation: nil, now: now)
        _ = try store.commit(lease: first, now: now, latestPlay: now.addingTimeInterval(-20)) { 1 }
        let second = try store.acquire(generation: nil, now: now.addingTimeInterval(70))
        _ = try store.commit(lease: second, now: now.addingTimeInterval(70), latestPlay: now.addingTimeInterval(-10)) { 0 }
        XCTAssertEqual(try store.status().lastNewPlayAt, now.addingTimeInterval(-20))
        XCTAssertEqual(try store.status().lastSuccessAt, now.addingTimeInterval(70))
    }
    func testAccountReplacementClearsDiagnosticsAndGenerationButKeepsCooldown() throws {
        let store = try TrackingStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite"))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let generation = try store.start()
        let lease = try store.acquire(generation: generation, now: now)
        _ = try store.commit(lease: lease, now: now, latestPlay: now) { 1 }
        try store.bind(configuration: RecentConfiguration(observer: AccountID("online:8"), target: AccountID("online:7"), mode: .friendAccount))
        let state = try store.status()
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.generation)
        XCTAssertNil(state.lastPlayAt)
        XCTAssertNil(state.lastSuccessAt)
        XCTAssertEqual(state.nextEligibleAt, now.addingTimeInterval(60))
    }

}
