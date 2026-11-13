import SwiftUI
import SafariServices

/// Import from and export to the player's Arcaea consultant workbook in Google Sheets.
/// Nothing is transferred without a preview and a confirmation.
struct SheetView: View {
    @State private var model = ConsultantProbeModel.shared
    @State private var confirmDismissSend = false
    @State private var confirmDisconnect = false
    @State private var editor: EditorDestination?
    @State private var showDiagnostics = false
    private var blocked: Bool { !model.connected || model.busy || model.pending || model.journalUnreadable || model.exportPending || model.exportJournalUnreadable }
    var body: some View {
        Form {
            Section {
                LabeledContent("Workbook", value: model.metadata?.title ?? (model.connected ? "Connected" : "Not connected"))
                Button(model.connected ? "Choose another workbook" : "Connect Google and choose workbook", systemImage: "link") { Task { await model.connect() } }
                    .disabled(model.busy || model.journalUnreadable || model.exportJournalUnreadable)
                    .accessibilityIdentifier("sheet.connect")
                if let url = model.sheetURL {
                    Button("Open workbook", systemImage: "safari") { model.editorOpened(); editor = EditorDestination(url: url) }
                }
            } header: { Text("Google Sheets") } footer: {
                Text("ArcProbe can only reach the one workbook you pick.")
            }
            Section {
                NavigationLink { ConsultantImportView() } label: { Label("Import scores from sheet", systemImage: "square.and.arrow.down") }
                    .disabled(blocked).accessibilityIdentifier("sheet.import.open")
                NavigationLink { ConsultantExportView() } label: { Label("Send scores to sheet", systemImage: "square.and.arrow.up") }
                    .disabled(blocked).accessibilityIdentifier("sheet.export.open")
            } header: { Text("Scores") } footer: {
                Text("Both show a preview first. Importing keeps higher ArcProbe scores and manual corrections.")
            }
            if model.exportPending {
                Section("Last send needs checking") {
                    Text("The last send could not be confirmed. Checking again does not send anything.").foregroundStyle(.orange)
                    Button("Check the last send") { Task { await model.verifyExport() } }
                        .disabled(model.busy || !model.connected || model.exportJournalUnreadable)
                        .accessibilityIdentifier("sheet.export.verify")
                    Button("I checked the sheet myself — clear this") { confirmDismissSend = true }
                        .disabled(model.busy || model.exportJournalUnreadable)
                }
            }
            if model.pending {
                Section("Test cell needs restoring") {
                    Text("An earlier sheet test left a score of 9,975,813 in Score Input H5 of the test workbook. Reconnect to that workbook if needed, then restore it.")
                        .foregroundStyle(.orange)
                    Button("Restore test cell") { Task { await model.recover() } }
                        .disabled(model.busy || !model.connected || model.journalUnreadable)
                }
            }
            Section {
                HStack(alignment: .firstTextBaseline) {
                    if model.busy { ProgressView() }
                    Text(model.status).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled).accessibilityIdentifier("sheet.status")
                }
            }
            if model.connected {
                Section { Button("Disconnect Google", role: .destructive) { confirmDisconnect = true }.disabled(model.busy || model.pending || model.exportPending) }
            }
        }
        .navigationTitle("Consultant sheet").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Diagnostics", systemImage: "doc.text") { showDiagnostics = true }
                    .accessibilityIdentifier("sheet.diagnostics.toolbar")
            }
        }
        .navigationDestination(isPresented: $showDiagnostics) { ProbeDiagnosticsView(model: model) }
        .confirmationDialog("Clear the pending send record?", isPresented: $confirmDismissSend, titleVisibility: .visible) {
            Button("I checked the sheet — clear it", role: .destructive) { Task { await model.dismissExportAfterReview() } }
        } message: { Text("Only do this after looking at the actual sheet. Nothing is undone or sent again.") }
        .confirmationDialog("Disconnect Google?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { model.disconnect() }
        } message: { Text("ArcProbe forgets the Google login on this device. Your workbook is not changed.") }
        .fullScreenCover(item: $editor) { destination in
            ProbeBrowser(url: destination.url, didLoad: { model.editorInitialLoad($0) })
                .ignoresSafeArea()
        }
        .task { if model.connected, model.metadata == nil, !model.busy { await model.read() } }
    }
}

private struct EditorDestination: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ProbeDiagnosticsView: View {
    let model: ConsultantProbeModel
    @State private var copied = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if copied { Text("Report copied").foregroundStyle(.green).accessibilityIdentifier("sheet.diagnostics.copied") }
                Text("A log of recent sheet operations. It contains no account names, workbook IDs, tokens or scores.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if model.diagnosticsSaveFailed {
                    Text("The report could not be saved locally. You can still copy it here.").foregroundStyle(.orange)
                }
                Text(model.report).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sheet.diagnostics.text")
            }.padding()
        }
        .navigationTitle("Diagnostics").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Copy report", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = model.report; copied = true
                }.accessibilityIdentifier("sheet.diagnostics.copy")
            }
        }
    }
}

/// Safari owns navigation, website authentication and redirects. No OAuth tokens are injected.
private struct ProbeBrowser: UIViewControllerRepresentable {
    let url: URL
    let didLoad: @MainActor (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(didLoad: didLoad, done: { dismiss() }) }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .done
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let didLoad: @MainActor (Bool) -> Void
        let done: @MainActor () -> Void
        init(didLoad: @escaping @MainActor (Bool) -> Void, done: @escaping @MainActor () -> Void) {
            self.didLoad = didLoad; self.done = done
        }
        nonisolated func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
            Task { @MainActor [weak self] in self?.didLoad(didLoadSuccessfully) }
        }
        nonisolated func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            Task { @MainActor [weak self] in self?.done() }
        }
    }
}
