import XCTest
@testable import ArcaeaCore

final class ConsultantExportTests: XCTestCase {
    private let title = "Synthetic Song [FTR]"
    private var catalog: ChartCatalog { ChartCatalog(charts: [ChartMetadata(id: testChart, constant: ChartConstant(tenths: 100), noteCount: 1000, title: "Synthetic Song", provenance: "test")]) }
    func snapshot(score: Any = 9_900_000, raw: Any = 9_900_000, identity: String = "Synthetic Song [FTR]", notes: Int = 1000, duplicate: Bool = false, header: String = "점수") throws -> ConsultantExportSnapshot {
        let inputs: [[Any]] = [[identity, "번역 제목 [FTR]", "번역 제목", "FTR"]]
        let evaluated = try JSONSerialization.data(withJSONObject: ["valueRanges": [
            ["values": [["v9.0.2a-beta"]]],
            ["values": [["곡명_난이도", "체감보면상수", "노트수", "점수_나"], ["번역 제목 [FTR]", 10, notes, score]]],
            ["values": duplicate ? inputs + inputs : inputs], ["values": [[header, "L"]]]
        ]])
        return try ConsultantExportSnapshot.decode(evaluated: evaluated, raw: JSONSerialization.data(withJSONObject: ["values": [[header]] + (duplicate ? [[raw], [raw]] : [[raw]])]))
    }
    func store(score: Int? = 9_950_000) throws -> ArchiveStore {
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: score.map { [observation("local-best", score: $0)] } ?? []))
        return store
    }
    func testAuthoritativePreviewIncreasesDecreasesClearsAndKeepsEqualWithoutChangingArchive() throws {
        let archive = try store()
        for (remote, expected) in [(9_800_000, ConsultantExportPlan.Disposition.increase), (10_000_000, .decrease), (9_950_000, .unchanged)] {
            let plan = try archive.previewConsultantExport(snapshot(score: remote, raw: remote), accountID: testAccount, mode: .matchArcProbe)
            XCTAssertEqual(plan.entries.first?.disposition, expected)
            XCTAssertEqual(plan.entries.first?.chartID, testChart)
            XCTAssertEqual(plan.entries.first?.score, 9_950_000)
        }
        let cleared = try store(score: nil).previewConsultantExport(snapshot(), accountID: testAccount, mode: .matchArcProbe)
        XCTAssertEqual(cleared.entries.first?.disposition, .clear)
        XCTAssertEqual(cleared.changes.first?.score, 0)
        XCTAssertEqual(try archive.bestScores(accountID: testAccount).first?.values.score, 9_950_000)
        XCTAssertThrowsError(try archive.previewConsultantExport(snapshot(), accountID: otherAccount, mode: .matchArcProbe))
    }
    func testProtectsFormulaDuplicatesUnknownChartAndNoteMismatch() throws {
        let archive = try store()
        for (data, reason) in [(try snapshot(raw: "=9990000"), ConsultantExportPlan.Disposition.formula),
                               (try snapshot(duplicate: true), .duplicate),
                               (try snapshot(identity: "Unknown [FTR]"), .unmapped),
                               (try snapshot(notes: 999), .invalid),
                               (try snapshot(score: "#ERROR!"), .invalid),
                               (try snapshot(raw: true), .invalid)] {
            let plan = try archive.previewConsultantExport(data, accountID: testAccount, mode: .matchArcProbe)
            XCTAssertEqual(plan.entries.first?.disposition, reason)
            XCTAssertTrue(plan.changes.isEmpty)
        }
    }
    func testShorthandComparedUsingDecodedScoreAndCorrectedLocalBestWins() throws {
        let archive = try store()
        let plan = try archive.previewConsultantExport(snapshot(score: 10_001_000, raw: "MAX"), accountID: testAccount, mode: .matchArcProbe)
        XCTAssertEqual(plan.entries.first?.disposition, .decrease)
        _ = try archive.applyManual(change: .correctBest(accountID: testAccount, chartID: testChart, values: ScoreValues(score: 9_700_000)))
        XCTAssertEqual(try archive.previewConsultantExport(plan.snapshot, accountID: testAccount, mode: .matchArcProbe).changes.first?.score, 9_700_000)
    }
    func testImprovementsOnlyPreservesHigherAndMissingScoresButSendsNewBests() throws {
        for local in [Int?.none, 9_700_000, 9_900_000, 9_950_000] {
            let archive = try store(score: local)
            let plan = try archive.previewConsultantExport(snapshot(), accountID: testAccount, mode: .improvementsOnly)
            XCTAssertEqual(plan.mode, .improvementsOnly)
            if local == 9_950_000 {
                XCTAssertEqual(plan.entries.first?.disposition, .increase)
                XCTAssertEqual(plan.changes.first?.score, local)
            } else {
                XCTAssertTrue(plan.changes.isEmpty)
                XCTAssertEqual(plan.entries.first?.disposition, local == 9_900_000 ? .unchanged : .keepHigher)
            }
        }
    }
    func testInsertedInputColumnAndHeaderFormulaRejectWholeLayout() throws {
        XCTAssertThrowsError(try snapshot(header: "Notes"))
        XCTAssertThrowsError(try snapshot(header: "=ARRAYFORMULA()"))
    }
    func testSmallNumericScoresAreSkippedBecauseSheetTreatsThemAsShinyCounts() throws {
        let plan = try store(score: 1000).previewConsultantExport(snapshot(), accountID: testAccount, mode: .matchArcProbe)
        XCTAssertEqual(plan.entries.first?.disposition, .invalid)
        XCTAssertTrue(plan.changes.isEmpty)
    }
    func testRowPositionsAndLocalizedJoinAreIndependentOfDataMOrder() throws {
        let other = ChartID(songID: "mask", difficulty: .future)
        let archive = try ArchiveStore(url: temporaryArchiveURL(), catalog: ChartCatalog(charts: [
            ChartMetadata(id: testChart, noteCount: 1000, title: "Synthetic Song", provenance: "test"),
            ChartMetadata(id: other, noteCount: 500, title: "~_+", provenance: "test")]))
        _ = try archive.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [observation("best", score: 9_950_000)]))
        let evaluated = try JSONSerialization.data(withJSONObject: ["valueRanges": [
            ["values": [["v9.0.2a-beta"]]],
            ["values": [["곡명_난이도", "체감보면상수", "노트수", "점수_나"], ["번역 [FTR]", 10, 1000, 9_800_000], ["~_+ [FTR]", 10, 500, 9_900_000]]],
            ["values": [["~_+ [FTR]", "~_+ [FTR]"], [], ["Synthetic Song [FTR]", "번역 [FTR]"]]], ["values": [["점수", "L"]]]]])
        let raw = try JSONSerialization.data(withJSONObject: ["values": [["점수"], [9_900_000], [], [9_800_000]]])
        let plan = try archive.previewConsultantExport(ConsultantExportSnapshot.decode(evaluated: evaluated, raw: raw), accountID: testAccount, mode: .matchArcProbe)
        XCTAssertEqual(plan.changes.map(\.row), [5, 7])
        XCTAssertEqual(plan.changes.map(\.score), [0, 9_950_000])
        XCTAssertEqual(plan.entries.map(\.chartID), [other, testChart])
    }

}

@MainActor final class ConsultantExportServiceTests: XCTestCase {
    func testSendVerifiesRawAndCalculatedScoresAndClearsJournal() async throws {
        let fixture = ConsultantExportTests(); let archive = try fixture.store()
        let old = try fixture.snapshot(); let expected = try fixture.snapshot(score: 9_950_000, raw: 9_950_000)
        let remote = ExportRemoteMock(snapshot: old, after: expected); let journal = ExportJournalMock()
        remote.onWrite = { XCTAssertNotNil(journal.entry) }
        let service = ConsultantExportService(remote: remote, journal: journal)
        let plan = try archive.previewConsultantExport(old, accountID: testAccount, mode: .matchArcProbe)
        let count = try await service.send(plan, fileID: "selected", inputTab: "Input [Score Input]", store: archive)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(remote.writes.count, 1); XCTAssertEqual(remote.writes.first?.first?.row, 5)
        XCTAssertNil(journal.entry)
    }
    func testStaleSheetOrArchiveAndFailedJournalNeverWrite() async throws {
        let fixture = ConsultantExportTests(); let archive = try fixture.store(); let old = try fixture.snapshot()
        let remote = ExportRemoteMock(snapshot: old, after: old); let journal = ExportJournalMock()
        let service = ConsultantExportService(remote: remote, journal: journal)
        let plan = try archive.previewConsultantExport(old, accountID: testAccount, mode: .matchArcProbe)
        remote.current = try fixture.snapshot(raw: "9900000")
        do { _ = try await service.send(plan, fileID: "selected", inputTab: "Input", store: archive); XCTFail() } catch {}
        remote.current = old; journal.failSave = true
        do { _ = try await service.send(plan, fileID: "selected", inputTab: "Input", store: archive); XCTFail() } catch {}
        journal.failSave = false
        _ = try archive.applyManual(change: .correctBest(accountID: testAccount, chartID: testChart, values: ScoreValues(score: 9_600_000)))
        do { _ = try await service.send(plan, fileID: "selected", inputTab: "Input", store: archive); XCTFail() } catch {}
        XCTAssertTrue(remote.writes.isEmpty); XCTAssertNil(journal.entry)
    }
    func testTimeoutRetainsJournalRecheckNeverResendsAndWaitsForCalculatedScore() async throws {
        let fixture = ConsultantExportTests(); let archive = try fixture.store(); let old = try fixture.snapshot()
        let remote = ExportRemoteMock(snapshot: old, after: old); remote.failWrite = true
        let journal = ExportJournalMock(); let service = ConsultantExportService(remote: remote, journal: journal)
        do { _ = try await service.send(archive.previewConsultantExport(old, accountID: testAccount, mode: .matchArcProbe), fileID: "selected", inputTab: "Input", store: archive); XCTFail() } catch {}
        XCTAssertNotNil(journal.entry)
        do { _ = try await service.verifyPending(fileID: "different"); XCTFail() } catch {}
        do { _ = try await service.verifyPending(fileID: "selected"); XCTFail() } catch {}
        remote.current = try fixture.snapshot(score: 9_900_000, raw: 9_950_000)
        do { _ = try await service.verifyPending(fileID: "selected"); XCTFail() } catch {}
        XCTAssertNotNil(journal.entry)
        remote.current = try fixture.snapshot(score: 9_950_000, raw: 9_950_000)
        let count = try await service.verifyPending(fileID: "selected")
        XCTAssertEqual(count, 1); XCTAssertNil(journal.entry); XCTAssertEqual(remote.writes.count, 1)
    }
    func testSelectionChangePreventsSendAndPersistentJournalBlocksSecondSend() async throws {
        let fixture = ConsultantExportTests(); let archive = try fixture.store(); let old = try fixture.snapshot()
        let remote = ExportRemoteMock(snapshot: old, after: old)
        let url = temporaryArchiveURL().deletingLastPathComponent().appendingPathComponent("pending.json")
        let journal = FileConsultantExportJournal(url: url)
        let service = ConsultantExportService(remote: remote, journal: journal)
        let plan = try archive.previewConsultantExport(old, accountID: testAccount, mode: .matchArcProbe)
        do { _ = try await service.send(plan, fileID: "selected", inputTab: "Input", store: archive) { throw ConsultantExportError.selection }; XCTFail() } catch {}
        XCTAssertTrue(remote.writes.isEmpty); XCTAssertNil(try journal.load())
        remote.failWrite = true
        do { _ = try await service.send(plan, fileID: "selected", inputTab: "Input", store: archive); XCTFail() } catch {}
        let restoredJournal = FileConsultantExportJournal(url: url)
        XCTAssertEqual(try restoredJournal.load()?.changes.first?.score, 9_950_000)
        let restarted = ConsultantExportService(remote: remote, journal: restoredJournal)
        do { _ = try await restarted.send(plan, fileID: "selected", inputTab: "Input", store: archive); XCTFail() } catch {}
        XCTAssertThrowsError(try restarted.dismissPendingAfterReview())
        XCTAssertEqual(remote.writes.count, 1)
        try restarted.dismissPendingAfterReview(now: Date().addingTimeInterval(301))
        XCTAssertNil(try restoredJournal.load())
        try Data("corrupted".utf8).write(to: url)
        XCTAssertThrowsError(try restoredJournal.load())
        do { _ = try await restarted.send(plan, fileID: "selected", inputTab: "Input", store: archive); XCTFail() } catch {}
        XCTAssertEqual(remote.writes.count, 1)
    }
    func testSendRevalidatesUsingReviewedModeRatherThanAuthoritativeMode() async throws {
        let fixture = ConsultantExportTests(); let old = try fixture.snapshot()
        let remote = ExportRemoteMock(snapshot: old, after: old); let journal = ExportJournalMock()
        let archive = try fixture.store(score: nil)
        let plan = try archive.previewConsultantExport(old, accountID: testAccount, mode: .improvementsOnly)
        let count = try await ConsultantExportService(remote: remote, journal: journal).send(plan, fileID: "selected", inputTab: "Input", store: archive)
        XCTAssertEqual(count, 0); XCTAssertTrue(remote.writes.isEmpty); XCTAssertNil(journal.entry)
    }
    func testNoChangesNeedsNoWriteOrJournal() async throws {
        let fixture = ConsultantExportTests(); let archive = try fixture.store(score: 9_900_000); let old = try fixture.snapshot()
        let remote = ExportRemoteMock(snapshot: old, after: old); let journal = ExportJournalMock()
        let count = try await ConsultantExportService(remote: remote, journal: journal).send(archive.previewConsultantExport(old, accountID: testAccount, mode: .matchArcProbe), fileID: "selected", inputTab: "Input", store: archive)
        XCTAssertEqual(count, 0); XCTAssertTrue(remote.writes.isEmpty); XCTAssertNil(journal.entry)
    }

}

@MainActor private final class ExportRemoteMock: ConsultantExportRemote {
    var current: ConsultantExportSnapshot; var after: ConsultantExportSnapshot
    var failWrite = false; var onWrite: (() -> Void)?
    var writes: [[ConsultantScoreWrite]] = []
    init(snapshot: ConsultantExportSnapshot, after: ConsultantExportSnapshot) { current = snapshot; self.after = after }
    func exportSnapshot(fileID: String, inputTab: String) async throws -> ConsultantExportSnapshot { current }
    func writeScores(fileID: String, inputTab: String, changes: [ConsultantScoreWrite]) async throws {
        onWrite?(); writes.append(changes)
        if failWrite { throw URLError(.timedOut) }
        current = after
    }
}
@MainActor private final class ExportJournalMock: ConsultantExportJournalStore {
    var entry: ConsultantExportJournal?; var failSave = false
    func load() throws -> ConsultantExportJournal? { entry }
    func save(_ entry: ConsultantExportJournal) throws { if failSave { throw URLError(.cannotWriteToFile) }; self.entry = entry }
    func clear() throws { entry = nil }
}
