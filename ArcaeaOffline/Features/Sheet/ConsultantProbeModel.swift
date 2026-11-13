import Foundation
import Observation
import UIKit
import ConsultantProbeCore
import ArcaeaCore

@MainActor @Observable final class ConsultantProbeModel {
    static let shared = ConsultantProbeModel()
    let auth = GoogleProbeAuth()
    private(set) var busy = false
    private(set) var importPlan: ConsultantImportPlan?
    private var importFileID: String?
    private(set) var exportPlan: ConsultantExportPlan?
    private var exportFileID: String?
    private var exportInputTab: String?
    private(set) var exportPending = false
    private(set) var exportJournalUnreadable = false
    private let exportJournal: FileConsultantExportJournal
    @ObservationIgnored private lazy var exportService = ConsultantExportService(remote: exportRemote, journal: exportJournal)
    private(set) var connected = false
    private(set) var pending = false
    private(set) var journalUnreadable = false
    private(set) var metadata: SheetMetadata?
    private(set) var status = "Connect Google to import or send sheet scores."
    private(set) var reportLines: [String] = []
    private(set) var refreshAvailable = false
    private(set) var diagnosticsSaveFailed = false
    private let diagnostics: ProbeDiagnosticStore
    private let journal: FileProbeJournal
    private var runner: ProbeRunner?
    @ObservationIgnored private lazy var api = GoogleSheetAPI(token: { [auth] in try await auth.token() })
    @ObservationIgnored private lazy var exportRemote = GoogleConsultantExportRemote(api: api)
    var selectedID: String? { auth.fileID }
    var sheetURL: URL? { selectedID.flatMap { URL(string: "https://docs.google.com/spreadsheets/d/\($0)/edit") } }
    static var versionLabel: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "unknown") (\(info["CFBundleVersion"] as? String ?? "unknown"))"
    }
    var report: String {
        (["ArcProbe \(Self.versionLabel) — Sheet diagnostics", "iOS: \(UIDevice.current.systemVersion)",
          "Installed bundle: \(Bundle.main.bundleIdentifier ?? "unknown")", "Expected bundle: app.arcaeaoffline",
          "Connected: \(connected); refresh token present: \(refreshAvailable)",
          "Recovery pending: \(pending); journal unreadable: \(journalUnreadable)",
          "Sheet send pending: \(exportPending); send record unreadable: \(exportJournalUnreadable)",
          "No account, workbook title/ID, tokens or scores included. Test-cell C5 character codes may be included.",
          "Current result: \(status)"] + reportLines).joined(separator: "\n")
    }
    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        exportJournal = FileConsultantExportJournal(url: base.appendingPathComponent("ConsultantProbe/pending-send.json"))
        journal = FileProbeJournal(url: base.appendingPathComponent("ConsultantProbe/pending-test.json"))
        diagnostics = ProbeDiagnosticStore(directory: base.appendingPathComponent("ConsultantProbe/Diagnostics"))
        do { reportLines = try diagnostics.loadLines() }
        catch { reportLines = ["Earlier diagnostic history could not be read."] }
        updateState()
        if connected { status = "Google connection restored." }
        if auth.storageIssue { status = "Saved Google session could not be loaded. Reconnect before testing." }
        saveDiagnostics()
    }
    func connect() async {
        await perform("Google sign-in / Picker") {
            let required = try self.journal.load()?.fileID ?? self.exportJournal.load()?.fileID
            self.metadata = nil
            self.clearImportPreview(); self.clearExportPreview()
            try await self.auth.connect(requiredFileID: required)
            self.updateState()
            try await self.readMetadata()
            self.record("Connected to the workbook.")
        }
    }
    func read() async {
        await perform("Sheet API read") {
            try await self.readMetadata()
            guard let metadata = self.metadata, let tab = metadata.inputTab else {
                self.record("This workbook does not look like a consultant sheet."); return
            }
            // Only inspect the fixed fixture in the designated disposable workbook.
            if metadata.id == ProbeRunner.testFileID {
                _ = try await self.api.snapshot(fileID: metadata.id, inputTab: tab)
                self.record("Test workbook ready. No cells changed.")
            } else { self.record("Workbook ready.") }
        }
    }
    func refresh() async {
        await perform("Refresh-token test") {
            _ = try await self.auth.token(forceRefresh: true)
            try await self.readMetadata()
            self.record("Forced refresh + API metadata: PASS.")
        }
    }
    func recover() async {
        await perform("Pending test recovery") {
            let runner = ProbeRunner(sheet: self.api, journal: self.journal); self.runner = runner
            defer { self.runner = nil }
            try await runner.restore()
            self.record("Recovery: original input and formula values verified. No pending test.")
        }
    }
    func disconnect() {
        guard !busy, !pending, !journalUnreadable, !exportPending, !exportJournalUnreadable else { return }
        do { try auth.disconnect(); metadata = nil; clearImportPreview(); clearExportPreview(); updateState(); record("Google session removed from this device. Google account access can also be revoked in Google settings.") }
        catch { record("Could not remove the saved Google session.") }
    }
    func clearImportPreview() { importPlan = nil; importFileID = nil }
    func previewImport(store: ArchiveStore, accountID: AccountID) async {
        guard !busy else { return }
        clearImportPreview()
        await perform("Read sheet scores") {
            guard !self.pending, !self.journalUnreadable, !self.exportPending, !self.exportJournalUnreadable else { throw ProbeError.pending }
            try await self.readMetadata()
            guard let fileID = self.selectedID, self.metadata?.inputTab != nil else { throw ConsultantImportError.unsupportedLayout }
            let snapshot = try ConsultantSnapshot.decode(await self.api.scoreImportData(fileID: fileID))
            let plan = try await Task.detached { try store.previewConsultantImport(snapshot, accountID: accountID) }.value
            guard self.selectedID == fileID else { throw ProbeError.invalidSelection }
            self.importPlan = plan; self.importFileID = fileID
            self.record("Import preview ready: \(plan.addCount) scores can be added; \(plan.entries.count - plan.addCount) scored rows skipped. No archive or sheet scores changed.")
        }
    }
    func applyImport(archive: ArchiveModel) async {
        await perform("Import sheet scores") {
            guard !self.pending, !self.journalUnreadable, !self.exportPending, !self.exportJournalUnreadable, let plan = self.importPlan,
                  let fileID = self.importFileID, self.selectedID == fileID,
                  plan.accountID == (archive.selectedAccountID ?? AccountID("local")) else { throw ConsultantImportError.stalePreview }
            let store = archive.store
            let receipt = try await Task.detached { try store.importConsultant(plan, fileID: fileID) }.value
            archive.selectedAccountID = plan.accountID
            try archive.reload()
            self.clearImportPreview()
            self.record("Imported \(receipt.addedCount) sheet scores into ArcProbe. Google sheet unchanged. History uses the import date; play dates and clear lamps remain unknown.")
        }
    }
    func clearExportPreview() { exportPlan = nil; exportFileID = nil; exportInputTab = nil }
    func previewExport(store: ArchiveStore, accountID: AccountID, mode: ConsultantExportMode) async {
        guard !busy else { return }
        clearExportPreview()
        await perform("Compare ArcProbe and sheet scores") {
            guard !self.pending, !self.journalUnreadable, !self.exportPending, !self.exportJournalUnreadable else { throw ConsultantExportError.pending }
            try await self.readMetadata()
            guard let fileID = self.selectedID, let tab = self.metadata?.inputTab else { throw ConsultantExportError.layout }
            let snapshot = try await self.exportRemote.exportSnapshot(fileID: fileID, inputTab: tab)
            let plan = try await Task.detached { try store.previewConsultantExport(snapshot, accountID: accountID, mode: mode) }.value
            guard self.selectedID == fileID else { throw ConsultantExportError.selection }
            self.exportPlan = plan; self.exportFileID = fileID; self.exportInputTab = tab
            self.record("Send preview ready: \(plan.changes.count) mobile score changes. Nothing sent yet.")
        }
    }
    func applyExport(archive: ArchiveModel, mode: ConsultantExportMode) async {
        await perform("Send reviewed scores") {
            guard !self.pending, !self.journalUnreadable, !self.exportPending, !self.exportJournalUnreadable,
                  let plan = self.exportPlan, plan.mode == mode, let fileID = self.exportFileID, let tab = self.exportInputTab,
                  self.selectedID == fileID, archive.selectedAccountID == plan.accountID else { throw ConsultantExportError.selection }
            let taskID = UIApplication.shared.beginBackgroundTask(withName: "Verify consultant scores")
            defer { if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) } }
            // Discard the preview after any attempted send. Recovery always reads the durable journal.
            defer { self.clearExportPreview(); self.clearImportPreview() }
            let count = try await self.exportService.send(plan, fileID: fileID, inputTab: tab, store: archive.store) {
                guard self.selectedID == fileID, archive.selectedAccountID == plan.accountID else { throw ConsultantExportError.selection }
            }
            self.record("Sent and verified \(count) mobile scores. ArcProbe's archive was unchanged.")
        }
    }
    func verifyExport() async {
        await perform("Verify pending sheet send") {
            guard let fileID = self.selectedID else { throw ConsultantExportError.selection }
            let count = try await self.exportService.verifyPending(fileID: fileID)
            self.record("Verified \(count) sent scores. Pending send cleared; no extra writes made.")
        }
    }
    func dismissExportAfterReview() async {
        await perform("Dismiss reviewed send record") {
            try self.exportService.dismissPendingAfterReview()
            self.clearExportPreview(); self.clearImportPreview()
            self.record("Pending send record dismissed after your review. No sheet cells changed. Refresh the preview before another send.")
        }
    }
    private func readMetadata() async throws {
        guard let fileID = auth.fileID else { throw ProbeError.invalidSelection }
        let result = try await api.metadata(fileID: fileID)
        guard result.id == fileID else { throw ProbeError.invalidSelection }
        metadata = result
    }
    private func perform(_ operation: String, body: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; status = operation + "…"
        defer { busy = false; updateState() }
        do { try await body() }
        catch {
            let message: String
            if let error = error as? ProbeError { message = error.localizedDescription }
            else if let error = error as? ConsultantExportError { message = error.localizedDescription }
            else if let error = error as? ConsultantImportError { message = error.localizedDescription }
            else if let error = error as? SheetReadError { message = error.localizedDescription }
            else if let error = error as? SheetHTTPError { message = error.localizedDescription }
            else if let error = error as? GoogleProbeAuth.AuthError { message = error.localizedDescription }
            else { message = "Network or local storage operation failed. Retry when connected and unlocked. Any pending recovery is retained." }
            record(operation + ": " + message)
        }
    }
    private func updateState() {
        connected = auth.connected; refreshAvailable = auth.canRefresh
        do { pending = try journal.load() != nil; journalUnreadable = false }
        catch { pending = true; journalUnreadable = true; status = "The recovery record cannot be read. Do not run another test or uninstall this build; inspect the test cell in Google Sheets." }
        do { exportPending = try exportJournal.load() != nil; exportJournalUnreadable = false }
        catch { exportPending = true; exportJournalUnreadable = true; status = "The pending send record cannot be read. Keep the app installed and check the sheet before sending again." }
        saveDiagnostics()
    }
    func editorOpened() { record("Opened Apple in-app browser. Its Google login is separate from API authorization.") }
    func editorInitialLoad(_ succeeded: Bool) {
        record(succeeded ? "In-app browser initial navigation loaded. Private workbook access and editing still require visual confirmation." : "In-app browser initial navigation failed. Check connectivity or try the external browser link.")
    }
    private func saveDiagnostics() {
        do { try diagnostics.save(lines: reportLines, report: report); diagnosticsSaveFailed = false }
        catch { diagnosticsSaveFailed = true }
    }
    private func record(_ message: String) {
        status = message
        reportLines.append(ISO8601DateFormatter().string(from: Date()) + " · " + message)
        reportLines = Array(reportLines.suffix(50))
        saveDiagnostics()
    }
}
