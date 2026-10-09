import Foundation

/// A real full-sync snapshot, never reconstructed from the current best scores.
public struct PotentialBaseline: Hashable, Codable, Sendable {
    public let accountID: AccountID
    public let anchor: PotentialPoint
    public let syncedAt: Date
    public let scores: [BestScore]

    internal func validate() throws {
        try ArchiveValidation.account(accountID)
        try ArchiveValidation.potential(anchor)
        try ArchiveValidation.date(syncedAt)
        guard anchor.accountID == accountID, anchor.series == .official,
              let date = anchor.timestamp.date, date <= syncedAt,
              scores.count <= 10_000, Set(scores.map(\.chartID)).count == scores.count else {
            throw ArchiveError.invalidRecord("Invalid potential baseline")
        }
        for score in scores {
            guard score.accountID == accountID else { throw ArchiveError.accountMismatch }
            try ArchiveValidation.chartID(score.chartID)
            try ArchiveValidation.values(score.values)
        }
    }
}

extension ArchiveStore {
    public func potentialBaseline(accountID: AccountID) throws -> PotentialBaseline? {
        try locked { try record("SELECT payload FROM potential_baselines WHERE account_id=?", [.text(accountID.rawValue)]) }
    }
    internal func putPotentialBaseline(_ baseline: PotentialBaseline) throws {
        try baseline.validate()
        try database.execute("INSERT OR REPLACE INTO potential_baselines(account_id,payload) VALUES(?,?)",
            [.text(baseline.accountID.rawValue), .blob(try encoder.encode(baseline))])
    }
    internal func capturePotentialBaseline(_ batch: ImportBatch) throws {
        guard batch.kind == .full,
              let anchor = batch.potentialPoints.filter({ $0.series == .official }).max(by: {
                  ($0.timestamp.milliseconds ?? 0) < ($1.timestamp.milliseconds ?? 0)
              }), let anchorDate = anchor.timestamp.date, anchorDate <= batch.importedAt else { return }
        if let previous = try potentialBaseline(accountID: batch.profile.id),
           previous.syncedAt > batch.importedAt || previous.anchor.timestamp.milliseconds! > anchor.timestamp.milliseconds! { return }
        let canonical: PotentialPoint = try record("SELECT payload FROM potential_points WHERE account_id=? AND series=? AND source_id=?",
            [.text(batch.profile.id.rawValue), .text(PotentialSeries.official.rawValue), .text(anchor.sourceID)]) ?? anchor
        let raw = batch.observations.map { EffectiveObservation(original: $0, values: $0.values, isOverridden: false) }
        try putPotentialBaseline(PotentialBaseline(accountID: batch.profile.id, anchor: canonical,
            syncedAt: batch.importedAt, scores: ScoreReconciler.best(accountID: batch.profile.id, observations: raw)))
    }

    /// Only post-sync estimates. Official observations are never recalculated or edited.
    public func localPotentialHistory(accountID: AccountID) throws -> [PotentialPoint] {
        try locked {
            try database.transaction(write: false) {
                guard let baseline = try potentialBaseline(accountID: accountID) else { return [] }
                guard let latest = try potentialHistory(accountID: accountID).last,
                      latest.timestamp.milliseconds == baseline.anchor.timestamp.milliseconds,
                      latest.value.equivalent(to: baseline.anchor.value) else { return [] }
                let observations = try effectiveUnlocked(accountID: accountID, includeSuppressed: false)
                let corrections: [BestCorrection] = try records("SELECT payload FROM best_corrections WHERE account_id=?", [.text(accountID.rawValue)])
                return try PotentialContinuation.build(baseline: baseline, observations: observations,
                    corrections: corrections, catalog: catalogUnlocked())
            }
        }
    }
}

private enum PotentialContinuation {
    struct Event {
        let chart: ChartID
        let values: ScoreValues
        let date: Date
        let correction: Bool
    }
    static func build(baseline: PotentialBaseline, observations: [EffectiveObservation],
                      corrections: [BestCorrection], catalog: ChartCatalog) throws -> [PotentialPoint] {
        func normalized(_ date: Date) -> Date {
            Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded(.up) / 1000)
        }
        let activeCorrections = corrections.filter {
            ($0.values.playedAt?.date ?? $0.recordedAt ?? .distantPast) > baseline.syncedAt
        }
        let excluded = Set(activeCorrections.flatMap(\.baselineIDs))
        var events = observations.filter { !excluded.contains($0.original.id) }.compactMap { play -> Event? in
            let date = play.values.playedAt?.date ?? play.original.firstSeenAt
            guard date > baseline.syncedAt else { return nil }
            return Event(chart: play.original.chartID, values: play.values, date: normalized(date), correction: false)
        }
        events += activeCorrections.map {
            Event(chart: $0.chartID, values: $0.values, date: normalized($0.values.playedAt?.date ?? $0.recordedAt!), correction: true)
        }
        events.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            // Apply explicit corrections before new eligible attempts at the same instant.
            return $0.correction && !$1.correction
        }
        let calculator = RatingCalculator(catalog: catalog)
        let initial = try calculator.rank(bestScores: baseline.scores).potentialUnits
        var best = Dictionary(uniqueKeysWithValues: baseline.scores.map { ($0.chartID, $0) })
        var lastUnits = initial
        var points: [PotentialPoint] = []
        var index = 0
        let anchorMicro = Int64((baseline.anchor.value.doubleValue * 1_000_000).rounded())
        while index < events.count {
            let date = events[index].date
            repeat {
                let event = events[index]
                let previous = event.correction ? nil : best[event.chart]
                let clear = [previous?.bestClear, event.values.bestClear, event.values.playClear]
                    .compactMap { $0 }.max { $0.precedence < $1.precedence }
                let values = (previous?.values.score ?? -1) > event.values.score ? previous!.values : event.values
                best[event.chart] = BestScore(accountID: baseline.accountID, chartID: event.chart, observationID: nil,
                    values: values, bestClear: clear, isOverridden: false, isBestCorrection: event.correction)
                index += 1
            } while index < events.count && events[index].date == date
            let units = try calculator.rank(bestScores: Array(best.values)).potentialUnits
            guard units != lastUnits else { continue }
            lastUnits = units
            let millis = Int64((date.timeIntervalSince1970 * 1000).rounded())
            let timestamp = SourceTimestamp(value: millis, unit: .milliseconds)
            // Carry changes from the real official value, not the absolute B50 estimate.
            let micro = min(30_000_000, max(0, anchorMicro + (units - initial) * 5 / 3))
            points.append(PotentialPoint(accountID: baseline.accountID, sourceID: "continuation:\(millis)",
                timestamp: timestamp, value: PotentialValue(rawValue: micro, decimalPlaces: 6),
                series: .localEstimate, firstSeenAt: date))
        }
        return points
    }
}
