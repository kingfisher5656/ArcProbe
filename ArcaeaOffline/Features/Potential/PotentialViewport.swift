import Foundation
import Observation
import SwiftUI

enum HistoryRange: CaseIterable, Hashable {
    case month, quarter, year, fiveYears, all
    var title: LocalizedStringKey {
        switch self { case .month: "30D"; case .quarter: "90D"; case .year: "1Y"; case .fiveYears: "5Y"; case .all: "All" }
    }
    /// How far back from now the range reaches; nil is everything saved.
    var length: TimeInterval? {
        switch self { case .month: 30 * 86_400; case .quarter: 90 * 86_400; case .year: 365 * 86_400; case .fiveYears: 5 * 365 * 86_400; case .all: nil }
    }
}

/// The stretch of the potential history that is on screen.
///
/// The chart scrolls and zooms by changing `position` and `length`. They live here rather than in the view's
/// own state so that scrolling, which writes `position` on every frame, redraws only the header that reads it
/// and not the chart with all its points.
@MainActor @Observable final class PotentialViewport {
    struct Sample: Equatable { let time: Date; let value: Double }

    /// Leading edge of the visible stretch. The chart writes it while it scrolls.
    var position = Date() { didSet { if position != oldValue { settle() } } }
    /// Seconds of history on screen.
    var length: TimeInterval = 86_400 { didSet { if length != oldValue { settle() } } }
    /// From the first point to now (or to the last point, should it lie in the future); never shorter than a day.
    private(set) var dataRange = Date().addingTimeInterval(-86_400)...Date()
    /// The value axis, fitted to the points on screen.
    private(set) var values = 0.0...1.0
    @ObservationIgnored private var samples: [Sample] = []
    @ObservationIgnored private var settling: Task<Void, Never>?

    var end: Date { position.addingTimeInterval(length) }
    /// Everything that can be scrolled to: the data, plus a little room at both ends so the first and last points
    /// are not drawn on the edge. The room is a share of what is on screen, so it looks the same at every zoom.
    var domain: ClosedRange<Date> {
        dataRange.lowerBound.addingTimeInterval(-length * Self.margin)...dataRange.upperBound.addingTimeInterval(length * Self.margin)
    }
    private var dataSpan: TimeInterval { dataRange.upperBound.timeIntervalSince(dataRange.lowerBound) }
    /// The widest view: all the data with the room at both ends.
    private var longest: TimeInterval { dataSpan / (1 - 2 * Self.margin) }

    /// Share of the screen kept free beyond the first and the last point.
    static let margin = 0.03
    /// The closest zoom: one day across the screen.
    static let shortest: TimeInterval = 86_400

    /// New data. With a preset chosen the view moves to it again (so a new point comes into view);
    /// after a pinch or drag (`range` is nil) it stays where the user left it.
    func load(_ samples: [Sample], now: Date, range: HistoryRange?) {
        self.samples = samples.sorted { $0.time < $1.time }
        dataRange = Self.dataRange(first: self.samples.first?.time, last: self.samples.last?.time, now: now)
        if let range { show(range) } else { zoom(to: length, around: 0.5) }
        settling?.cancel()
        values = Self.valueDomain(visibleValues())
    }

    /// The last `range` of history, ending now.
    func show(_ range: HistoryRange) {
        let span = min(range.length ?? dataSpan, dataSpan)
        length = span / (1 - 2 * Self.margin)
        position = dataRange.upperBound.addingTimeInterval(length * Self.margin - length)
    }

    /// Changes how much is on screen, keeping the moment under `anchor` (0 leading … 1 trailing) where it is.
    func zoom(to newLength: TimeInterval, around anchor: Double, from start: (position: Date, length: TimeInterval)? = nil) {
        let start = start ?? (position, length)
        let clamped = min(max(newLength, min(Self.shortest, longest)), longest)
        let fixed = start.position.addingTimeInterval(start.length * anchor)
        let wanted = fixed.addingTimeInterval(-clamped * anchor)
        length = clamped
        position = min(max(wanted, domain.lowerBound), domain.upperBound.addingTimeInterval(-clamped))
    }

    static func dataRange(first: Date?, last: Date?, now: Date) -> ClosedRange<Date> {
        let end = max(last ?? now, now)
        return min(first ?? end, end.addingTimeInterval(-shortest))...end
    }

    /// An axis around the given values. A single value, or equal values, still get a span the right way up.
    static func valueDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let margin = max((high - low) * 0.15, 0.05)
        return ((low - margin) * 100).rounded(.down) / 100...((high + margin) * 100).rounded(.up) / 100
    }

    /// Values on screen, with the nearest point on each side so a line that crosses the screen stays inside the axis.
    /// With nothing in reach, the whole history decides.
    private func visibleValues() -> [Double] {
        let from = position, until = end
        var result = samples.filter { $0.time >= from && $0.time <= until }.map(\.value)
        if let before = samples.last(where: { $0.time < from }) { result.append(before.value) }
        if let after = samples.first(where: { $0.time > until }) { result.append(after.value) }
        return result
    }

    /// Refits the value axis shortly after scrolling or zooming pauses, instead of on every frame.
    private func settle() {
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled, let self else { return }
            let fitted = Self.valueDomain(self.visibleValues())
            if fitted != self.values { withAnimation(.easeOut(duration: 0.25)) { self.values = fitted } }
        }
    }
}
