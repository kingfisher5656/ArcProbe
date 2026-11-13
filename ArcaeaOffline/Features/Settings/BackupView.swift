import ArcaeaCore
import SwiftUI
import UniformTypeIdentifiers

/// Export and restore of the score archive (JSON) and the downloaded cover art.
struct BackupView: View {
    @Environment(ArchiveModel.self) private var model
    private enum ImportKind { case scores, covers }
    private enum Presented: Identifiable {
        case share(ShareFile, cleanup: URL?)
        case review(BackupRestorePreview)
        var id: String { switch self { case .share(let file, _): "share:\(file.url.path)"; case .review(let preview): "review:\(preview.id)" } }
    }
    @State private var presented: Presented?
    @State private var importing: ImportKind?
    @State private var validating = false
    private var resources: LibraryResources { .shared }
    private var coversBusy: Bool { resources.downloading || resources.managingCoverBackup }
    var body: some View {
        List {
            Section {
                Button("Export scores", systemImage: "square.and.arrow.up") { model.perform { presented = .share(try model.backupFile(), cleanup: nil) } }
                    .accessibilityIdentifier("backup.export")
                Button("Restore scores", systemImage: "square.and.arrow.down") { importing = .scores }
                    .accessibilityIdentifier("backup.restore")
            } header: { Text("Scores") } footer: {
                Text("A JSON file with every account, play, correction and potential history point. Logins are never included. Restoring replaces the archive after you review it.")
            }
            Section {
                Button("Export cover art", systemImage: "square.and.arrow.up") { exportCovers() }.disabled(coversBusy)
                Button("Restore cover art", systemImage: "square.and.arrow.down") { importing = .covers }.disabled(coversBusy)
                if resources.managingCoverBackup { HStack { ProgressView(); Text("Working on cover backup…").font(.subheadline) } }
                if let message = resources.message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
            } header: { Text("Cover art") } footer: {
                Text("Saves downloaded covers so a reinstall does not have to download them again. Restoring merges and keeps whichever image is larger.")
            }
        }
        .navigationTitle("Backup & restore").navigationBarTitleDisplayMode(.inline)
        .overlay { if validating { ProgressView("Checking backup…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .sheet(item: $presented, onDismiss: nil) { item in
            switch item {
            case .share(let file, let cleanup): ShareSheet(file: file).onDisappear { if let cleanup { try? FileManager.default.removeItem(at: cleanup) } }
            case .review(let preview): BackupRestoreReview(preview: preview)
            }
        }
        .fileImporter(isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }),
                      allowedContentTypes: importing == .covers ? [.data] : [.json]) { result in
            let kind = importing; importing = nil
            switch (kind, result) {
            case (_, .failure(let error)): model.errorMessage = error.localizedDescription
            case (.covers, .success(let url)): Task { do { try await resources.restoreCoverBackup(from: url) } catch { model.errorMessage = error.localizedDescription } }
            case (_, .success(let url)): reviewScores(url)
            }
        }
    }
    private func exportCovers() {
        Task {
            do { let url = try await resources.exportCoverBackup(); presented = .share(ShareFile(url: url), cleanup: url.deletingLastPathComponent()) }
            catch { model.errorMessage = error.localizedDescription }
        }
    }
    private func reviewScores(_ url: URL) {
        Task {
            validating = true; defer { validating = false }
            do {
                let opened = url.startAccessingSecurityScopedResource()
                defer { if opened { url.stopAccessingSecurityScopedResource() } }
                let preview = try await Task.detached(priority: .userInitiated) {
                    try BackupRestorePreview.validate(Data(contentsOf: url, options: .mappedIfSafe))
                }.value
                presented = .review(preview)
            } catch { model.errorMessage = error.localizedDescription }
        }
    }
}
