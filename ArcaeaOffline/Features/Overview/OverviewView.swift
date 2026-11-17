import ArcaeaCore
import SwiftUI

struct OverviewView: View {
    @Environment(ArchiveModel.self) private var model
    @State private var export: ShareFile?
    @State private var exportingJPG = false
    @State private var editor: ScoreEditorDestination?
    @State private var width: CGFloat = 0
    /// Four cards across on an iPad held upright and five on its side; fewer in a narrow window or on a phone.
    private var columnCount: Int { width >= 1100 ? 5 : width >= 700 ? 4 : width >= 480 ? 3 : 2 }
    /// Card text is sized for the five-across landscape card of this device. A narrower card (four across in
    /// portrait, a split window) shrinks its text by the same ratio, so every layout has the same proportions.
    private var cardScale: CGFloat {
        func cardWidth(_ available: CGFloat, columns: CGFloat) -> CGFloat { (min(available, 1450) - 40 - 14 * (columns - 1)) / columns }
        let screen = UIScreen.main.bounds
        let reference = cardWidth(max(screen.width, screen.height), columns: 5)
        guard width > 0, reference > 0 else { return 1 }
        return min(1, max(0.6, cardWidth(width, columns: CGFloat(columnCount)) / reference))
    }
    var body: some View {
        ScrollView {
            Group {
                if let ranking = model.ranking, !ranking.rows.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        summary(ranking)
                        // A plain Grid rather than a lazy one: it can make every card in a row as tall as the tallest,
                        // which a two-line title would otherwise leave ragged. Fifty cards is few enough.
                        let top = Array(ranking.rows.prefix(50)), count = columnCount, scale = cardScale
                        Grid(alignment: .top, horizontalSpacing: 14, verticalSpacing: 14) {
                            ForEach(Array(stride(from: 0, to: top.count, by: count)), id: \.self) { start in
                                GridRow {
                                    ForEach(start..<start + count, id: \.self) { index in
                                        if index < top.count {
                                            NavigationLink { ScoreDetailView(chart: top[index].best.chartID) } label: { BestScoreCard(row: top[index], scale: scale) }.buttonStyle(.plain)
                                        } else {
                                            // Keeps the columns of a short last row the same width as the rows above.
                                            Color.clear.gridCellUnsizedAxes(.vertical)
                                        }
                                    }
                                }
                            }
                        }
                        Text("Ratings are estimates from the saved chart constants. Charts without a known constant are unrated.").font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    EmptyArchiveView(title: "Your archive starts here", systemImage: "music.note") { editor = .add }
                        .padding(.vertical, 80)
                }
            }.padding(20).frame(maxWidth: 1450).frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .background(Color(.systemGroupedBackground)).navigationTitle("ArcProbe")
        .toolbar {
            if !(model.ranking?.rows.isEmpty ?? true) {
                Menu {
                    Button(exportingJPG ? "Preparing B50 JPG…" : "Share B50 JPG", systemImage: "photo") {
                        exportingJPG = true
                        Task { @MainActor in
                            defer { exportingJPG = false }
                            do { export = try await ScoreExportService.jpg(model: model) }
                            catch { model.errorMessage = error.localizedDescription }
                        }
                    }.disabled(exportingJPG)
                    Button("Share B50 CSV", systemImage: "tablecells") { model.perform { export = try ScoreExportService.csv(model: model) } }
                } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Export Best 50")
            }
        }
        .sheet(item: $export) { ShareSheet(file: $0) }
        .sheet(item: $editor) { ScoreEditorView(destination: $0) }
    }
    /// One line: the estimate ArcProbe works out, and the last official value beside it.
    private func summary(_ ranking: RankingSnapshot) -> some View {
        let count = model.bestScores.count
        let details = [model.selectedProfile?.displayName, String(localized: "\(count) chart bests")].compactMap { $0 }
        let official = model.officialHistory.last
        return HStack(spacing: 16) {
            Text(RatingCalculator.display(ranking.potentialUnits)).font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text("Estimated potential").font(.headline)
                Text(details.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Official").font(.subheadline).foregroundStyle(.secondary)
                if let official {
                    Text(official.value.doubleValue.formatted(.number.precision(.fractionLength(official.value.decimalPlaces)))).font(.headline.monospacedDigit())
                    Text(DisplayFormat.date(official.timestamp)).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Not imported").font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct BestScoreCard: View {
    @Environment(ArchiveModel.self) private var model
    let row: RankedScore
    /// 1 on the reference (landscape) card; smaller on a narrower card.
    let scale: CGFloat
    /// Follows the text size chosen in iOS Settings, which fixed point sizes would otherwise ignore.
    @ScaledMetric(relativeTo: .body) private var dynamicType: CGFloat = 1
    private func font(_ size: CGFloat, _ weight: Font.Weight = .regular, _ design: Font.Design = .default) -> Font {
        .system(size: size * scale * dynamicType, weight: weight, design: design)
    }
    var body: some View {
        let chart = row.best.chartID
        VStack(alignment: .leading, spacing: 0) {
            CoverArtwork(chart: chart).aspectRatio(1.2, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    Text(row.rank.map { "#\($0)" } ?? String(localized: "Unrated")).font(font(17, .semibold)).padding(9 * scale)
                        .background(Color(.secondarySystemGroupedBackground).opacity(0.95), in: RoundedRectangle(cornerRadius: 10 * scale)).padding(10 * scale)
                }
                .overlay(alignment: .bottomTrailing) {
                    ChartBadge(chart: chart, level: model.catalog[chart]?.level).background(Color(.secondarySystemGroupedBackground).opacity(0.95), in: Capsule())
                        .scaleEffect(scale, anchor: .bottomTrailing).padding(10 * scale)
                }
            VStack(alignment: .leading, spacing: 10 * scale) {
                Text(model.title(chart)).font(font(17, .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                if let artist = model.artist(chart) { Text(artist).font(font(12)).foregroundStyle(.secondary).lineLimit(1) }
                HStack(spacing: 0) {
                    Text(DisplayFormat.score(row.best.values.score)).font(font(20, .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(DisplayFormat.grade(row.best.values.score)).font(font(15, .bold))
                }
                HStack(alignment: .bottom, spacing: 0) {
                    ClearLamp(clear: row.best.bestClear, scale: scale * dynamicType)
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2 * scale) {
                        Text("PLAY RATING").font(font(11, .semibold)).foregroundStyle(.secondary)
                        Text(row.ratingUnits.map { RatingCalculator.display($0) } ?? String(localized: "Unrated"))
                            .font(font(22, .bold, .rounded)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                if row.best.isOverridden || row.best.isBestCorrection { Label("Manual correction", systemImage: "pencil").font(font(12)).foregroundStyle(.orange) }
            }.padding(16 * scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 18 * scale))
        .accessibilityElement(children: .combine)
    }
}
