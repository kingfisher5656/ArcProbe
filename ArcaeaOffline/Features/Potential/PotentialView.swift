import ArcaeaCore
import Charts
import SwiftUI

enum HistoryRange: String, CaseIterable { case month = "30D", quarter = "90D", year = "1Y", fiveYears = "5Y", all = "All", custom = "Custom" }
struct PotentialView: View {
    @Environment(ArchiveModel.self) private var model
    private var history: [PotentialPoint] { model.officialHistory + model.localHistory }
    @State private var range = HistoryRange.fiveYears
    @State private var lower = 0.0
    @State private var upper = 1.0
    private var historyDates: [Date] { history.compactMap { $0.timestamp.date } }
    private func boundary(_ fraction: Double) -> Date {
        let first = historyDates.first ?? Date()
        return first.addingTimeInterval((historyDates.last ?? first).timeIntervalSince(first) * fraction)
    }
    @State private var selection: Date?
    @State private var points: [PotentialPoint] = []
    @State private var displayedOfficial: [PotentialPoint] = []
    @State private var displayedEstimate: [PotentialPoint] = []
    private var estimateLine: [PotentialPoint] {
        guard !displayedEstimate.isEmpty else { return [] }
        if let anchor = model.officialHistory.last, points.contains(anchor) { return [anchor] + displayedEstimate }
        return displayedEstimate
    }
    private var cutoff: Date? {
        let days: Int? = switch range { case .month: 30; case .quarter: 90; case .year: 365; case .fiveYears: nil; case .all, .custom: nil }
        if range == .fiveYears { return Calendar.current.date(byAdding: .year, value: -5, to: Date()) }
        return days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
    }
    private var selectedPoint: PotentialPoint? {
        guard let selection else { return points.last }
        return HistorySampler.nearest(points, reference: selection.timeIntervalSince1970, key: { $0.timestamp.date?.timeIntervalSince1970 ?? 0 })
    }
    private func displayValue(_ point: PotentialPoint) -> String {
        if point.series == .localEstimate {
            // Match Best 50's truncation to three places while retaining extra
            // precision in the plotted values.
            let milli = point.value.rawValue / 1_000
            return String(format: "%lld.%03lld", locale: Locale(identifier: "en_US_POSIX"), milli / 1_000, milli % 1_000)
        }
        return point.value.doubleValue.formatted(.number.precision(.fractionLength(point.value.decimalPlaces)))
    }
    private func syncPresetSliders() {
        guard range != .custom else { return }
        let first = historyDates.first ?? Date()
        let duration = (historyDates.last ?? first).timeIntervalSince(first)
        lower = duration > 0 ? min(1, max(0, (cutoff ?? first).timeIntervalSince(first) / duration)) : 0
        upper = 1
    }
    private func rebuildSeries() {
        let from = range == .custom ? boundary(lower) : cutoff
        let until = range == .custom ? boundary(upper) : nil
        points = history.filter { point in
            guard let date = point.timestamp.date else { return false }
            return (from.map { date >= $0 } ?? true) && (until.map { date <= $0 } ?? true)
        }
        displayedOfficial = HistorySampler.sample(points.filter { $0.series == .official }, value: { $0.value.doubleValue })
        displayedEstimate = HistorySampler.sample(points.filter { $0.series == .localEstimate }, value: { $0.value.doubleValue })
        selection = nil
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { VStack(alignment: .leading, spacing: 8) { Text("Potential").font(.title2.bold()); Text("\(points.count) saved points").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); if let point = selectedPoint { VStack(alignment: .trailing, spacing: 5) { Text(displayValue(point)).font(.largeTitle.weight(.semibold).monospacedDigit()); Text(DisplayFormat.date(point.timestamp)).font(.caption).foregroundStyle(.secondary) } } }
                HStack(spacing: 20) {
                    Label("Official", systemImage: "circle.fill").foregroundStyle(.purple)
                    Label("Local estimate", systemImage: "circle.fill").foregroundStyle(.orange)
                }.font(.caption)
                Picker("Date range", selection: $range) { ForEach(HistoryRange.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                VStack(spacing: 12) {
                    HStack { Text("From"); Spacer(); Text(boundary(lower).formatted(date: .abbreviated, time: .omitted)) }
                    Slider(value: Binding(get: { lower }, set: { lower = min($0, upper); range = .custom }), in: 0...1).accessibilityLabel("History range start")
                    HStack { Text("To"); Spacer(); Text(boundary(upper).formatted(date: .abbreviated, time: .omitted)) }
                    Slider(value: Binding(get: { upper }, set: { upper = max($0, lower); range = .custom }), in: 0...1).accessibilityLabel("History range end")
                }.font(.subheadline).disabled(historyDates.count < 2)

                if points.isEmpty { ContentUnavailableView("No history in this range", systemImage: "chart.xyaxis.line", description: Text("Import your main account’s official history in Settings, or choose another date range.")).frame(height: 350) }
                else {
                    Chart {
                        ForEach(displayedOfficial, id: \.sourceID) { point in
                            if let date = point.timestamp.date {
                                LineMark(x: .value("Date", date), y: .value("Potential", point.value.doubleValue), series: .value("Source", "Official")).foregroundStyle(.purple)
                                PointMark(x: .value("Date", date), y: .value("Potential", point.value.doubleValue)).foregroundStyle(.purple).symbolSize(20)
                            }
                        }
                        ForEach(estimateLine, id: \.sourceID) { point in
                            if let date = point.timestamp.date {
                                LineMark(x: .value("Date", date), y: .value("Potential", point.value.doubleValue), series: .value("Source", "Estimate")).foregroundStyle(.orange)
                            }
                        }
                        ForEach(displayedEstimate, id: \.sourceID) { point in
                            if let date = point.timestamp.date {
                                PointMark(x: .value("Date", date), y: .value("Potential", point.value.doubleValue)).foregroundStyle(.orange).symbolSize(25)
                            }
                        }
                        if let point = selectedPoint, let date = point.timestamp.date, selection != nil { RuleMark(x: .value("Selected", date)).foregroundStyle(.secondary.opacity(0.35)).lineStyle(StrokeStyle(dash: [4, 3])) }
                    }.chartXSelection(value: $selection).chartYScale(domain: .automatic(includesZero: false)).frame(height: 390).padding(.vertical)
                }
                if let last = model.officialHistory.last {
                    Label("Official data through \(DisplayFormat.date(last.timestamp))", systemImage: "checkmark.shield")
                        .font(.subheadline).foregroundStyle(.purple)
                }
                if let synced = model.potentialSyncDate {
                    Text("Orange continues from the last official value using changes in saved-score potential after the full sync on \(synced.formatted(date: .abbreviated, time: .shortened)). Later score and date edits recalculate only this estimate. Official history is never rewritten.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Run a full Arcaea Online import to establish the score baseline for the orange continuation. Existing official history stays unchanged; no older potential is reconstructed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("JSON backup preserves official history, the sync baseline, and later score changes.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 1250).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24)).padding(24)
        }.background(Color(.systemGroupedBackground)).navigationTitle("Potential history")
        .task { syncPresetSliders(); rebuildSeries() }
        .onChange(of: model.revision) { syncPresetSliders(); rebuildSeries() }
        .onChange(of: range) { syncPresetSliders(); rebuildSeries() }
        .onChange(of: lower) { rebuildSeries() }
        .onChange(of: upper) { rebuildSeries() }
    }
}
