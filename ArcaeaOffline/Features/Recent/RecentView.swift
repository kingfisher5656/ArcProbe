import ArcaeaCore
import SwiftUI

struct RecentView: View {
    @Environment(ArchiveModel.self) private var model
    @State private var recentOnly = true
    private var plays: [EffectiveObservation] { (recentOnly ? model.recentObservations : model.observations).sorted { ($0.values.playedAt?.date ?? $0.original.firstSeenAt) > ($1.values.playedAt?.date ?? $1.original.firstSeenAt) } }
    var body: some View {
        List {
            Section { TrackingStatusCard() }
            Section { Toggle("Only recent fetches", isOn: $recentOnly) }
            Section("\(plays.count) observed plays") {
                ForEach(plays, id: \.original.id) { play in
                    NavigationLink { ScoreDetailView(chart: play.original.chartID) } label: { VStack(alignment: .leading, spacing: 3) { ScoreRow(chart: play.original.chartID, values: play.values, override: play.isOverridden, showsPlayRating: true); Text(model.sourceLabel(play)).font(.caption2).foregroundStyle(.secondary) } }
                }
            }
            Section { Text("Recent plays include observed attempts below your personal best. Plays that disappear from the website before a fetch can be missed.").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Recent plays")
        .overlay { if plays.isEmpty { ContentUnavailableView("No recent plays saved", systemImage: "clock", description: Text(recentOnly ? "Configure the separate recent login in Settings, then fetch a play." : "Record a play in Scores or import your account.")) .allowsHitTesting(false).padding(.top, 160) } }
    }
}

struct TrackingStatusCard: View {
    @Environment(OnlineRuntime.self) private var runtime
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(runtime.trackingStatus?.isActive == true ? "Tracking signal active" : "Tracking inactive", systemImage: runtime.trackingStatus?.isActive == true ? "record.circle" : "pause.circle").font(.headline)
            if let status = runtime.trackingStatus {
                statusRow("Last attempt", status.lastAttemptAt)
                statusRow("Last successful fetch", status.lastSuccessAt)
                statusRow("Last new play", status.lastNewPlayAt)
                if let next = status.nextEligibleAt, next > Date() { statusRow("Next eligible request", next) }
            }
            Text("Continuous 70-second tracking needs validation on your iPad. Stopped or suspended loops may miss plays.").font(.footnote).foregroundStyle(.secondary)
        }.task { await runtime.refreshStatus() }
    }
    private func statusRow(_ label: String, _ date: Date?) -> some View { HStack { Text(label); Spacer(); Text(date?.formatted(date: .abbreviated, time: .shortened) ?? "Never").foregroundStyle(.secondary) }.font(.caption) }
}
