import XCTest
@testable import ArcaeaCore

final class ManualChangesTests: XCTestCase {
    func testModifierBitmaskIsPreservedAndOutsideUnsigned16BitRangeIsRejected() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let original = ScoreObservation(id: ObservationID("mask"), accountID: testAccount, chartID: testChart,
            source: .manual, values: ScoreValues(score: 9_800_000, modifier: 32_768, health: 75),
            firstSeenAt: testDate, identityConfidence: .manual)
        _ = try store.applyManual(change: .add(original))
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.modifier, 32_768)
        XCTAssertThrowsError(try store.applyManual(change: .override(accountID: testAccount, observationID: original.id,
            values: ScoreValues(score: 9_800_000, modifier: 65_536))))
    }

    func testFirstOfflineManualAddCreatesProfileAtomicallyAndUndoRemovesEmptyProfile() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        XCTAssertThrowsError(try store.applyManual(change: .add(observation("bad", score: -1, source: .manual))))
        XCTAssertTrue(try store.profiles().isEmpty)
        let token = try store.applyManual(change: .add(observation("offline", at: nil, source: .manual)))
        XCTAssertEqual(try store.profiles().map(\.id), [testAccount])
        XCTAssertNil(try store.bestScores(accountID: testAccount).first?.values.playedAt)
        try store.undo(token)
        XCTAssertTrue(try store.profiles().isEmpty)
    }

    func testOverrideSurvivesReimportKeepsSourceImmutableAndUndoSurvivesReopening() throws {
        let url = temporaryArchiveURL()
        let store = try ArchiveStore(url: url)
        let imported = observation("best", score: 9_900_000)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [imported]))
        let token = try store.applyManual(change: .override(accountID: testAccount, observationID: imported.id,
                                                          values: ScoreValues(score: 9_600_000)))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [imported]))
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_600_000)
        XCTAssertTrue(try XCTUnwrap(store.bestScores(accountID: testAccount).first).isOverridden)
        XCTAssertEqual(try store.sourceObservations(accountID: testAccount).first?.score, 9_900_000)
        let reopened = try ArchiveStore(url: url)
        XCTAssertEqual(try reopened.latestUndoToken(), token)
        try reopened.undo(token)
        XCTAssertEqual(try reopened.bestScores(accountID: testAccount).first?.values.score, 9_900_000)
    }

    func testDeletionSuppressesSameRecordButNewDistinctPlayImportsAndUndoRestores() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let imported = observation("old", score: 9_900_000)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [imported]))
        let token = try store.applyManual(change: .suppress(accountID: testAccount, observationID: imported.id))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [imported, observation("new", score: 9_700_000, at: 1_800_000_100)]))
        XCTAssertEqual(try store.observations(accountID: testAccount).map(\.original.id.rawValue), ["new"])
        XCTAssertEqual(try store.observations(accountID: testAccount, includeSuppressed: true).count, 2)
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_700_000)
        try store.undo(token)
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_900_000)
    }

    func testDownwardBestCorrectionHidesEntireBaselineAndAllowsGenuinelyNewPlay() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let baseline = [observation("bad", score: 9_900_000), observation("also-bad", score: 9_800_000)]
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: baseline))
        _ = try store.applyManual(change: .correctBest(accountID: testAccount, chartID: testChart,
                                                      values: ScoreValues(score: 9_600_000)))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: baseline))
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_600_000)
        XCTAssertTrue(try XCTUnwrap(store.bestScores(accountID: testAccount).first).isBestCorrection)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount),
            observations: [observation("actual-new", score: 9_700_000, at: 1_800_000_100)]))
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_700_000)
        let reset = try store.applyManual(change: .resetBestCorrection(accountID: testAccount, chartID: testChart))
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_900_000)
        try store.undo(reset)
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_700_000)
    }

    func testManualAddMissingFieldsResetRestoreAndLIFOProtection() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount)))
        let manual = observation("manual", score: 9_800_000, at: nil, source: .manual)
        let added = try store.applyManual(change: .add(manual))
        let edited = try store.applyManual(change: .override(accountID: testAccount, observationID: manual.id, values: ScoreValues(score: 9_500_000)))
        XCTAssertThrowsError(try store.undo(added))
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_500_000)
        try store.undo(edited)
        let suppress = try store.applyManual(change: .suppress(accountID: testAccount, observationID: manual.id))
        XCTAssertTrue(try store.bestScores(accountID: testAccount).isEmpty)
        let restore = try store.applyManual(change: .restore(accountID: testAccount, observationID: manual.id))
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_800_000)
        try store.undo(restore); try store.undo(suppress)
        let reset = try store.applyManual(change: .resetOverride(accountID: testAccount, observationID: manual.id))
        try store.undo(reset); try store.undo(added)
        XCTAssertTrue(try store.sourceObservations(accountID: testAccount).isEmpty)
    }

    func testInvalidCountsKnownNoteBoundsWrongOwnerAndOverflowCannotMutateArchive() throws {
        let catalog = ChartCatalog(charts: [ChartMetadata(id: testChart, noteCount: 100, provenance: "synthetic")])
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [observation("valid", judgments: Judgments(pure: 98, shinyPure: 90, far: 1, lost: 1))]))
        let bad: [ScoreValues] = [
            ScoreValues(score: -1), ScoreValues(score: 10_000_101),
            ScoreValues(score: 1, judgments: Judgments(pure: 90, shinyPure: 91)),
            ScoreValues(score: 1, judgments: Judgments(pure: 98, far: 1, lost: 0)),
            ScoreValues(score: 1, judgments: Judgments(far: -1)),
            ScoreValues(score: 1, playedAt: SourceTimestamp(value: Int64.max, unit: .seconds)),
            ScoreValues(score: 1, health: 101)
        ]
        for values in bad {
            XCTAssertThrowsError(try store.applyManual(change: .override(accountID: testAccount, observationID: ObservationID("valid"), values: values)))
        }
        XCTAssertThrowsError(try store.applyManual(change: .suppress(accountID: otherAccount, observationID: ObservationID("valid"))))
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_800_000)
        XCTAssertNil(try store.latestUndoToken())
    }
}
