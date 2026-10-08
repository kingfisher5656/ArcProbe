import Foundation
import XCTest
@testable import ArcaeaCore

final class TrackingTests: XCTestCase {
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
