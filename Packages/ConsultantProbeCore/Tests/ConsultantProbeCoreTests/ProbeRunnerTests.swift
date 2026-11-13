import XCTest
@testable import ConsultantProbeCore

@MainActor final class ProbeRunnerTests: XCTestCase {
    let tab = "점수 입력 [Score Input]"
    func testSuccessfulProbeRestoresBaselineAndClearsJournal() async throws {
        let sheet = MemorySheet(), journal = MemoryJournal()
        let runner = ProbeRunner(sheet: sheet, journal: journal, pause: {})
        let passed = try await runner.run(fileID: ProbeRunner.testFileID, inputTab: tab)
        XCTAssertTrue(passed)
        XCTAssertEqual(sheet.values, [9_975_813, 0])
        XCTAssertEqual(sheet.current.input, 0)
        XCTAssertNil(journal.value)
    }
    func testRejectsOtherWorkbookWithoutWriting() async {
        let sheet = MemorySheet(), journal = MemoryJournal()
        do { _ = try await ProbeRunner(sheet: sheet, journal: journal, pause: {}).run(fileID: "private-real-scores", inputTab: tab); XCTFail() } catch {}
        XCTAssertTrue(sheet.values.isEmpty)
        XCTAssertNil(journal.value)
    }
    func testDoesNotOverwriteExistingScoreOrWrongChart() async {
        for baseline in [ProbeSnapshot(input: 9_800_000, decoded: 9_800_000, rating: 3, priority: 0), ProbeSnapshot(input: 0, decoded: 0, rating: 0, priority: 0, identity: "Other [PST]")] {
            let sheet = MemorySheet(), journal = MemoryJournal(); sheet.current = baseline
            do { _ = try await ProbeRunner(sheet: sheet, journal: journal, pause: {}).run(fileID: ProbeRunner.testFileID, inputTab: tab); XCTFail() } catch {}
            XCTAssertTrue(sheet.values.isEmpty)
        }
    }
    func testJournalFailurePreventsNetworkWrite() async {
        let sheet = MemorySheet(), journal = MemoryJournal(); journal.failSave = true
        do { _ = try await ProbeRunner(sheet: sheet, journal: journal, pause: {}).run(fileID: ProbeRunner.testFileID, inputTab: tab); XCTFail() } catch {}
        XCTAssertTrue(sheet.values.isEmpty)
    }
    func testUncertainWriteKeepsJournalAndCanRecoverAfterRelaunch() async throws {
        let sheet = MemorySheet(), journal = MemoryJournal(); sheet.failAfterWrite = true
        do { _ = try await ProbeRunner(sheet: sheet, journal: journal, pause: {}).run(fileID: ProbeRunner.testFileID, inputTab: tab); XCTFail() } catch {}
        XCTAssertNotNil(journal.value)
        XCTAssertEqual(sheet.current.input, 9_975_813)
        sheet.failAfterWrite = false
        try await ProbeRunner(sheet: sheet, journal: journal, pause: {}).restore()
        XCTAssertEqual(sheet.current.input, 0)
        XCTAssertNil(journal.value)
    }
    func testRecoveryRefusesAnotherEditorsChange() async throws {
        let sheet = MemorySheet(), journal = MemoryJournal()
        journal.value = ProbeJournal(fileID: ProbeRunner.testFileID, inputTab: tab, baseline: sheet.current)
        sheet.current.input = 123
        do { try await ProbeRunner(sheet: sheet, journal: journal, pause: {}).restore(); XCTFail() } catch {}
        XCTAssertEqual(sheet.current.input, 123)
        XCTAssertTrue(sheet.values.isEmpty)
        XCTAssertNotNil(journal.value)
    }
    func testNoRecalculationReportsFailureButStillRestores() async throws {
        let sheet = MemorySheet(), journal = MemoryJournal(); sheet.recalculates = false
        let passed = try await ProbeRunner(sheet: sheet, journal: journal, pause: {}).run(fileID: ProbeRunner.testFileID, inputTab: tab)
        XCTAssertFalse(passed)
        XCTAssertEqual(sheet.current.input, 0)
        XCTAssertNil(journal.value)
    }
    func testUncertainWriteCannotClearJournalWhileDelayedServerCommitIsStillPossible() async throws {
        let sheet = MemorySheet(), journal = MemoryJournal()
        journal.value = ProbeJournal(fileID: ProbeRunner.testFileID, inputTab: tab, baseline: sheet.current)
        // The server has not yet applied a request that timed out locally.
        do { try await ProbeRunner(sheet: sheet, journal: journal, pause: {}).restore(); XCTFail("Must not claim restoration") } catch {}
        XCTAssertNotNil(journal.value)
        // The delayed server commit is now visible. Recovery may restore it safely.
        sheet.current = ProbeSnapshot(input: 9_975_813, decoded: 9_975_813, rating: 3.579065, priority: 0.11196)
        try await ProbeRunner(sheet: sheet, journal: journal, pause: {}).restore()
        XCTAssertEqual(sheet.current.input, 0)
        XCTAssertNil(journal.value)
    }
    func testUncertainRestoreDoesNotSendAnotherWriteOrClearItsJournal() async throws {
        let sheet = MemorySheet(), journal = MemoryJournal(); sheet.failBeforeRestore = true
        do { _ = try await ProbeRunner(sheet: sheet, journal: journal, pause: {}).run(fileID: ProbeRunner.testFileID, inputTab: tab); XCTFail() } catch {}
        XCTAssertEqual(sheet.current.input, 9_975_813)
        sheet.failBeforeRestore = false
        do { try await ProbeRunner(sheet: sheet, journal: journal, pause: {}).restore(); XCTFail("An unresolved restore needs investigation") } catch {}
        XCTAssertEqual(sheet.values, [9_975_813])
        XCTAssertNotNil(journal.value)
    }
    func testPendingJournalPreventsNewTest() async {
        let sheet = MemorySheet(), journal = MemoryJournal()
        journal.value = ProbeJournal(fileID: ProbeRunner.testFileID, inputTab: tab, baseline: sheet.current)
        do { _ = try await ProbeRunner(sheet: sheet, journal: journal, pause: {}).run(fileID: ProbeRunner.testFileID, inputTab: tab); XCTFail() } catch {}
        XCTAssertTrue(sheet.values.isEmpty)
        XCTAssertNotNil(journal.value)
    }
}
@MainActor final class MemoryJournal: ProbeJournalStore {
    var value: ProbeJournal?
    var failSave = false
    func load() throws -> ProbeJournal? { value }
    func save(_ journal: ProbeJournal) throws { if failSave { throw TestError.network }; value = journal }
    func clear() throws { value = nil }
}
@MainActor final class MemorySheet: ProbeSheet {
    var current = ProbeSnapshot(input: 0, decoded: 0, rating: 0, priority: -0.01822)
    var values: [Double] = []
    var failAfterWrite = false
    var recalculates = true
    var failBeforeRestore = false
    func snapshot(fileID: String, inputTab: String) async throws -> ProbeSnapshot {
        if failAfterWrite && !values.isEmpty { throw TestError.network }
        return current
    }
    func write(fileID: String, inputTab: String, value: Double) async throws {
        if value == 0, failBeforeRestore { throw TestError.network }
        values.append(value); current.input = value
        if recalculates { current.decoded = value; current.rating = value == 0 ? 0 : 3.579065; current.priority = value == 0 ? -0.01822 : 0.11196 }
        if failAfterWrite { throw TestError.network }
    }
}
enum TestError: Error { case network }
