import XCTest
@testable import ArcaeaCore

final class ConsultantImportTests: XCTestCase {
    private let title = "Synthetic Song [FTR]"
    private var catalog: ChartCatalog { ChartCatalog(charts: [ChartMetadata(id: testChart, constant: ChartConstant(tenths: 100), noteCount: 1000, title: "Synthetic Song", provenance: "test")]) }
    private func snapshot(_ rows: [[Any]], version: String = "v9.0.2a-beta") throws -> ConsultantSnapshot {
        let data = try JSONSerialization.data(withJSONObject: ["valueRanges": [
            ["values": [[version]]],
            ["values": [["곡명_난이도", "체감보면상수", "노트수", "점수_나"]] + rows]
        ]])
        return try ConsultantSnapshot.decode(data)
    }
    func testPreviewSkipsInvalidUnmappedDuplicateAndEmptyScores() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
        let data = try snapshot([[title, 10, 1000, 9900000], ["Other [FTR]", 10, 1000, 9800000], ["Broken [FTR]", 10, 1000, "#ERROR!"], ["Empty [FTR]", 10, 1000, 0]])
        let plan = try store.previewConsultantImport(data, accountID: testAccount)
        XCTAssertEqual(plan.entries.map(\.disposition), [.add, .unmapped, .invalid])
        XCTAssertEqual(plan.emptyCount, 1)
        XCTAssertTrue(try store.sourceObservations(accountID: testAccount).isEmpty)
        let duplicates = try store.previewConsultantImport(snapshot([[title, 10, 1000, 9900000], [title, 10, 1000, 9800000]]), accountID: testAccount)
        XCTAssertTrue(duplicates.entries.allSatisfy { $0.disposition == .duplicate })
        XCTAssertThrowsError(try snapshot([], version: "v99"))
    }
    func testImportIsAtomicIdempotentUndatedAndBackedUp() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
        let data = try snapshot([[title, 10, 1000, 9900000]])
        let plan = try store.previewConsultantImport(data, accountID: testAccount)
        let receipt = try store.importConsultant(plan, fileID: "test-sheet", importedAt: testDate)
        XCTAssertEqual(receipt.addedCount, 1)
        let imported = try XCTUnwrap(store.sourceObservations(accountID: testAccount).first)
        XCTAssertEqual(imported.source, .consultantSheet)
        XCTAssertNil(imported.values.playedAt)
        XCTAssertNil(imported.values.playClear)
        let repeated = try store.previewConsultantImport(data, accountID: testAccount)
        XCTAssertEqual(repeated.entries.first?.disposition, .keepExisting)
        XCTAssertEqual(try store.importConsultant(repeated, fileID: "test-sheet", importedAt: testDate).addedCount, 0)
        let restored = try ArchiveStore(url: temporaryArchiveURL())
        _ = try ArchiveBackup(store: restored).validateAndRestore(data: ArchiveBackup(store: store).export())
        XCTAssertEqual(try restored.sourceObservations(accountID: testAccount), [imported])
        XCTAssertTrue(try store.sourceObservations(accountID: otherAccount).isEmpty)
    }
    func testHigherBestAndManualCorrectionSurviveImportAndStalePreviewIsRejected() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [observation("existing", score: 9950000)]))
        let lower = try store.previewConsultantImport(snapshot([[title, 10, 1000, 9900000]]), accountID: testAccount)
        XCTAssertEqual(lower.entries.first?.disposition, .keepExisting)
        let higher = try store.previewConsultantImport(snapshot([[title, 10, 1000, 10000000]]), accountID: testAccount)
        _ = try store.applyManual(change: .correctBest(accountID: testAccount, chartID: testChart, values: ScoreValues(score: 9800000)))
        XCTAssertThrowsError(try store.importConsultant(higher, fileID: "sheet", importedAt: testDate))
        let protected = try store.previewConsultantImport(snapshot([[title, 10, 1000, 10000000]]), accountID: testAccount)
        XCTAssertEqual(protected.entries.first?.disposition, .manualProtected)
        XCTAssertEqual(try store.importConsultant(protected, fileID: "sheet", importedAt: testDate).addedCount, 0)
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9800000)
    }
    func testSheetImportUsesImportTimeForPotentialContinuation() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
        let anchor = PotentialPoint(accountID: testAccount, sourceID: "official", timestamp: SourceTimestamp(value: 1_800_000_000, unit: .seconds), value: PotentialValue(rawValue: 1234, decimalPlaces: 2), firstSeenAt: testDate)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [observation("baseline", score: 9800000)], potentialPoints: [anchor], importedAt: testDate))
        let plan = try store.previewConsultantImport(snapshot([[title, 10, 1000, 10000000]]), accountID: testAccount)
        _ = try store.importConsultant(plan, fileID: "sheet", importedAt: testDate.addingTimeInterval(600))
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 10000000)
        XCTAssertEqual(try store.potentialHistory(accountID: testAccount), [anchor])
        let point = try XCTUnwrap(store.localPotentialHistory(accountID: testAccount).last)
        XCTAssertEqual(point.timestamp.date, testDate.addingTimeInterval(600))
        XCTAssertGreaterThan(point.value.doubleValue, anchor.value.doubleValue)
        XCTAssertNil(try store.sourceObservations(accountID: testAccount).first { $0.source == .consultantSheet }?.values.playedAt)
    }
    func testSheetOnlyGraphStartsAtImportAndSurvivesBackup() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
        let plan = try store.previewConsultantImport(snapshot([[title, 10, 1000, 9900000]]), accountID: testAccount)
        _ = try store.importConsultant(plan, fileID: "sheet", importedAt: testDate)
        let points = try store.localPotentialHistory(accountID: testAccount)
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points.first?.timestamp.date, testDate)
        let rating = try RatingCalculator(catalog: catalog).rank(bestScores: store.bestScores(accountID: testAccount))
        XCTAssertEqual(try XCTUnwrap(points.first).value.doubleValue, Double(rating.potentialUnits) / Double(RatingCalculator.scale), accuracy: 0.000002)
        let second = try store.previewConsultantImport(snapshot([[title, 10, 1000, 10000000]]), accountID: testAccount)
        _ = try store.importConsultant(second, fileID: "sheet", importedAt: testDate.addingTimeInterval(60))
        XCTAssertEqual(try store.localPotentialHistory(accountID: testAccount).count, 2)
        let restored = try ArchiveStore(url: temporaryArchiveURL())
        _ = try ArchiveBackup(store: restored).validateAndRestore(data: ArchiveBackup(store: store).export())
        XCTAssertEqual(try restored.localPotentialHistory(accountID: testAccount), try store.localPotentialHistory(accountID: testAccount))
    }
    func testLaterBestCorrectionKeepsEarlierSheetImportPoint() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
        let importedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = try store.previewConsultantImport(snapshot([[title, 10, 1000, 9900000]]), accountID: testAccount)
        _ = try store.importConsultant(plan, fileID: "sheet", importedAt: importedAt)
        let first = try XCTUnwrap(store.localPotentialHistory(accountID: testAccount).first)
        _ = try store.applyManual(change: .correctBest(accountID: testAccount, chartID: testChart, values: ScoreValues(score: 9800000)))
        let history = try store.localPotentialHistory(accountID: testAccount)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first, first)
        XCTAssertLessThan(try XCTUnwrap(history.last).value.doubleValue, first.value.doubleValue)
    }
    func testCorrectionInSameMillisecondCannotReplaySupersededSheetHigh() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
        let importedAt = Date(timeIntervalSince1970: 1_700_000_000.0001)
        let plan = try store.previewConsultantImport(snapshot([[title, 10, 1000, 10000000]]), accountID: testAccount)
        _ = try store.importConsultant(plan, fileID: "sheet", importedAt: importedAt)
        let ids = Set(try store.sourceObservations(accountID: testAccount).map(\.id))
        try store.setCorrection(testAccount, testChart, BestCorrection(accountID: testAccount, chartID: testChart,
            values: ScoreValues(score: 9800000), baselineIDs: ids, recordedAt: importedAt.addingTimeInterval(0.0001)))
        let point = try XCTUnwrap(store.localPotentialHistory(accountID: testAccount).last)
        let expected = try RatingCalculator(catalog: catalog).rank(bestScores: store.bestScores(accountID: testAccount)).potentialUnits
        XCTAssertEqual(point.value.doubleValue, Double(expected) / Double(RatingCalculator.scale), accuracy: 0.000002)
    }
    func testBundledTitleAliasesWorkWithoutSubscriptionAndINSMapsToBeyond() throws {
        let id = ChartID(songID: "sayonarahatsukoi", difficulty: .past)
        let ins = ChartID(songID: "ins-test", difficulty: .beyond)
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: ChartCatalog(charts: [ChartMetadata(id: id, provenance: "test"), ChartMetadata(id: ins, title: "INS Chart", provenance: "test")]))
        let plan = try store.previewConsultantImport(snapshot([["Sayonara Hatsukoi [PST]", 1.5, 205, 9975813], ["INS Chart [INS]", 10, 1000, 9900000]]), accountID: testAccount)
        XCTAssertEqual(plan.entries.map(\.chartID), [id, ins])
        XCTAssertEqual(plan.addCount, 2)
    }
    func testWorkbookAliasesDistinguishSameNamedSongsAndLocalizedTitles() throws {
        let examples: [(String, String)] = [
            ("Genesis(Arcaea)", "genesis"), ("Genesis(CHUNITHM)", "genesischunithm"),
            ("Quon(Lanota)", "quon"), ("Quon(WACCA)", "quonwacca"),
            ("Anokumene", "anokumene"), ("Alice a la mode", "alicealamode"),
            ("neo kosmo", "neokosmo"), ("II", "ii")
        ]
        let charts = examples.map { ChartMetadata(id: ChartID(songID: $0.1, difficulty: .future), provenance: "test") }
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: ChartCatalog(charts: charts))
        let rows: [[Any]] = examples.map { ["\($0.0) [FTR]", 10, 1000, 9900000] }
        let plan = try store.previewConsultantImport(snapshot(rows), accountID: testAccount)
        XCTAssertEqual(plan.entries.map(\.chartID), charts.map(\.id))
        XCTAssertEqual(plan.addCount, examples.count)
        // An unqualified duplicate name must still be rejected rather than guessed.
        let ambiguous = try store.previewConsultantImport(snapshot([["Genesis [FTR]", 10, 1000, 9900000], ["Quon [FTR]", 10, 1000, 9900000]]), accountID: testAccount)
        XCTAssertEqual(ambiguous.entries.map(\.disposition), [.ambiguous, .ambiguous])
    }
    func testAmbiguousTitlesAndInvalidNumericCellsAreNeverImported() throws {
        let other = ChartID(songID: "ambiguous", difficulty: .future)
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: ChartCatalog(charts: Array(catalog.charts.values) + [ChartMetadata(id: other, title: "Synthetic Song", provenance: "test")]))
        let plan = try store.previewConsultantImport(snapshot([[title, 10, 1000, 9900000], [title, 10, 1000, true], [title, 10, 1000, 9900000.5], [title, 10, 1000, 10001001]]), accountID: testAccount)
        XCTAssertEqual(plan.entries.map(\.disposition), [.ambiguous, .invalid, .invalid, .invalid])
        XCTAssertEqual(try store.importConsultant(plan, fileID: "sheet", importedAt: testDate).addedCount, 0)
        XCTAssertTrue(try store.profiles().isEmpty)
    }
    func testDeletedOrOverriddenChartsRemainProtected() throws {
        for suppress in [true, false] {
            let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
            _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [observation("edited", score: 9800000)]))
            if suppress { _ = try store.applyManual(change: .suppress(accountID: testAccount, observationID: ObservationID("edited"))) }
            else { _ = try store.applyManual(change: .override(accountID: testAccount, observationID: ObservationID("edited"), values: ScoreValues(score: 9700000))) }
            let plan = try store.previewConsultantImport(snapshot([[title, 10, 1000, 10000000]]), accountID: testAccount)
            XCTAssertEqual(plan.entries.first?.disposition, .manualProtected)
            XCTAssertEqual(try store.importConsultant(plan, fileID: "sheet", importedAt: testDate).addedCount, 0)
            XCTAssertEqual(try store.sourceObservations(accountID: testAccount).count, 1)
        }
    }
    func testOtherConnectionImprovementInvalidatesPreviewBeforeAnyInsert() throws {
        let url = temporaryArchiveURL()
        let store = try ArchiveStore(url: url, catalog: catalog)
        let plan = try store.previewConsultantImport(snapshot([[title, 10, 1000, 9900000]]), accountID: testAccount)
        let shortcut = try ArchiveStore(url: url)
        _ = try shortcut.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [observation("new-recent", score: 9950000)]))
        XCTAssertThrowsError(try store.importConsultant(plan, fileID: "sheet", importedAt: testDate))
        XCTAssertEqual(try store.sourceObservations(accountID: testAccount).count, 1)
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9950000)
    }

}
