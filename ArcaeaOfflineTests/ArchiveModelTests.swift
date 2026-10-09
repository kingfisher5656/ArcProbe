import XCTest
import ArcaeaCore
@testable import ArcaeaOffline

@MainActor
final class ArchiveModelTests: XCTestCase {
    func testManualAddPersistsAndKeepsUnknownDateAndJudgments() throws {
        let model = try makeModel()
        try model.save(ScoreDraft(chartID: chart, score: 9_900_000))
        XCTAssertEqual(model.observations.count, 1)
        XCTAssertNil(model.observations.first?.values.playedAt)
        XCTAssertNil(model.observations.first?.values.judgments)
        let reopened = try ArchiveModel(store: model.store, catalog: model.catalog)
        XCTAssertEqual(reopened.observations.first?.values.score, 9_900_000)
    }
    func testDeleteThenUndoRestoresScoreWithoutTouchingOfficialHistory() throws {
        let model = try makeModel()
        try model.save(ScoreDraft(chartID: chart, score: 9_900_000))
        let play = try XCTUnwrap(model.observations.first)
        try model.delete(play)
        XCTAssertTrue(model.observations.isEmpty)
        try model.undoLastChange()
        XCTAssertEqual(model.observations.first?.values.score, 9_900_000)
        XCTAssertTrue(model.officialHistory.isEmpty)
    }
    func testCorrectionLowersBestAndResetRestoresImportedBest() throws {
        let model = try makeModel()
        let remote = ScoreObservation(id: ObservationID("remote:1"), accountID: AccountID("local"), chartID: chart, source: .officialImport, values: ScoreValues(score: 9_900_000), firstSeenAt: Date())
        _ = try model.store.apply(batch: ImportBatch(profile: AccountProfile(id: AccountID("local")), observations: [remote]))
        try model.reload()
        try model.save(ScoreDraft(chartID: chart, score: 9_700_000), correctingBest: true)
        XCTAssertEqual(model.bestScores.first?.values.score, 9_700_000)
        try model.resetBest(chart)
        XCTAssertEqual(model.bestScores.first?.values.score, 9_900_000)
    }
    func testScoreOnlyEditPreservesRemoteGaugeHealthAndTimestampOrigin() throws {
        let model = try makeModel()
        let values = ScoreValues(score: 9_900_000, playedAt: SourceTimestamp(value: 1_700_000_000, unit: .seconds), modifier: 2, health: 85)
        let remote = ScoreObservation(id: ObservationID("remote:gauge"), accountID: AccountID("local"), chartID: chart, source: .officialImport, values: values, firstSeenAt: Date())
        _ = try model.store.apply(batch: ImportBatch(profile: AccountProfile(id: AccountID("local")), observations: [remote]))
        try model.reload()
        try model.save(ScoreDraft(chartID: chart, score: 9_850_000, playedAt: values.playedAt?.date), editing: remote.id)
        let edited = try XCTUnwrap(model.observations.first?.values)
        XCTAssertEqual(edited.modifier, 2)
        XCTAssertEqual(edited.health, 85)
        XCTAssertEqual(edited.playedAt?.origin, .server)
    }
    func testRecentAttemptRatingUsesItsOwnScoreAndClearInsteadOfChartBest() throws {
        let model = try makeModel()
        try model.save(ScoreDraft(chartID: chart, score: 9_900_000, playClear: .normal, bestClear: .normal))
        let lower = ScoreValues(score: 9_500_000, playClear: .trackLost)
        XCTAssertEqual(model.playRatingUnits(chart, values: lower), 6_000_000)
        XCTAssertEqual(model.ranking?.rows.first?.ratingUnits, 7_020_000)
    }
    func testRecentCaptureRemainsVisibleWhenFullImportProvidesCanonicalDetails() throws {
        let model = try makeModel()
        let profile = AccountProfile(id: AccountID("local"))
        let time = SourceTimestamp(value: 1_700_000_000, unit: .seconds)
        let imported = ScoreObservation(id: ObservationID("shared:play"), accountID: profile.id, chartID: chart, source: .officialImport, values: ScoreValues(score: 9_900_000, playedAt: time, judgments: Judgments(pure: 1000, far: 0, lost: 0)), firstSeenAt: Date())
        let recent = ScoreObservation(id: imported.id, accountID: profile.id, chartID: chart, source: .officialRecent, values: ScoreValues(score: 9_900_000, playedAt: time), firstSeenAt: Date())
        _ = try model.store.apply(batch: ImportBatch(profile: profile, observations: [imported]))
        _ = try model.store.apply(batch: ImportBatch(profile: profile, observations: [recent], kind: .recent))
        try model.reload()
        XCTAssertEqual(model.observations.count, 1)
        XCTAssertEqual(model.observations.first?.original.source, .officialImport)
        XCTAssertEqual(model.recentObservations.count, 1)
    }
    func testGraphContinuationRebuildsFromSyncBaselineAndRestores() throws {
        let model = try makeModel()
        let account = AccountID("local")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let baseline = ScoreObservation(id: ObservationID("baseline"), accountID: account, chartID: chart, source: .officialImport,
            values: ScoreValues(score: 9_800_000), firstSeenAt: date)
        let anchor = PotentialPoint(accountID: account, sourceID: "anchor", timestamp: SourceTimestamp(value: 1_700_000_000, unit: .seconds), value: PotentialValue(rawValue: 12000, decimalPlaces: 3), firstSeenAt: date)
        _ = try model.store.apply(batch: ImportBatch(profile: AccountProfile(id: account), observations: [baseline], potentialPoints: [anchor], importedAt: date, kind: .full))
        try model.reload()
        XCTAssertTrue(model.localHistory.isEmpty)
        try model.save(ScoreDraft(chartID: chart, score: 10_000_000, playedAt: date.addingTimeInterval(100)))
        XCTAssertEqual(model.localHistory.last?.value.rawValue, 12_033_333)
        XCTAssertEqual(model.officialHistory, [anchor])
        let history = model.localHistory
        let restored = try makeModel()
        try restored.restoreBackup(ArchiveBackup(store: model.store).export())
        XCTAssertEqual(restored.localHistory, history)
        XCTAssertEqual(restored.potentialSyncDate, date)
    }

    func testInvalidScoreLeavesArchiveUnchanged() throws {
        let model = try makeModel()
        XCTAssertThrowsError(try model.save(ScoreDraft(chartID: chart, score: -1))) { error in
            guard case ArchiveError.invalidRecord = error else { return XCTFail("Invalid scores must return an archive validation error") }
        }
        XCTAssertTrue(model.observations.isEmpty)
    }
    private var chart: ChartID { ChartID(songID: "testchart", difficulty: .future) }
    private func makeModel() throws -> ArchiveModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("archive.sqlite")
        let catalog = ChartCatalog(charts: [ChartMetadata(id: chart, constant: ChartConstant(tenths: 100), provenance: "synthetic")])
        return try ArchiveModel(store: ArchiveStore(url: url, catalog: catalog), catalog: catalog)
    }
}
