import ArcaeaCore
import Charts
import SwiftUI

enum HistoryRange: String, CaseIterable { case month = "30D", quarter = "90D", year = "1Y", fiveYears = "5Y", all = "All", custom = "Custom" }
struct PotentialView: View {
    @Environment(ArchiveModel.self) private var model
    @State private var range = HistoryRange.fiveYears
    @State private var lower = 0.0
    @State private var upper = 1.0
    private var historyDates: [Date] { model.officialHistory.compactMap { $0.timestamp.date } }
    private func boundary(_ fraction: Double) -> Date {
        let first = historyDates.first ?? Date()
        return first.addingTimeInterval((historyDates.last ?? first).timeIntervalSince(first) * fraction)
    }
    @State private var selection: Date?
    @State private var points: [PotentialPoint] = []
    @State private var displayedPoints: [PotentialPoint] = []
    private var cutoff: Date? {
        let days: Int? = switch range { case .month: 30; case .quarter: 90; case .year: 365; case .fiveYears: nil; case .all, .custom: nil }
        if range == .fiveYears { return Calendar.current.date(byAdding: .year, value: -5, to: Date()) }
        return days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
    }
    private var selectedPoint: PotentialPoint? {
        guard let selection else { return points.last }
        return HistorySampler.nearest(points, reference: selection.timeIntervalSince1970, key: { $0.timestamp.date?.timeIntervalSince1970 ?? 0 })
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
        points = model.officialHistory.filter { point in
            guard let date = point.timestamp.date else { return false }
            return (from.map { date >= $0 } ?? true) && (until.map { date <= $0 } ?? true)
        }
        displayedPoints = HistorySampler.sample(points, value: { $0.value.doubleValue })
        selection = nil
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack { VStack(alignment: .leading, spacing: 8) { Text("Official potential").font(.title2.bold()); Text("\(points.count) returned observations").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); if let point = selectedPoint { VStack(alignment: .trailing, spacing: 5) { Text(point.value.doubleValue.formatted(.number.precision(.fractionLength(point.value.decimalPlaces)))).font(.largeTitle.weight(.semibold).monospacedDigit()); Text(DisplayFormat.date(point.timestamp)).font(.caption).foregroundStyle(.secondary) } } }
                Picker("Date range", selection: $range) { ForEach(HistoryRange.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                VStack(spacing: 12) {
                    HStack { Text("From"); Spacer(); Text(boundary(lower).formatted(date: .abbreviated, time: .omitted)) }
                    Slider(value: Binding(get: { lower }, set: { lower = min($0, upper); range = .custom }), in: 0...1).accessibilityLabel("History range start")
                    HStack { Text("To"); Spacer(); Text(boundary(upper).formatted(date: .abbreviated, time: .omitted)) }
                    Slider(value: Binding(get: { upper }, set: { upper = max($0, lower); range = .custom }), in: 0...1).accessibilityLabel("History range end")
                }.font(.subheadline).disabled(historyDates.count < 2)

                if points.isEmpty { ContentUnavailableView("No official history in this range", systemImage: "chart.xyaxis.line", description: Text("Import your main account’s potential history in Settings, or choose another date range.")).frame(height: 350) }
                else {
                    Chart {
                        ForEach(displayedPoints, id: \.sourceID) { point in if let date = point.timestamp.date { LineMark(x: .value("Date", date), y: .value("Official potential", point.value.doubleValue)).foregroundStyle(.purple); PointMark(x: .value("Date", date), y: .value("Official potential", point.value.doubleValue)).foregroundStyle(.purple).symbolSize(20) } }
                        if let point = selectedPoint, let date = point.timestamp.date, selection != nil { RuleMark(x: .value("Selected", date)).foregroundStyle(.secondary.opacity(0.35)).lineStyle(StrokeStyle(dash: [4, 3])) }
                    }.chartXSelection(value: $selection).chartYScale(domain: .automatic(includesZero: false)).frame(height: 390).padding(.vertical)
                }
                Label("Official history is preserved separately from local score estimates.", systemImage: "checkmark.shield").font(.subheadline).foregroundStyle(.secondary)
                Text("Large histories use a display sample that preserves high and low points. Touch inspection still uses every saved observation. Only observations returned by the website are saved. Missing days stay missing; manual score edits do not change this graph.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 1250).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24)).padding(24)
        }.background(Color(.systemGroupedBackground)).navigationTitle("Potential history")
        .task { syncPresetSliders(); rebuildSeries() }
        .onChange(of: model.revision) { syncPresetSliders(); rebuildSeries() }
        .onChange(of: range) { syncPresetSliders(); rebuildSeries() }
        .onChange(of: lower) { rebuildSeries() }
        .onChange(of: upper) { rebuildSeries() }
    }
}
