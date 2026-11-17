import ArcaeaCore
import Charts
import SwiftUI

struct PotentialView: View {
    @Environment(ArchiveModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    /// The preset that was last tapped; nil once the chart has been dragged or pinched away from it.
    @State private var range: HistoryRange? = .fiveYears
    @State private var viewport = PotentialViewport()
    @State private var selection: Date?
    /// Every point with a date, oldest first.
    @State private var points: [PotentialPoint] = []
    @State private var displayedOfficial: [PotentialPoint] = []
    @State private var displayedEstimate: [PotentialPoint] = []
    /// Where the view was when a pinch began.
    @State private var pinchStart: (position: Date, length: TimeInterval)?

    /// The estimate continues from the last official point, so the two lines meet.
    private var estimateLine: [PotentialPoint] {
        guard !displayedEstimate.isEmpty else { return [] }
        if let anchor = model.officialHistory.last, anchor.timestamp.date != nil { return [anchor] + displayedEstimate }
        return displayedEstimate
    }
    private func rebuild() {
        points = (model.officialHistory + model.localHistory).filter { $0.timestamp.date != nil }
            .sorted { ($0.timestamp.date ?? .distantPast) < ($1.timestamp.date ?? .distantPast) }
        displayedOfficial = HistorySampler.sample(points.filter { $0.series == .official }, value: { $0.value.doubleValue })
        displayedEstimate = HistorySampler.sample(points.filter { $0.series == .localEstimate }, value: { $0.value.doubleValue })
        viewport.load(points.compactMap { point in point.timestamp.date.map { .init(time: $0, value: point.value.doubleValue) } }, now: Date(), range: range)
        selection = nil
    }

    var body: some View {
        @Bindable var viewport = viewport
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PotentialHeader(viewport: viewport, points: points, selection: selection)
                HStack(spacing: 20) {
                    Label("Official", systemImage: "circle.fill").foregroundStyle(.purple)
                    Label("Local estimate", systemImage: "circle.fill").foregroundStyle(.orange)
                }.font(.caption)
                if points.isEmpty {
                    ContentUnavailableView {
                        Label("No potential history yet", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("Official history comes with a main-account import. After it, ArcProbe adds its own estimate for each play you save.")
                    } actions: {
                        Button("Import from Arcaea Online") { navigation.openSettings(.mainAccount) }.buttonStyle(.borderedProminent)
                    }.frame(height: 350)
                } else {
                    Picker("Date range", selection: Binding(get: { range }, set: { chosen in
                        range = chosen
                        if let chosen { withAnimation(.easeInOut(duration: 0.3)) { viewport.show(chosen) } }
                    })) {
                        ForEach(HistoryRange.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }.pickerStyle(.segmented)
                    chart(position: $viewport.position)
                    Text("Drag to move through time and pinch to zoom. Touch and hold to read a point.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let last = model.officialHistory.last {
                    Label("Official data through \(DisplayFormat.date(last.timestamp))", systemImage: "checkmark.shield")
                        .font(.subheadline).foregroundStyle(.purple)
                }
                Text(model.potentialSyncDate == nil
                     ? "Orange is ArcProbe’s own estimate. Import your main account in Settings to add official history."
                     : "Purple is official history up to your last import. Orange is ArcProbe’s estimate from plays saved since then.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 1250).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24)).padding(24)
        }.background(Color(.systemGroupedBackground)).navigationTitle("Potential history")
        .task { rebuild() }
        .onChange(of: model.revision) { rebuild() }
    }

    private func chart(position: Binding<Date>) -> some View {
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
            if let selection, let point = PotentialHeader.nearest(points, to: selection), let date = point.timestamp.date {
                RuleMark(x: .value("Selected", date)).foregroundStyle(.secondary.opacity(0.35)).lineStyle(StrokeStyle(dash: [4, 3]))
            }
        }
        .chartXScale(domain: viewport.domain)
        // An explicit value axis: the automatic one covers the whole history rather than what is on screen,
        // and with a single point it came out upside down.
        .chartYScale(domain: viewport.values)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: viewport.length)
        .chartScrollPosition(x: position)
        .chartXSelection(value: $selection)
        .simultaneousGesture(MagnifyGesture()
            .onChanged { pinch in
                let start = pinchStart ?? (viewport.position, viewport.length)
                pinchStart = start
                range = nil
                viewport.zoom(to: start.length / max(pinch.magnification, 0.01), around: pinch.startAnchor.x, from: start)
            }
            .onEnded { _ in pinchStart = nil })
        .frame(height: 390).padding(.vertical, 4)
        .accessibilityIdentifier("potential.chart")
    }
}

/// The value and date at the selection (or the newest point on screen), and what stretch of time is shown.
/// A view of its own so that scrolling redraws this and nothing else.
private struct PotentialHeader: View {
    let viewport: PotentialViewport
    let points: [PotentialPoint]
    let selection: Date?

    static func nearest(_ points: [PotentialPoint], to date: Date) -> PotentialPoint? {
        HistorySampler.nearest(points, reference: date.timeIntervalSince1970, key: { $0.timestamp.date?.timeIntervalSince1970 ?? 0 })
    }
    static func displayValue(_ point: PotentialPoint) -> String {
        if point.series == .localEstimate {
            // Match Best 50's truncation to three places while retaining extra precision in the plotted values.
            let milli = point.value.rawValue / 1_000
            return String(format: "%lld.%03lld", locale: Locale(identifier: "en_US_POSIX"), milli / 1_000, milli % 1_000)
        }
        return point.value.doubleValue.formatted(.number.precision(.fractionLength(point.value.decimalPlaces)))
    }
    var body: some View {
        let visible = points.filter { point in point.timestamp.date.map { $0 >= viewport.position && $0 <= viewport.end } ?? false }
        // The dates named are those that can hold a point: not before the first one, not after now.
        let from = max(viewport.position, viewport.dataRange.lowerBound), until = min(viewport.end, viewport.dataRange.upperBound)
        let shown = selection.flatMap { Self.nearest(points, to: $0) } ?? visible.last ?? points.last
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Potential").font(.title2.bold())
                if !points.isEmpty {
                    Text((from..<max(from, until)).formatted(date: .abbreviated, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(visible.count) saved points").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let shown {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(Self.displayValue(shown)).font(.largeTitle.weight(.semibold).monospacedDigit())
                    Text(DisplayFormat.date(shown.timestamp)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
