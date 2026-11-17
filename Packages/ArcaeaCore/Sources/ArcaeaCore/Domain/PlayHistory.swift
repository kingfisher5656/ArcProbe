import Foundation

/// How a play compares with the best saved play of the same chart before it.
public enum PlayChange: Hashable, Sendable {
    /// No earlier play of this chart is saved.
    case first
    /// Beat the earlier best by this many points.
    case newBest(by: Int)
    /// Equal to the earlier best.
    case tie
    /// Short of the earlier best by this many points.
    case below(by: Int)

    public var isNewBest: Bool { if case .newBest = self { true } else { false } }
}

public enum PlayHistory {
    /// The change each play made, keyed by observation.
    ///
    /// A play gets no entry when the order of plays cannot be known, because a wrong "new best" is worse than none:
    /// - its own date is unknown, or
    /// - another saved play of the chart has no date and was first seen after this play was made
    ///   (it may have been played before or after).
    ///
    /// A play without a date that was first seen at or before this play's date did happen earlier, so it counts.
    public static func changes(_ plays: [EffectiveObservation]) -> [ObservationID: PlayChange] {
        var result: [ObservationID: PlayChange] = [:]
        for chartPlays in Dictionary(grouping: plays, by: \.original.chartID).values {
            var dated: [(date: Date, play: EffectiveObservation)] = []
            var undated: [(seen: Date, score: Int)] = []
            for play in chartPlays {
                if let date = play.values.playedAt?.date { dated.append((date, play)) }
                else { undated.append((play.original.firstSeenAt, play.values.score)) }
            }
            dated.sort {
                ($0.date, $0.play.original.firstSeenAt, $0.play.original.id.rawValue) < ($1.date, $1.play.original.firstSeenAt, $1.play.original.id.rawValue)
            }
            var bestBefore: Int?
            for (date, play) in dated {
                defer { bestBefore = max(bestBefore ?? play.values.score, play.values.score) }
                guard !undated.contains(where: { $0.seen > date }) else { continue }
                let earlier = ([bestBefore] + undated.map { Optional($0.score) }).compactMap { $0 }.max()
                guard let earlier else { result[play.original.id] = .first; continue }
                let difference = play.values.score - earlier
                result[play.original.id] = difference > 0 ? .newBest(by: difference) : difference == 0 ? .tie : .below(by: -difference)
            }
        }
        return result
    }
}
