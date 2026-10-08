import XCTest
@testable import ArcaeaCore

final class ReconciliationTests: XCTestCase {
    func testSameRouteEventIdentityEnrichmentDoesNotMergeAnotherVerifiedAttempt() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let values = ScoreValues(score: 9_800_000, playedAt: SourceTimestamp(value: 1_800_000_000, unit: .seconds))
        func remote(_ event: String?) throws -> ScoreObservation {
            try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialRecent,
                                        values: values, firstSeenAt: testDate, eventID: event)
        }
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [remote(nil), remote("first"), remote("second")]))
        XCTAssertEqual(try store.sourceObservations(accountID: testAccount).count, 2)
        let restored = try ArchiveStore(url: temporaryArchiveURL())
        _ = try ArchiveBackup(store: restored).validateAndRestore(data: ArchiveBackup(store: store).export())
        XCTAssertEqual(try restored.sourceObservations(accountID: testAccount).count, 2)
    }

    func testEventIDIntroducedByAnotherRouteKeepsCorrectionAndSuppression() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let values = ScoreValues(score: 9_800_000, playedAt: SourceTimestamp(value: 1_800_000_000, unit: .seconds))
        let recent = try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialRecent,
            values: values, firstSeenAt: testDate)
        let imported = try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialImport,
            values: values, firstSeenAt: testDate, eventID: "server-event")
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [recent]))
        _ = try store.applyManual(change: .override(accountID: testAccount, observationID: recent.id, values: ScoreValues(score: 9_500_000)))
        let receipt = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [imported]))
        XCTAssertEqual(receipt.addedCount, 0)
        XCTAssertEqual(receipt.duplicateCount, 1)
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_500_000)
        _ = try store.applyManual(change: .suppress(accountID: testAccount, observationID: recent.id))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [imported]))
        XCTAssertTrue(try store.bestScores(accountID: testAccount).isEmpty)
        let roundTrip = try ArchiveStore(url: temporaryArchiveURL())
        _ = try ArchiveBackup(store: roundTrip).validateAndRestore(data: ArchiveBackup(store: store).export())
        let repeated = try roundTrip.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [imported]))
        XCTAssertEqual(repeated.addedCount, 0)
        XCTAssertTrue(try roundTrip.bestScores(accountID: testAccount).isEmpty)
    }

    func testDifferentVerifiedEventIDsRemainDistinctEvenWithEqualTimestampAndScore() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let values = ScoreValues(score: 9_800_000, playedAt: SourceTimestamp(value: 1_800_000_000, unit: .seconds))
        let uncertain = try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialRecent, values: values, firstSeenAt: testDate)
        let first = try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialImport, values: values, firstSeenAt: testDate, eventID: "first-event")
        let second = try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialImport, values: values, firstSeenAt: testDate, eventID: "second-event")
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [uncertain, first, second]))
        XCTAssertEqual(try store.sourceObservations(accountID: testAccount).count, 2)
    }

    func testSamePlayAcrossSourcesEnrichesCoherentlyAndDoesNotBypassSuppression() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let recent = try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialRecent,
            values: ScoreValues(score: 9_800_000, playedAt: SourceTimestamp(value: 1_800_000_000, unit: .seconds),
                                judgments: Judgments(pure: 900, far: 10, lost: 2), playClear: .normal), firstSeenAt: testDate)
        let imported = try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialImport,
            values: ScoreValues(score: 9_800_000, playedAt: SourceTimestamp(value: 1_800_000_000_000, unit: .milliseconds),
                                judgments: Judgments(pure: 900, shinyPure: 800, far: 10, lost: 2), playClear: .normal,
                                bestClear: .fullRecall, modifier: 0, health: 80), firstSeenAt: testDate.addingTimeInterval(70))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [recent]))
        let receipt = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [imported]))
        XCTAssertEqual(receipt.duplicateCount, 1)
        XCTAssertEqual(receipt.addedCount, 0)
        let best = try XCTUnwrap(store.bestScores(accountID: testAccount).first)
        XCTAssertEqual(best.values.judgments, imported.values.judgments)
        XCTAssertEqual(best.values.health, 80)
        XCTAssertEqual(best.bestClear, .fullRecall)
        XCTAssertEqual(try store.captureSources(accountID: testAccount)[recent.id], [.officialImport, .officialRecent])
        XCTAssertTrue(try store.captureSources(accountID: otherAccount).isEmpty)
        XCTAssertEqual(try store.sourceObservations(accountID: testAccount).first?.values, recent.values)
        _ = try store.applyManual(change: .suppress(accountID: testAccount, observationID: recent.id))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [imported]))
        XCTAssertTrue(try store.bestScores(accountID: testAccount).isEmpty)
    }

    func testIncomingPartialMetadataPreservesExistingRatingAndNoteBounds() throws {
        let chart = ChartMetadata(id: testChart, constant: ChartConstant(tenths: 105), level: "10+", noteCount: 100, provenance: "dated snapshot")
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: ChartCatalog(charts: [chart]))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [observation("score")],
            charts: [ChartMetadata(id: testChart, title: "Imported title", artist: "Artist", provenance: "official response")]))
        let merged = try XCTUnwrap(store.chartCatalog()[testChart])
        XCTAssertEqual(merged.constant?.tenths, 105)
        XCTAssertEqual(merged.noteCount, 100)
        XCTAssertEqual(merged.level, "10+")
        XCTAssertEqual(merged.title, "Imported title")
        let snapshot = try RatingCalculator(catalog: store.chartCatalog()).rank(bestScores: store.bestScores(accountID: testAccount))
        XCTAssertEqual(snapshot.missingConstants, 0)
    }

    func testRepeatedPollDeduplicatesWhileDistinctIdenticalScoresRemainAttempts() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let first = observation("first")
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [first], kind: .recent))
        let receipt = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount),
            observations: [first, observation("second", at: 1_800_000_001)], kind: .recent))
        XCTAssertEqual(receipt.addedCount, 1)
        XCTAssertEqual(receipt.duplicateCount, 1)
        XCTAssertEqual(try store.observations(accountID: testAccount).count, 2)
        XCTAssertEqual(try store.bestScores(accountID: testAccount).count, 1)
    }

    func testLowerRecentPlayPreservesBestButImprovedLampAndJudgmentsStayCoherent() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let best = observation("best", score: 9_950_000, judgments: Judgments(pure: 900, shinyPure: 800, far: 10, lost: 0), clear: .normal)
        let lower = observation("lower", score: 9_700_000, at: 1_800_000_001,
                                judgments: Judgments(pure: 850, shinyPure: 700, far: 60, lost: 0), clear: .fullRecall)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [best, lower]))
        let selected = try XCTUnwrap(store.bestScores(accountID: testAccount).first)
        XCTAssertEqual(selected.values.score, 9_950_000)
        XCTAssertEqual(selected.values.judgments?.pure, 900)
        XCTAssertEqual(selected.values.judgments?.far, 10)
        XCTAssertEqual(selected.values.playClear, .normal)
        XCTAssertEqual(selected.bestClear, .fullRecall)
        XCTAssertEqual(try store.observations(accountID: testAccount).count, 2)
    }

    func testTiedScoresChooseOneCompleteAttemptAndUnknownsRemainNil() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [
            observation("old", judgments: Judgments(pure: 100, far: 2, lost: 3)),
            observation("new", at: 1_800_000_100, judgments: Judgments(pure: 98, far: 5, lost: 2)),
            observation("unknown", at: nil, chart: ChartID(songID: "unknown", difficulty: .past))
        ]))
        let rows = try store.bestScores(accountID: testAccount)
        let selected = try XCTUnwrap(rows.first { $0.chartID == testChart })
        XCTAssertEqual(selected.values.judgments, Judgments(pure: 98, far: 5, lost: 2))
        let unknown = try XCTUnwrap(rows.first { $0.chartID.songID == "unknown" })
        XCTAssertNil(unknown.values.playedAt)
        XCTAssertNil(unknown.values.judgments)
        XCTAssertNil(unknown.values.playClear)
        XCTAssertNil(unknown.bestClear)
    }
}
