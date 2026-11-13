import SwiftUI
import ArcaeaCore

struct ConsultantImportView: View {
    @Environment(ArchiveModel.self) private var archive
    @State private var model = ConsultantProbeModel.shared
    @State private var confirm = false
    private var account: AccountID { archive.selectedAccountID ?? AccountID("local") }
    private var accountName: String { archive.selectedProfile?.displayName ?? archive.selectedAccountID?.rawValue ?? "Local archive" }
    var body: some View {
        List {
            Section("Import into \(accountName)") {
                if archive.profiles.count > 1 {
                    Picker("Account", selection: Binding(get: { account }, set: { selected in
                        archive.perform {
                            archive.selectedAccountID = selected
                            try archive.reload()
                        }
                        model.clearImportPreview()
                    })) {
                        ForEach(archive.profiles, id: \.id) { profile in Text(profile.displayName ?? profile.id.rawValue).tag(profile.id) }
                    }.disabled(model.busy)
                }
                Text("Mobile scores only. Higher existing bests, manual corrections and deletions are preserved. Play dates and clear lamps stay unknown. Potential history uses the import date; calculations and JPG export assume normal clear when no clear is known.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Refresh preview") { Task { await model.previewImport(store: archive.store, accountID: account) } }
                    .disabled(model.busy).accessibilityIdentifier("sheet.import.refresh")
            }
            Section("Review") {
                if model.busy { ProgressView() }
                Text(model.status).accessibilityIdentifier("sheet.import.status")
                if let plan = model.importPlan, plan.accountID == account {
                    LabeledContent("Ready to import", value: String(plan.addCount))
                    LabeledContent("Skipped scored rows", value: String(plan.entries.count - plan.addCount))
                    LabeledContent("Empty / unplayed rows", value: String(plan.emptyCount))
                    Button("Import \(plan.addCount) scores") { confirm = true }
                        .disabled(plan.addCount == 0 || model.busy)
                        .accessibilityIdentifier("sheet.import.apply")
                }
            }
            if let plan = model.importPlan, plan.accountID == account {
                Section("Scored rows") {
                    if plan.entries.isEmpty { Text("No scored mobile charts were found in this sheet.").foregroundStyle(.secondary) }
                    ForEach(plan.entries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.title.isEmpty ? "Unrecognized row \(entry.id)" : entry.title).font(.headline)
                            if let score = entry.score { Text(DisplayFormat.score(score)).monospacedDigit() }
                            Text(reason(entry.disposition)).font(.subheadline)
                                .foregroundStyle(entry.disposition == .add ? Color.green : Color.secondary)
                            if let old = entry.previousScore { Text("Current best: \(DisplayFormat.score(old))").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle("Import sheet scores")
        .task { await model.previewImport(store: archive.store, accountID: account) }
        .confirmationDialog("Import \(model.importPlan?.addCount ?? 0) scores into \(accountName)?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Import reviewed scores") { Task { await model.applyImport(archive: archive) } }
        } message: { Text("Only rows marked Ready will be added to ArcProbe. The Google workbook will stay unchanged.") }
    }
    private func reason(_ disposition: ConsultantImportPlan.Disposition) -> String {
        switch disposition {
        case .add: "Ready — new chart best"
        case .keepExisting: "Skipped — existing best is equal or higher"
        case .manualProtected: "Skipped — manual correction or deletion is preserved"
        case .unmapped: "Skipped — song not matched; try updating chart metadata"
        case .ambiguous: "Skipped — more than one chart matches this title"
        case .invalid: "Skipped — unsupported score, difficulty or note count"
        case .duplicate: "Skipped — multiple sheet rows match the same chart"
        }
    }
}
