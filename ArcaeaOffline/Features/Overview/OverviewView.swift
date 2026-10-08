import ArcaeaCore
import SwiftUI

struct OverviewView: View {
    @Environment(ArchiveModel.self) private var model
    @State private var export: ShareFile?
    private let columns = [GridItem(.adaptive(minimum: 240), spacing: 14)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                summary
                if let ranking = model.ranking, !ranking.rows.isEmpty {
                    HStack { Text("Your Best 50").font(.title2.bold()); Spacer(); Text("\(min(ranking.rows.count, 50)) saved chart\(ranking.rows.count == 1 ? "" : "s")").font(.subheadline).foregroundStyle(.secondary) }
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(ranking.rows.prefix(50)), id: \.best.chartID) { row in
                            NavigationLink { ScoreDetailView(chart: row.best.chartID) } label: { BestScoreCard(row: row) }.buttonStyle(.plain)
                        }
                    }
                    Text("Local estimates use the dated chart-constant snapshot. Unknown or outdated constants remain unrated.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Your archive starts here", systemImage: "music.note", description: Text("Import your account in Settings, or add a score offline in Scores."))
                        .frame(maxWidth: .infinity).padding(.vertical, 36)
                }
            }.padding(24).frame(maxWidth: 1450)
        }
        .background(Color(.systemGroupedBackground)).navigationTitle("ArcProbe")
        .toolbar {
            if !(model.ranking?.rows.isEmpty ?? true) {
                Menu {
                    Button("Share B50 JPG", systemImage: "photo") { model.perform { export = try ScoreExportService.jpg(model: model) } }
                    Button("Share B50 CSV", systemImage: "tablecells") { model.perform { export = try ScoreExportService.csv(model: model) } }
                } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Export Best 50")
            }
        }
        .sheet(item: $export) { ShareSheet(file: $0) }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Label("SAVED SCORE POTENTIAL", systemImage: "sparkles").font(.caption.weight(.semibold)).tracking(1); Spacer(); Text(model.selectedProfile?.displayName ?? model.selectedProfile?.id.rawValue ?? "Offline archive").font(.subheadline) }
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text(model.ranking.map { RatingCalculator.display($0.potentialUnits) } ?? "—").font(.system(size: 58, weight: .semibold, design: .rounded)).monospacedDigit()
                VStack(alignment: .leading, spacing: 5) { Text("Local estimate").font(.headline); Text("\(model.bestScores.count) chart best\(model.bestScores.count == 1 ? "" : "s") · \(model.observations.count) saved play\(model.observations.count == 1 ? "" : "s")").font(.subheadline).opacity(0.8) }
            }
            Divider().overlay(.white.opacity(0.15))
            HStack { Text("Latest official potential"); Spacer(); Text(model.officialHistory.last.map { $0.value.doubleValue.formatted(.number.precision(.fractionLength(3))) } ?? "Not imported").fontWeight(.semibold).monospacedDigit() }.font(.subheadline)
            if let latest = model.officialHistory.last { Text("Observed \(DisplayFormat.date(latest.timestamp))").font(.caption).opacity(0.8) }
        }.padding(24).foregroundStyle(.white)
            .background(LinearGradient(colors: [Color(red: 0.37, green: 0.25, blue: 0.54), Color(red: 0.18, green: 0.17, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct BestScoreCard: View {
    @Environment(ArchiveModel.self) private var model
    let row: RankedScore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverArtwork(chart: row.best.chartID).aspectRatio(1.2, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    Text(row.rank.map { "#\($0)" } ?? "Unrated").font(.headline).padding(9).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(10)
                }
                .overlay(alignment: .bottomTrailing) {
                    ChartBadge(chart: row.best.chartID, level: model.catalog[row.best.chartID]?.level).background(.regularMaterial, in: Capsule()).padding(10)
                }
            VStack(alignment: .leading, spacing: 10) {
                Text(model.title(row.best.chartID)).font(.headline).lineLimit(2)
                if let artist = model.artist(row.best.chartID) { Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                HStack { Text(DisplayFormat.score(row.best.values.score)).font(.title3.weight(.semibold).monospacedDigit()); Spacer(); Text(DisplayFormat.grade(row.best.values.score)).font(.subheadline.bold()).foregroundStyle(.purple) }
                HStack(alignment: .bottom) {
                    Text(DisplayFormat.clear(row.best.bestClear)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("PLAY RATING").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        Text(row.ratingUnits.map { RatingCalculator.display($0) } ?? "Unrated")
                            .font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
                            .foregroundStyle(.purple).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                if row.best.isOverridden || row.best.isBestCorrection { Label("Manual correction", systemImage: "pencil").font(.caption).foregroundStyle(.orange) }
            }.padding(16)
        }.background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
