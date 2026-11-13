import ArcaeaCore
import SwiftUI

/// The subscribed account whose full score list and potential history are imported.
struct MainAccountView: View {
    @Environment(ArchiveModel.self) private var model
    @Environment(OnlineRuntime.self) private var runtime
    @State private var login: LoginRequest?
    @State private var confirmingSignOut = false
    @State private var importTask: Task<Void, Never>?
    var body: some View {
        List {
            Section {
                LabeledContent("Signed in as", value: runtime.mainProfile.map { $0.displayName ?? $0.id.rawValue } ?? "Not signed in")
                Button(runtime.mainProfile == nil ? "Sign in" : "Switch account", systemImage: "person.crop.circle") { login = LoginRequest(role: .main) }
                    .disabled(runtime.isImporting).accessibilityIdentifier("main.signIn")
            }
            Section {
                Button("Import scores and potential history", systemImage: "arrow.down.circle") { startImport() }
                    .disabled(runtime.mainProfile == nil || runtime.isImporting).accessibilityIdentifier("main.import")
                if runtime.isImporting {
                    HStack { ProgressView(); Text(runtime.progress).font(.subheadline); Spacer(); Button("Cancel") { importTask?.cancel() } }
                } else if !runtime.progress.isEmpty {
                    Text(runtime.progress).font(.subheadline).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Needs an active Arcaea Online subscription. The import is the source of truth: for every chart it returns, it replaces local, manual and sheet scores.")
            }
            if runtime.mainProfile != nil {
                Section { Button("Sign out", role: .destructive) { confirmingSignOut = true }.disabled(runtime.isImporting) }
            }
        }
        .navigationTitle("Main account").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $login) { OfficialLoginView(request: $0) }
        .confirmationDialog("Sign out of the main account?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { do { try await runtime.disconnect(role: .main) } catch { model.errorMessage = error.localizedDescription } } }
        } message: { Text("Saved scores and history stay on this device.") }
        .task { await runtime.refreshStatus() }
    }
    private func startImport() {
        importTask = Task {
            do {
                let receipt = try await runtime.fullImport()
                model.selectedAccountID = receipt.accountID
                try model.reload()
                model.notice = "Import complete: \(receipt.addedCount) new plays"
            } catch { model.errorMessage = error.localizedDescription }
            importTask = nil
        }
    }
}
