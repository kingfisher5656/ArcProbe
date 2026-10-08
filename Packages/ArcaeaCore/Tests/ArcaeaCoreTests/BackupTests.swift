import XCTest
@testable import ArcaeaCore

final class BackupTests: XCTestCase {
    func testFullRoundTripPreservesAccountsOverridesSuppressionCorrectionsHistoryCapturesAndUndo() throws {
        let source = try ArchiveStore(url: temporaryArchiveURL(), catalog: ChartCatalog(charts: [ChartMetadata(id: testChart, constant: ChartConstant(tenths: 100), provenance: "synthetic")]))
        let correctionChart = ChartID(songID: "corrected", difficulty: .beyond)
        _ = try source.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount, displayName: "Main"), observations: [
            observation("edit", score: 9_900_000), observation("delete", score: 9_700_000),
            observation("baseline", score: 10_000_000, chart: correctionChart)
        ], potentialPoints: [PotentialPoint(accountID: testAccount, sourceID: "official", timestamp: SourceTimestamp(value: 1_800_000_000_001, unit: .milliseconds), value: PotentialValue(rawValue: 12_345_678, decimalPlaces: 6), firstSeenAt: testDate)]))
        _ = try source.apply(batch: ImportBatch(profile: AccountProfile(id: otherAccount), observations: [observation("other", account: otherAccount)]))
        _ = try source.applyManual(change: .override(accountID: testAccount, observationID: ObservationID("edit"), values: ScoreValues(score: 9_500_000)))
        _ = try source.applyManual(change: .suppress(accountID: testAccount, observationID: ObservationID("delete")))
        let undo = try source.applyManual(change: .correctBest(accountID: testAccount, chartID: correctionChart, values: ScoreValues(score: 9_600_000)))
        let exported = try ArchiveBackup(store: source).export()
        let target = try ArchiveStore(url: temporaryArchiveURL())
        let receipt = try ArchiveBackup(store: target).validateAndRestore(data: exported)
        XCTAssertEqual(receipt.addedCount, 4)
        XCTAssertEqual(try target.profiles(), try source.profiles())
        XCTAssertEqual(try target.sourceObservations(accountID: testAccount), try source.sourceObservations(accountID: testAccount))
        XCTAssertEqual(try target.bestScores(accountID: testAccount), try source.bestScores(accountID: testAccount))
        XCTAssertEqual(try target.potentialHistory(accountID: testAccount), try source.potentialHistory(accountID: testAccount))
        XCTAssertEqual(try target.sourceCaptures(observationID: ObservationID("edit")), try source.sourceCaptures(observationID: ObservationID("edit")))
        XCTAssertEqual(try target.latestUndoToken(), undo)
        try target.undo(undo)
        XCTAssertEqual(try target.bestScores(accountID: testAccount).first { $0.chartID == correctionChart }?.values.score, 10_000_000)
    }

    func testUnsupportedCorruptCrossAccountAndOverflowBackupsLeaveExistingArchiveIntact() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [observation("existing")]))
        let backup = ArchiveBackup(store: store)
        let baseline = try JSONDecoder().decode(ArchivePayload.self, from: backup.export())
        var unsupported = baseline; unsupported.schemaVersion = 999
        XCTAssertThrowsError(try backup.validateAndRestore(data: JSONEncoder().encode(unsupported)))
        XCTAssertThrowsError(try backup.validateAndRestore(data: Data("{broken".utf8)))
        var collision = baseline
        collision.profiles = [AccountProfile(id: testAccount), AccountProfile(id: otherAccount)]
        collision.observations = [observation("shared"), observation("shared", account: otherAccount)]
        XCTAssertThrowsError(try backup.validateAndRestore(data: JSONEncoder().encode(collision)))
        var overflow = baseline
        overflow.profiles = [AccountProfile(id: testAccount)]
        overflow.observations = [ScoreObservation(id: ObservationID("overflow"), accountID: testAccount,
            chartID: testChart, source: .officialImport, values: ScoreValues(score: 1, playedAt: SourceTimestamp(value: Int64.max, unit: .seconds)), firstSeenAt: testDate)]
        XCTAssertThrowsError(try backup.validateAndRestore(data: JSONEncoder().encode(overflow)))
        XCTAssertEqual(try store.sourceObservations(accountID: testAccount).map(\.id.rawValue), ["existing"])
    }

    func testCancellationAfterReplacementStartsRollsBackAndNeverExportsInjectedSecrets() throws {
        let incoming = try ArchiveStore(url: temporaryArchiveURL())
        _ = try incoming.apply(batch: ImportBatch(profile: AccountProfile(id: otherAccount), observations: [observation("incoming", account: otherAccount)]))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: ArchiveBackup(store: incoming).export()) as? [String: Any])
        object["credentials"] = ["password": "synthetic-secret", "cookies": ["session": "synthetic-cookie"]]
        let data = try JSONSerialization.data(withJSONObject: object)
        let existing = try ArchiveStore(url: temporaryArchiveURL())
        _ = try existing.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [observation("existing")]))
        var checks = 0
        XCTAssertThrowsError(try ArchiveBackup(store: existing).validateAndRestore(data: data) {
            checks += 1
            if checks == 3 { throw CancellationError() }
        })
        XCTAssertGreaterThanOrEqual(checks, 3)
        XCTAssertEqual(try existing.sourceObservations(accountID: testAccount).map(\.id.rawValue), ["existing"])
        _ = try ArchiveBackup(store: existing).validateAndRestore(data: data)
        let restored = String(decoding: try ArchiveBackup(store: existing).export(), as: UTF8.self)
        XCTAssertFalse(restored.contains("synthetic-secret"))
        XCTAssertFalse(restored.contains("synthetic-cookie"))
        XCTAssertEqual(try existing.sourceObservations(accountID: otherAccount).map(\.id.rawValue), ["incoming"])
    }
}
