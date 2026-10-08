import ArcaeaCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(ArchiveModel.self) private var model
    @State private var share: ShareFile?
    @State private var restoring = false
    @State private var restorePreview: BackupRestorePreview?
    @State private var validating = false
    var body: some View {
        Form {
            Section("Archive") {
                if model.profiles.count > 1 {
                    Picker("Saved account", selection: Binding(get: { model.selectedAccountID }, set: { model.selectedAccountID = $0; model.perform { try model.reload() } })) { ForEach(model.profiles, id: \.id) { Text($0.displayName ?? $0.id.rawValue).tag(Optional($0.id)) } }
                } else { LabeledContent("Saved account", value: model.selectedProfile?.displayName ?? model.selectedProfile?.id.rawValue ?? "Created on first manual entry") }
                LabeledContent("Saved plays", value: String(model.observations.count))
                LabeledContent("Chart bests", value: String(model.bestScores.count))
            }
            AccountSettingsSections()
            LibrarySettingsSection()
            NotificationSettingsSection()
            Section {
                Button("Export JSON backup", systemImage: "square.and.arrow.up") { model.perform { share = try model.backupFile() } }
                Button("Restore JSON backup", systemImage: "square.and.arrow.down") { restoring = true }
                NavigationLink("Diagnostics") { DiagnosticsView() }
            } header: { Text("Backup and recovery") } footer: { Text("Backups include saved accounts, scores, corrections, deletion markers, and history. Passwords and session cookies are excluded. Restore validates the whole file, then asks you to confirm replacing the saved archive.") }
            Section("About") {
                LabeledContent("App", value: "ArcProbe 0.2.2")
                LabeledContent("Minimum version", value: "iOS / iPadOS 18")
                Text("An unofficial, local score companion. This app reads account data and never uploads scores or modifies Arcaea.").font(.footnote).foregroundStyle(.secondary)
                Text("Refresh chart constants and download official covers below your account settings. Cached covers remain available offline.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Accounts & sync")
        .sheet(item: $share) { ShareSheet(file: $0) }
        .sheet(item: $restorePreview) { BackupRestoreReview(preview: $0) }
        .overlay { if validating { ProgressView("Validating backup…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .fileImporter(isPresented: $restoring, allowedContentTypes: [.json]) { result in
            Task {
                validating = true
                defer { validating = false }
                do {
                    let url = try result.get()
                    let opened = url.startAccessingSecurityScopedResource()
                    defer { if opened { url.stopAccessingSecurityScopedResource() } }
                    restorePreview = try await Task.detached(priority: .userInitiated) {
                        let data = try Data(contentsOf: url, options: .mappedIfSafe)
                        return try BackupRestorePreview.validate(data)
                    }.value
                } catch { model.errorMessage = error.localizedDescription }
            }
        }
    }
}
