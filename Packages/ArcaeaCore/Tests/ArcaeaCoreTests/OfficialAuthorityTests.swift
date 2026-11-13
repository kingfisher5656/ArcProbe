import XCTest
@testable import ArcaeaCore

final class OfficialAuthorityTests: XCTestCase {
    private let extra = ChartID(songID: "unreported", difficulty: .future)
    private func full(_ scores: [ScoreObservation], at: Date = testDate.addingTimeInterval(100), history: [PotentialPoint] = []) -> ImportBatch {
        ImportBatch(profile: AccountProfile(id: testAccount), observations: scores, potentialPoints: history, importedAt: at, kind: .full)
    }
    func testOfficialSyncRemovesHigherAndMissingLocalScoresAndResetsCorrections() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [
            observation("sheet-high", score: 10000000, at: nil, source: .consultantSheet),
            observation("lower-play", score: 9700000),
            observation("unreported", score: 10000000, chart: extra, source: .consultantSheet)
        ], importedAt: testDate, kind: .consultantSheet))
        let removedUndo = try store.applyManual(change: .add(observation("manual-high", score: 10000000, source: .manual)))
        _ = try store.applyManual(change: .override(accountID: testAccount, observationID: ObservationID("lower-play"), values: ScoreValues(score: 10000000)))
        _ = try store.applyManual(change: .correctBest(accountID: testAccount, chartID: testChart, values: ScoreValues(score: 10001000)))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: otherAccount), observations: [observation("other", score: 10000000, account: otherAccount, source: .consultantSheet)], kind: .consultantSheet))
        _ = try store.apply(batch: full([observation("official", score: 9800000, clear: .normal, source: .officialImport)]))
        let best = try XCTUnwrap(store.bestScores(accountID: testAccount).first { $0.chartID == testChart })
        XCTAssertEqual(best.values.score, 9800000)
        XCTAssertFalse(best.isBestCorrection)
        XCTAssertEqual(Set(try store.sourceObservations(accountID: testAccount).map(\.id.rawValue)), ["lower-play", "official"])
        XCTAssertEqual(try store.bestScores(accountID: otherAccount).first?.values.score, 10000000)
        XCTAssertThrowsError(try store.undo(removedUndo))
        let restored = try ArchiveStore(url: temporaryArchiveURL())
        _ = try ArchiveBackup(store: restored).validateAndRestore(data: ArchiveBackup(store: store).export())
        XCTAssertEqual(try restored.bestScores(accountID: testAccount), try store.bestScores(accountID: testAccount))
        XCTAssertNil(try restored.latestUndoToken())
    }
    func testMissingLocalChartsAndCorrectionOnlyChartAreRemovedWithoutAffectingOtherAccount() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let absent = ChartID(songID: testChart.songID, difficulty: .beyond)
        let sheet = observation("missing-sheet", score: 9900000, at: nil, chart: absent, source: .consultantSheet)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [sheet], importedAt: testDate, kind: .consultantSheet))
        let manual = observation("missing-manual", score: 9800000, chart: extra, source: .manual)
        let added = try store.applyManual(change: .add(manual))
        _ = try store.applyManual(change: .override(accountID: testAccount, observationID: manual.id, values: ScoreValues(score: 10000000)))
        _ = try store.applyManual(change: .suppress(accountID: testAccount, observationID: sheet.id))
        let correctionOnly = ChartID(songID: "correction-only", difficulty: .past)
        _ = try store.applyManual(change: .correctBest(accountID: testAccount, chartID: correctionOnly, values: ScoreValues(score: 9900000)))
        let other = observation("other-manual", account: otherAccount, chart: extra, source: .manual)
        let otherUndo = try store.applyManual(change: .add(other))
        _ = try store.apply(batch: full([observation("official", source: .officialImport)]))
        XCTAssertEqual(try store.sourceObservations(accountID: testAccount).map(\.id.rawValue), ["official"])
        XCTAssertEqual(try store.bestScores(accountID: testAccount).map(\.chartID), [testChart])
        XCTAssertEqual(try store.sourceObservations(accountID: otherAccount), [other])
        XCTAssertEqual(try store.latestUndoToken(), otherUndo)
        XCTAssertThrowsError(try store.undo(added))
        let restored = try ArchiveStore(url: temporaryArchiveURL())
        _ = try ArchiveBackup(store: restored).validateAndRestore(data: ArchiveBackup(store: store).export())
        XCTAssertEqual(try restored.bestScores(accountID: testAccount).map(\.chartID), [testChart])
        try restored.undo(otherUndo)
        XCTAssertTrue(try restored.sourceObservations(accountID: otherAccount).isEmpty)
    }
    func testEmptyOfficialSnapshotRemovesLocalScoresButFailedImportRollsBack() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let sheet = observation("missing", at: nil, chart: extra, source: .consultantSheet)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [sheet], importedAt: testDate, kind: .consultantSheet))
        _ = try store.applyManual(change: .correctBest(accountID: testAccount, chartID: extra, values: ScoreValues(score: 10000000)))
        let bad = PotentialPoint(accountID: otherAccount, sourceID: "bad", timestamp: SourceTimestamp(value: 1800000000, unit: .seconds), value: PotentialValue(rawValue: 12, decimalPlaces: 0), firstSeenAt: testDate)
        XCTAssertThrowsError(try store.apply(batch: full([], history: [bad])))
        XCTAssertEqual(try store.sourceObservations(accountID: testAccount), [sheet])
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 10000000)
        XCTAssertNotNil(try store.latestUndoToken())
        _ = try store.apply(batch: full([]))
        XCTAssertTrue(try store.sourceObservations(accountID: testAccount).isEmpty)
        XCTAssertTrue(try store.bestScores(accountID: testAccount).isEmpty)
        XCTAssertTrue(try store.localPotentialHistory(accountID: testAccount).isEmpty)
        XCTAssertNil(try store.latestUndoToken())
    }
    func testRecentFetchDoesNotRemoveMissingLocalCharts() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let local = observation("local", chart: extra, source: .manual)
        _ = try store.applyManual(change: .add(local))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [observation("recent")], kind: .recent))
        XCTAssertTrue(try store.sourceObservations(accountID: testAccount).contains(local))
    }
    func testReimportSameOfficialObservationRemovesSuppressionsAndOverrides() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let official = observation("official", score: 9800000, source: .officialImport)
        _ = try store.apply(batch: full([official], at: testDate))
        _ = try store.applyManual(change: .override(accountID: testAccount, observationID: official.id, values: ScoreValues(score: 10000000)))
        _ = try store.applyManual(change: .suppress(accountID: testAccount, observationID: official.id))
        _ = try store.apply(batch: full([official]))
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9800000)
        XCTAssertNil(try store.latestUndoToken())
    }
    func testFailedAndOlderFullImportsCannotDeleteLocalScores() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        _ = try store.apply(batch: full([observation("official", source: .officialImport)], at: testDate))
        let local = observation("manual", score: 10000000, source: .manual)
        _ = try store.applyManual(change: .add(local))
        let bad = PotentialPoint(accountID: otherAccount, sourceID: "bad", timestamp: SourceTimestamp(value: 1800000000, unit: .seconds), value: PotentialValue(rawValue: 12, decimalPlaces: 0), firstSeenAt: testDate)
        XCTAssertThrowsError(try store.apply(batch: full([observation("new", score: 9900000, source: .officialImport)], history: [bad])))
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 10000000)
        XCTAssertThrowsError(try store.apply(batch: full([observation("old", score: 9700000, source: .officialImport)], at: testDate.addingTimeInterval(-1))))
        XCTAssertTrue(try store.sourceObservations(accountID: testAccount).contains(local))
        XCTAssertNotNil(try store.latestUndoToken())
    }
    func testOfficialHistoryReplacesLocalContinuationAndCorrectedOfficialPoint() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: ChartCatalog(charts: [ChartMetadata(id: testChart, constant: ChartConstant(tenths: 100), provenance: "test")]))
        let point = PotentialPoint(accountID: testAccount, sourceID: "point", timestamp: SourceTimestamp(value: 1800000000, unit: .seconds), value: PotentialValue(rawValue: 12000, decimalPlaces: 3), firstSeenAt: testDate)
        _ = try store.apply(batch: full([observation("official", source: .officialImport)], at: testDate, history: [point]))
        let local = ScoreObservation(id: ObservationID("sheet"), accountID: testAccount, chartID: testChart, source: .consultantSheet, values: ScoreValues(score: 10000000), firstSeenAt: testDate.addingTimeInterval(10), identityConfidence: .payloadOnly)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [local], importedAt: testDate.addingTimeInterval(10), kind: .consultantSheet))
        XCTAssertFalse(try store.localPotentialHistory(accountID: testAccount).isEmpty)
        let corrected = PotentialPoint(accountID: testAccount, sourceID: point.sourceID, timestamp: point.timestamp, value: PotentialValue(rawValue: 11999, decimalPlaces: 3), firstSeenAt: testDate.addingTimeInterval(100))
        _ = try store.apply(batch: full([observation("official", source: .officialImport)], history: [corrected]))
        XCTAssertTrue(try store.localPotentialHistory(accountID: testAccount).isEmpty)
        XCTAssertEqual(try store.potentialHistory(accountID: testAccount), [corrected])
        XCTAssertEqual(try store.potentialBaseline(accountID: testAccount)?.anchor, corrected)
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9800000)
    }
}
