import ArcaeaCore
import SwiftUI

struct ScoreDetailView: View {
    @Environment(ArchiveModel.self) private var model
    let chart: ChartID
    @State private var editor: ScoreEditorDestination?
    @State private var deleting: EffectiveObservation?
    private var best: BestScore? { model.bestScores.first { $0.chartID == chart } }
    private var plays: [EffectiveObservation] { model.observations.filter { $0.original.chartID == chart }.sorted { ($0.values.playedAt?.date ?? $0.original.firstSeenAt) > ($1.values.playedAt?.date ?? $1.original.firstSeenAt) } }
    var body: some View {
        List {
            Section {
                HStack(spacing: 20) { CoverPlaceholder(chart: chart, size: 90); VStack(alignment: .leading, spacing: 8) { Text(model.title(chart)).font(.title2.bold()); if let artist = model.artist(chart) { Text(artist).foregroundStyle(.secondary) }; ChartBadge(chart: chart, level: model.catalog[chart]?.level) } }.padding(.vertical, 8)
            }
            if let best {
                Section("Chart best") {
                    LabeledContent("Score", value: DisplayFormat.score(best.values.score))
                    LabeledContent("Grade", value: DisplayFormat.grade(best.values.score))
                    LabeledContent("Play rating (estimate)", value: model.rating(chart))
                    LabeledContent("Best clear", value: DisplayFormat.clear(best.bestClear))
                    LabeledContent("Chart constant", value: model.catalog[chart]?.usableConstant.map { String(format: "%.1f", $0.value) } ?? "Unknown / outdated")
                    if best.isBestCorrection { Label("Best-score correction applied", systemImage: "pencil").foregroundStyle(.orange); Button("Reset best to imported data") { model.perform { try model.resetBest(chart) } } }
                    Button("Correct chart best") { editor = .correctBest(chart, best.values) }
                }
            }
            Section("Saved plays · \(plays.count)") {
                ForEach(plays, id: \.original.id) { play in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text(DisplayFormat.score(play.values.score)).font(.title3.weight(.semibold).monospacedDigit()); Spacer(); Text(DisplayFormat.clear(play.values.playClear)).font(.caption).foregroundStyle(.secondary) }
                        HStack { Text(model.sourceLabel(play)); if play.isOverridden { Label("Edited", systemImage: "pencil").foregroundStyle(.orange) } }.font(.caption).foregroundStyle(.secondary)
                        Text(DisplayFormat.date(play.values.playedAt)).font(.subheadline).foregroundStyle(.secondary)
                        if let timestamp = play.values.playedAt { Text(timestamp.origin == .manual ? "Manually recorded date" : "Server-provided date").font(.caption2).foregroundStyle(.secondary) }
                        if let modifier = play.values.modifier { Text("Gauge modifier: \(modifier)").font(.caption).foregroundStyle(.secondary) }
                        if let health = play.values.health { Text("Health: \(health)").font(.caption).foregroundStyle(.secondary) }
                        if let judgments = play.values.judgments {
                            HStack { judgment("PURE", judgments.pure, .purple); judgment("FAR", judgments.far, .orange); judgment("LOST", judgments.lost, .pink) }
                        } else { Text("Judgments unknown").font(.caption).foregroundStyle(.secondary) }
                        HStack { Button("Edit") { editor = .edit(play) }; if play.isOverridden { Button("Reset") { model.perform { try model.resetOverride(play) } } }; Spacer(); Button("Delete", role: .destructive) { deleting = play } }.font(.subheadline).buttonStyle(.borderless)
                    }.padding(.vertical, 8).accessibilityIdentifier("play-\(play.original.id.rawValue)")
                }
            }
            Section { Text("Edits are local to your archive. Official potential history keeps its original values.").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle(model.title(chart)).navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Add play", systemImage: "plus") { editor = .addForChart(chart) } }
        .sheet(item: $editor) { ScoreEditorView(destination: $0) }
        .confirmationDialog("Delete this saved play?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete play", role: .destructive) { if let deleting { model.perform { try model.delete(deleting) } }; deleting = nil }
        } message: { Text("You can undo this change. The same imported record stays hidden after future imports.") }
    }
    private func judgment(_ title: String, _ value: Int?, _ color: Color) -> some View { VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption2.bold()).foregroundStyle(color); Text(value.map(String.init) ?? "—").font(.headline.monospacedDigit()) }.frame(maxWidth: .infinity, alignment: .leading) }
}
