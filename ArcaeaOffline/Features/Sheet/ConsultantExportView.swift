import SwiftUI
import ArcaeaCore

struct ConsultantExportView: View {
    @Environment(ArchiveModel.self) private var archive
    @State private var model = ConsultantProbeModel.shared
    @State private var confirm = false
    @State private var mode: ConsultantExportMode = .improvementsOnly
    private var accountName: String { archive.selectedProfile?.displayName ?? archive.selectedAccountID?.rawValue ?? "No account selected" }
    private var plan: ConsultantExportPlan? { model.exportPlan?.accountID == archive.selectedAccountID && model.exportPlan?.mode == mode ? model.exportPlan : nil }
    private var reviewedEntries: [ConsultantExportPlan.Entry] { plan?.entries.filter { $0.disposition != .unchanged } ?? [] }
    var body: some View {
        List {
            Section("Send from \(accountName)") {
                if let account = archive.selectedAccountID, archive.profiles.count > 1 {
                    Picker("Account", selection: Binding(get: { account }, set: { selected in
                        archive.perform { archive.selectedAccountID = selected; try archive.reload() }
                        model.clearExportPreview()
                    })) {
                        ForEach(archive.profiles, id: \.id) { profile in Text(profile.displayName ?? profile.id.rawValue).tag(profile.id) }
                    }.disabled(model.busy)
                }
                if let metadata = model.metadata { LabeledContent("Workbook", value: metadata.title) }
                Picker("Send mode", selection: $mode) {
                    Text("Only improvements").tag(ConsultantExportMode.improvementsOnly)
                    Text("Match ArcProbe").tag(ConsultantExportMode.matchArcProbe)
                }
                .disabled(model.busy || model.exportPending)
                .accessibilityIdentifier("sheet.export.mode")
                Text(mode == .improvementsOnly
                     ? "Send only higher or new ArcProbe bests. Higher sheet scores and scores missing from ArcProbe are kept."
                     : "The sheet will match this account's best scores, including lower scores. A sheet score is cleared when ArcProbe has no score for its chart. Import any scores you want to keep before sending.")
                Text("Only recognized mobile score cells are updated. Formulas, unrecognized charts, Switch scores, clear flags and other settings are kept. Close other sheet editors while sending.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Refresh send preview") { Task { await refresh() } }
                    .disabled(model.busy || archive.selectedAccountID == nil || model.exportPending)
                    .accessibilityIdentifier("sheet.export.refresh")
            }
            Section("Review") {
                if model.busy { ProgressView() }
                Text(model.status).accessibilityIdentifier("sheet.export.status")
                if let plan {
                    LabeledContent("Higher / new scores", value: String(plan.entries.filter { $0.disposition == .increase }.count))
                    LabeledContent("Lower scores", value: String(plan.entries.filter { $0.disposition == .decrease }.count))
                    LabeledContent("Scores to clear", value: String(plan.entries.filter { $0.disposition == .clear }.count))
                    LabeledContent("Higher sheet scores kept", value: String(plan.entries.filter { $0.disposition == .keepHigher }.count))
                    LabeledContent("Already matching", value: String(plan.entries.filter { $0.disposition == .unchanged }.count))
                    Button("Send \(plan.changes.count) reviewed changes", role: mode == .matchArcProbe ? .destructive : nil) { confirm = true }
                        .disabled(plan.changes.isEmpty || model.busy || model.exportPending)
                        .accessibilityIdentifier("sheet.export.apply")
                }
                if model.exportPending {
                    Text("The last send still needs checking. Go back to Consultant sheet to check it before sending again.").foregroundStyle(.orange)
                }
            }
            if plan != nil {
                Section("Changes and skipped rows") {
                    if reviewedEntries.isEmpty { Text("All recognized mobile scores already match.").foregroundStyle(.secondary) }
                    ForEach(reviewedEntries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.title.isEmpty ? "Unrecognized row \(entry.id)" : entry.title).font(.headline)
                            if entry.changesScore, let old = entry.previousScore, let new = entry.score {
                                Text("\(DisplayFormat.score(old)) → \(new == 0 ? "Unplayed" : DisplayFormat.score(new))").monospacedDigit()
                            }
                            Text(reason(entry.disposition)).font(.subheadline)
                                .foregroundStyle(entry.changesScore ? Color.orange : Color.secondary)
                        }.padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle("Send scores to sheet")
        .task { await refresh() }
        .onChange(of: mode) { _, _ in
            confirm = false
            model.clearExportPreview()
            Task { await refresh() }
        }
        .confirmationDialog(mode == .improvementsOnly ? "Send improvements from \(accountName)?" : "Make the sheet match \(accountName)?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Send reviewed changes", role: mode == .matchArcProbe ? .destructive : nil) { Task { await model.applyExport(archive: archive, mode: mode) } }
        } message: {
            Text(mode == .improvementsOnly
                 ? "Send \(plan?.changes.count ?? 0) higher or new scores to the selected workbook. Higher sheet scores will be kept. Keep ArcProbe open until verification finishes."
                 : "This changes \(plan?.changes.count ?? 0) mobile scores in the selected Google workbook, including the lower scores and clears shown above. ArcProbe's archive stays unchanged. Keep the app open until verification finishes.")
        }
    }
    private func refresh() async {
        guard let account = archive.selectedAccountID else { return }
        await model.previewExport(store: archive.store, accountID: account, mode: mode)
    }
    private func reason(_ disposition: ConsultantExportPlan.Disposition) -> String {
        switch disposition {
        case .increase: "Ready — higher or new best"
        case .decrease: "Ready — replace with lower ArcProbe best"
        case .clear: "Ready — clear score absent from ArcProbe"
        case .unchanged: "Already matching"
        case .keepHigher: "Kept — sheet score is higher or absent from ArcProbe"
        case .formula: "Skipped — input contains a formula"
        case .unmapped: "Skipped — song not recognized"
        case .ambiguous: "Skipped — more than one chart matches"
        case .invalid: "Skipped — unsupported score, difficulty or note count"
        case .duplicate: "Skipped — multiple sheet rows match this chart"
        }
    }
}
