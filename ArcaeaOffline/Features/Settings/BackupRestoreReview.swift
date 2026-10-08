import ArcaeaCore
import Foundation
import SwiftUI

struct BackupRestorePreview: Identifiable, Sendable {
    let id = UUID()
    let data: Data
    let accountCount: Int
    let playCount: Int
    let historyCount: Int
    static func validate(_ data: Data) throws -> BackupRestorePreview {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("restore-review-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ArchiveStore(url: directory.appendingPathComponent("review.sqlite"))
        _ = try ArchiveBackup(store: store).validateAndRestore(data: data)
        let profiles = try store.profiles()
        var plays = 0, history = 0
        for profile in profiles {
            plays += try store.sourceObservations(accountID: profile.id).count
            history += try store.potentialHistory(accountID: profile.id).count
        }
        return BackupRestorePreview(data: data, accountCount: profiles.count, playCount: plays, historyCount: history)
    }
}

struct BackupRestoreReview: View {
    @Environment(ArchiveModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let preview: BackupRestorePreview
    @State private var restoring = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Validated backup") { LabeledContent("Saved accounts", value: String(preview.accountCount)); LabeledContent("Source plays", value: String(preview.playCount)); LabeledContent("Official history points", value: String(preview.historyCount)) }
                Section { Text("Restoring replaces your saved archive with this backup, including its corrections and deletion markers. Export your current archive first if you want to keep it.").foregroundStyle(.secondary) }
                Section { Button("Replace saved archive", role: .destructive) { restoring = true; model.perform { try model.restoreBackup(preview.data); dismiss() }; restoring = false }.disabled(restoring).accessibilityIdentifier("confirmRestore") }
            }
            .navigationTitle("Restore backup").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Cancel") { dismiss() }.disabled(restoring) }
        }
    }
}
