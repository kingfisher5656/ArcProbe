import ArcaeaCore
import SwiftUI

struct RecentView: View {
    @Environment(ArchiveModel.self) private var model
    @State private var recentOnly = true
    private var plays: [EffectiveObservation] { (recentOnly ? model.recentObservations : model.observations).sorted { ($0.values.playedAt?.date ?? $0.original.firstSeenAt) > ($1.values.playedAt?.date ?? $1.original.firstSeenAt) } }
    var body: some View {
        List {
            Section { TrackingStatusCard() }
            Section {
                Picker("Show", selection: $recentOnly) { Text("Tracked plays").tag(true); Text("All saved plays").tag(false) }.pickerStyle(.segmented)
            }
            Section("\(plays.count) play\(plays.count == 1 ? "" : "s")") {
                ForEach(plays, id: \.original.id) { play in
                    NavigationLink { ScoreDetailView(chart: play.original.chartID) } label: { VStack(alignment: .leading, spacing: 3) { ScoreRow(chart: play.original.chartID, values: play.values, override: play.isOverridden, showsPlayRating: true); Text(model.sourceLabel(play)).font(.caption2).foregroundStyle(.secondary) } }
                }
            }
        }
        .navigationTitle("Recent plays")
        .overlay { if plays.isEmpty { ContentUnavailableView("No plays yet", systemImage: "clock", description: Text(recentOnly ? "Set up the tracker account and the Shortcut in Settings. Plays appear here as you finish them." : "Add a score in Scores or import your account in Settings.")) .allowsHitTesting(false).padding(.top, 160) } }
    }
}
