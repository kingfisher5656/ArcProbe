import XCTest
@testable import ArcaeaCore

final class LocalHistoryTests: XCTestCase {
    let sync = Date(timeIntervalSince1970: 1_800_000_000)
    var anchor: PotentialPoint {
        PotentialPoint(accountID: testAccount, sourceID: "official-cutoff",
            timestamp: SourceTimestamp(value: 1_799_999_900, unit: .seconds),
            value: PotentialValue(rawValue: 12345, decimalPlaces: 3), firstSeenAt: sync)
    }
    func makeStore() throws -> ArchiveStore {
        try ArchiveStore(url: temporaryArchiveURL(), catalog: ChartCatalog(charts: [
            ChartMetadata(id: testChart, constant: ChartConstant(tenths: 100), provenance: "test")
        ]))
    }
    func initial(_ store: ArchiveStore) throws {
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount),
            observations: [observation("baseline", score: 9_800_000, at: 1_600_000_000, source: .officialImport)],
            potentialPoints: [anchor], importedAt: sync, kind: .full))
    }
    func recent(_ store: ArchiveStore, score: Int = 10_000_000, at: Int64 = 1_800_000_010) throws {
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount),
            observations: [observation("recent", score: score, at: at)], importedAt: sync.addingTimeInterval(20), kind: .recent))
    }
    func testNoReconstructedPastAndNoEstimateWithoutFullSyncBaseline() throws {
        let store = try makeStore()
        try recent(store)
        XCTAssertTrue(try store.localPotentialHistory(accountID: testAccount).isEmpty)
        try initial(store)
        // Baseline is older than 2021; it must never become a local history point.
        let points = try store.localPotentialHistory(accountID: testAccount)
        XCTAssertEqual(points.count, 1)
        XCTAssertTrue(points.allSatisfy { $0.timestamp.date! > sync })
        XCTAssertEqual(try store.potentialHistory(accountID: testAccount), [anchor])
    }
    func testContinuationUsesOfficialAnchorPlusChangeFromFrozenBaseline() throws {
        let store = try makeStore(); try initial(store)
        XCTAssertTrue(try store.localPotentialHistory(accountID: testAccount).isEmpty)
        try recent(store)
        let point = try XCTUnwrap(store.localPotentialHistory(accountID: testAccount).last)
        // One chart improves by 1.0, weighted twice in a denominator of 60.
        XCTAssertEqual(point.value.rawValue, 12_345_000 + 33_333)
        _ = try store.applyManual(change: .override(accountID: testAccount, observationID: ObservationID("baseline"),
            values: ScoreValues(score: 10_100_000, playedAt: SourceTimestamp(value: 1_600_000_000, unit: .seconds))))
        XCTAssertEqual(try store.localPotentialHistory(accountID: testAccount), [point])
        XCTAssertEqual(try store.potentialHistory(accountID: testAccount), [anchor])
    }
    func testPostSyncEditsDatesDeletionAndUndoOnlyRebuildContinuation() throws {
        let store = try makeStore(); try initial(store); try recent(store)
        _ = try store.applyManual(change: .override(accountID: testAccount, observationID: ObservationID("recent"),
            values: ScoreValues(score: 9_900_000, playedAt: SourceTimestamp(value: 1_800_000_100, unit: .seconds))))
        let edited = try store.localPotentialHistory(accountID: testAccount)
        XCTAssertEqual(edited.last?.timestamp.date, sync.addingTimeInterval(100))
        XCTAssertEqual(edited.last?.value.rawValue, 12_345_000 + 16_666)
        let token = try store.applyManual(change: .suppress(accountID: testAccount, observationID: ObservationID("recent")))
        XCTAssertTrue(try store.localPotentialHistory(accountID: testAccount).isEmpty)
        try store.undo(token)
        XCTAssertEqual(try store.localPotentialHistory(accountID: testAccount), edited)
        _ = try store.applyManual(change: .override(accountID: testAccount, observationID: ObservationID("recent"),
            values: ScoreValues(score: 10_000_000, playedAt: SourceTimestamp(value: 1_799_999_000, unit: .seconds))))
        XCTAssertTrue(try store.localPotentialHistory(accountID: testAccount).isEmpty)
        XCTAssertEqual(try store.potentialHistory(accountID: testAccount), [anchor])
    }
    func testSyncBoundaryAndEarlierCorrectionCannotChangeOfficialTimeframe() throws {
        let store = try makeStore(); try initial(store)
        try recent(store, at: 1_800_000_000)
        XCTAssertTrue(try store.localPotentialHistory(accountID: testAccount).isEmpty)
        _ = try store.applyManual(change: .correctBest(accountID: testAccount, chartID: testChart,
            values: ScoreValues(score: 9_500_000, playedAt: SourceTimestamp(value: 1_799_999_999, unit: .seconds))))
        XCTAssertTrue(try store.localPotentialHistory(accountID: testAccount).isEmpty)
        XCTAssertEqual(try store.potentialHistory(accountID: testAccount), [anchor])
    }

    func testLegacyBackupNeedsNewSyncAndMalformedBaselineIsRejected() throws {
        let store = try makeStore(); try initial(store)
        let backup = try ArchiveBackup(store: store).export()
        var payload = try JSONDecoder().decode(ArchivePayload.self, from: backup)
        payload.potentialBaselines = nil
        let restored = try makeStore()
        _ = try ArchiveBackup(store: restored).validateAndRestore(data: JSONEncoder().encode(payload))
        XCTAssertNil(try restored.potentialBaseline(accountID: testAccount))
        XCTAssertEqual(try restored.potentialHistory(accountID: testAccount), [anchor])
        try recent(restored)
        XCTAssertTrue(try restored.localPotentialHistory(accountID: testAccount).isEmpty)
        payload = try JSONDecoder().decode(ArchivePayload.self, from: backup)
        payload.potentialBaselines = [PotentialBaseline(accountID: otherAccount, anchor: anchor, syncedAt: sync, scores: [])]
        XCTAssertThrowsError(try ArchiveBackup(store: restored).validateAndRestore(data: JSONEncoder().encode(payload)))
        XCTAssertEqual(try restored.potentialHistory(accountID: testAccount), [anchor])
    }
    func testSameOfficialPointAtLaterSyncRetainsCanonicalAnchorInBackup() throws {
        let store = try makeStore(); try initial(store)
        let repeated = PotentialPoint(accountID: testAccount, sourceID: anchor.sourceID,
            timestamp: anchor.timestamp, value: anchor.value, firstSeenAt: sync.addingTimeInterval(100))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount),
            observations: [observation("baseline", score: 9_800_000, at: 1_600_000_000, source: .officialImport)],
            potentialPoints: [repeated], importedAt: sync.addingTimeInterval(100), kind: .full))
        let restored = try makeStore()
        _ = try ArchiveBackup(store: restored).validateAndRestore(data: ArchiveBackup(store: store).export())
        XCTAssertEqual(try restored.potentialBaseline(accountID: testAccount)?.anchor, anchor)
        XCTAssertEqual(try restored.potentialBaseline(accountID: testAccount)?.syncedAt, sync.addingTimeInterval(100))
    }

    func testResyncAdvancesAnchorAndBackupRetainsBaseline() throws {
        let store = try makeStore(); try initial(store); try recent(store)
        let newer = PotentialPoint(accountID: testAccount, sourceID: "new-official",
            timestamp: SourceTimestamp(value: 1_800_000_200, unit: .seconds),
            value: PotentialValue(rawValue: 12400, decimalPlaces: 3), firstSeenAt: sync.addingTimeInterval(200))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount),
            observations: [observation("recent", score: 10_000_000, at: 1_800_000_010, source: .officialImport)],
            potentialPoints: [newer], importedAt: sync.addingTimeInterval(210), kind: .full))
        XCTAssertTrue(try store.localPotentialHistory(accountID: testAccount).isEmpty)
        _ = try store.applyManual(change: .correctBest(accountID: testAccount, chartID: testChart,
            values: ScoreValues(score: 9_800_000, playedAt: SourceTimestamp(value: 1_800_000_300, unit: .seconds))))
        let history = try store.localPotentialHistory(accountID: testAccount)
        XCTAssertEqual(history.last?.value.rawValue, 12_400_000 - 33_333)
        let restored = try makeStore()
        _ = try ArchiveBackup(store: restored).validateAndRestore(data: ArchiveBackup(store: store).export())
        XCTAssertEqual(try restored.localPotentialHistory(accountID: testAccount), history)
        XCTAssertEqual(try restored.potentialHistory(accountID: testAccount), [anchor, newer])
        XCTAssertTrue(try restored.localPotentialHistory(accountID: otherAccount).isEmpty)
    }
}
