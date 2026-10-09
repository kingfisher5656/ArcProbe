import Foundation

internal struct BestCorrection: Hashable, Codable, Sendable {
    let accountID: AccountID
    let chartID: ChartID
    let values: ScoreValues
    let baselineIDs: Set<ObservationID>
    var recordedAt: Date? = nil
}

internal enum ScoreReconciler {
    static func best(accountID: AccountID, observations: [EffectiveObservation], corrections: [BestCorrection] = []) -> [BestScore] {
        let groups = Dictionary(grouping: observations, by: { $0.original.chartID })
        let correctionMap = Dictionary(corrections.map { ($0.chartID, $0) }, uniquingKeysWith: { _, new in new })
        return Set(groups.keys).union(correctionMap.keys).sorted { $0.key < $1.key }.compactMap { chart in
            let correction = correctionMap[chart]
            let eligible = (groups[chart] ?? []).filter { !(correction?.baselineIDs.contains($0.original.id) ?? false) }
            let selected = eligible.sorted(by: preferred).first
            let lamps = eligible.flatMap { [$0.values.playClear, $0.values.bestClear].compactMap { $0 } }
                + [correction?.values.playClear, correction?.values.bestClear].compactMap { $0 }
            let lamp = lamps.max { $0.precedence < $1.precedence }
            if let correction, selected == nil || selected!.values.score <= correction.values.score {
                return BestScore(accountID: accountID, chartID: chart, observationID: nil, values: correction.values,
                                 bestClear: lamp, isOverridden: true, isBestCorrection: true)
            }
            guard let selected else { return nil }
            return BestScore(accountID: accountID, chartID: chart, observationID: selected.original.id,
                             values: selected.values, bestClear: lamp, isOverridden: selected.isOverridden,
                             isBestCorrection: false)
        }
    }
    private static func preferred(_ lhs: EffectiveObservation, _ rhs: EffectiveObservation) -> Bool {
        if lhs.values.score != rhs.values.score { return lhs.values.score > rhs.values.score }
        let leftTime = lhs.values.playedAt?.milliseconds ?? -1, rightTime = rhs.values.playedAt?.milliseconds ?? -1
        if leftTime != rightTime { return leftTime > rightTime }
        if lhs.original.firstSeenAt != rhs.original.firstSeenAt { return lhs.original.firstSeenAt > rhs.original.firstSeenAt }
        return lhs.original.id.rawValue < rhs.original.id.rawValue
    }
}
