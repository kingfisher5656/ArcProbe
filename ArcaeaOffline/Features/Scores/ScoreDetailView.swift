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
                // The song on the left and its best result on the right; stacked when the screen is narrow.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { identity; Spacer(minLength: 16); result(.trailing) }
                    VStack(alignment: .leading, spacing: 16) { identity; result(.leading) }
                }.padding(.vertical, 8)
            }
            if let best {
                Section("Chart best") {
                    HStack(alignment: .top) {
                        figure("Play rating", model.rating(chart), note: "Estimate")
                        figure("Chart constant", model.catalog[chart]?.usableConstant.map { String(format: "%.1f", $0.value) } ?? String(localized: "Unknown"))
                        if let notes = model.catalog[chart]?.noteCount { figure("Notes", notes.formatted()) }
                    }.padding(.vertical, 4)
                    if let judgments = best.values.judgments { JudgmentBar(judgments: judgments).padding(.vertical, 4) }
                    if best.isBestCorrection {
                        Label("Best-score correction applied", systemImage: "pencil").foregroundStyle(.orange)
                        Button("Reset best to imported data") { model.perform { try model.resetBest(chart) } }
                    }
                    Button("Correct chart best") { editor = .correctBest(chart, best.values) }
                }
            }
            Section {
                let changes = PlayHistory.changes(plays)
                ForEach(plays, id: \.original.id) { play in
                    playRow(play, change: changes[play.original.id])
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Not a destructive-role button: the row must stay until the deletion is confirmed.
                            Button("Delete", systemImage: "trash") { deleting = play }.tint(.red)
                            Button("Edit", systemImage: "pencil") { editor = .edit(play) }.tint(.blue)
                        }
                }
            } header: { Text("Plays · \(plays.count)") } footer: {
                Text("Edits stay on this device. A main-account import replaces them for the charts it returns.")
            }
        }
        .navigationTitle(model.title(chart)).navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Add play", systemImage: "plus") { editor = .addForChart(chart) } }
        .sheet(item: $editor) { ScoreEditorView(destination: $0) }
        // An alert, not a confirmation dialog: on iPad the dialog is a popover pinned to the top of the list,
        // far from the play that was tapped and without its title.
        .alert("Delete this saved play?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { play in
            Button("Delete play", role: .destructive) { model.perform { try model.delete(play) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in Text("You can undo this right after.") }
    }

    private var identity: some View {
        HStack(spacing: 18) {
            CoverPlaceholder(chart: chart, size: 132)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.title(chart)).font(.title2.bold()).lineLimit(3)
                if let artist = model.artist(chart) { Text(artist).foregroundStyle(.secondary).lineLimit(2) }
                if let pack = LibraryResources.shared.packs.pack(forSong: chart.songID) { Text(pack.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                ChartBadge(chart: chart, level: model.catalog[chart]?.level).padding(.top, 2)
            }
        }
    }
    @ViewBuilder private func result(_ alignment: HorizontalAlignment) -> some View {
        if let best {
            VStack(alignment: alignment, spacing: 4) {
                Text(DisplayFormat.score(best.values.score)).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
                HStack(spacing: 10) {
                    Text(DisplayFormat.grade(best.values.score)).font(.title3.bold())
                    ClearLamp(clear: best.bestClear)
                }
            }.accessibilityElement(children: .combine)
        }
    }
    private func figure(_ title: LocalizedStringKey, _ value: String, note: LocalizedStringKey? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
            if let note { Text(note).font(.caption2).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private func playRow(_ play: EffectiveObservation, change: PlayChange?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(DisplayFormat.score(play.values.score)).font(.headline.monospacedDigit())
                    Text(DisplayFormat.grade(play.values.score)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    ClearLamp(clear: play.values.playClear)
                    if play.isOverridden { Label("Edited", systemImage: "pencil").font(.caption).foregroundStyle(.orange) }
                    if let change { PlayChangeLabel(change: change) }
                }
                Text(origin(play)).font(.subheadline).foregroundStyle(.secondary)
                if let counts = counts(play) { Text(counts).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Menu {
                Button("Edit", systemImage: "pencil") { editor = .edit(play) }
                if play.isOverridden { Button("Reset to original", systemImage: "arrow.uturn.backward") { model.perform { try model.resetOverride(play) } } }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = play }
            } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 36, height: 36).contentShape(Rectangle()) }
                .accessibilityLabel("Play actions").accessibilityIdentifier("playActions")
        }.padding(.vertical, 2)
    }
    /// When and where the play came from, on one line. An unknown date stays unknown.
    private func origin(_ play: EffectiveObservation) -> String {
        var parts: [String] = []
        if let played = play.values.playedAt, let date = played.date {
            let text = date.formatted(date: .abbreviated, time: .shortened)
            parts.append(played.origin == .manual ? String(localized: "\(text) (entered by hand)") : text)
        } else { parts.append(String(localized: "Date unknown")) }
        parts.append(model.sourceLabel(play))
        if play.original.source == .consultantSheet || play.original.source == .gameData {
            parts.append(String(localized: "imported \(play.original.firstSeenAt.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.joined(separator: " · ")
    }
    /// Judgment counts and the gauge, leaving out whatever was not recorded.
    private func counts(_ play: EffectiveObservation) -> String? {
        var parts: [String] = []
        if let judgments = play.values.judgments {
            for (name, value) in [("Pure", judgments.pure), ("Far", judgments.far), ("Lost", judgments.lost)] {
                if let value { parts.append("\(name) \(value.formatted())") }
            }
        }
        // The game's gauge numbers: 0 normal, 1 easy, 2 hard.
        let gauges = [String(localized: "Normal gauge"), String(localized: "Easy gauge"), String(localized: "Hard gauge")]
        let gauge = play.values.modifier.map { gauges.indices.contains($0) ? gauges[$0] : String(localized: "Gauge type \($0)") }
        switch (gauge, play.values.health) {
        case let (gauge?, health?): parts.append("\(gauge) \(health)%")
        case let (gauge?, nil): parts.append(gauge)
        case let (nil, health?): parts.append(String(localized: "Gauge \(health)%"))
        case (nil, nil): break
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
