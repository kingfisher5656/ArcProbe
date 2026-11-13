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

    /// Official continuation, or a local series starting at the first sheet import. Never reconstructs older plays.
    public func localPotentialHistory(accountID: AccountID) throws -> [PotentialPoint] {
        try locked {
            try database.transaction(write: false) {
                let observations = try effectiveUnlocked(accountID: accountID, includeSuppressed: false)
                let corrections: [BestCorrection] = try records("SELECT payload FROM best_corrections WHERE account_id=?", [.text(accountID.rawValue)])
                guard let baseline = try potentialBaseline(accountID: accountID) else {
                    guard try potentialHistory(accountID: accountID).isEmpty else { return [] }
                    return try PotentialContinuation.withoutOfficialHistory(accountID: accountID, observations: observations,
                        corrections: corrections, catalog: catalogUnlocked())
                }
                guard let latest = try potentialHistory(accountID: accountID).last,
                      latest.timestamp.milliseconds == baseline.anchor.timestamp.milliseconds,
                      latest.value.equivalent(to: baseline.anchor.value) else { return [] }
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
    static func withoutOfficialHistory(accountID: AccountID, observations: [EffectiveObservation],
                                       corrections: [BestCorrection], catalog: ChartCatalog) throws -> [PotentialPoint] {
        guard let start = observations.filter({ $0.original.source == .consultantSheet }).map({ $0.original.firstSeenAt }).min() else { return [] }
        // Seed from records already known at the first import, never backfill their old play dates.
        let earlier = observations.filter { $0.original.firstSeenAt < start }
        let earlierCorrections = corrections.filter { ($0.recordedAt ?? .distantPast) < start }
        let scores = ScoreReconciler.best(accountID: accountID, observations: earlier, corrections: earlierCorrections)
        let units = try RatingCalculator(catalog: catalog).rank(bestScores: scores).potentialUnits
        let cutoff = Date(timeIntervalSince1970: floor(start.timeIntervalSince1970 * 1000) / 1000 - 0.001)
        return try timeline(accountID: accountID, cutoff: cutoff, initialScores: scores,
            anchorValue: PotentialValue(rawValue: units * 5 / 3, decimalPlaces: 6),
            observations: observations.filter { $0.original.firstSeenAt >= start },
            corrections: corrections.filter { ($0.recordedAt ?? .distantPast) >= start }, catalog: catalog,
            useRecordedDates: true, includeFirstPoint: true)
    }
    static func build(baseline: PotentialBaseline, observations: [EffectiveObservation],
                      corrections: [BestCorrection], catalog: ChartCatalog) throws -> [PotentialPoint] {
        try timeline(accountID: baseline.accountID, cutoff: baseline.syncedAt, initialScores: baseline.scores,
            anchorValue: baseline.anchor.value, observations: observations, corrections: corrections, catalog: catalog)
    }
    private static func timeline(accountID: AccountID, cutoff: Date, initialScores: [BestScore],
                                 anchorValue: PotentialValue, observations: [EffectiveObservation],
                                 corrections: [BestCorrection], catalog: ChartCatalog,
                                 useRecordedDates: Bool = false, includeFirstPoint: Bool = false) throws -> [PotentialPoint] {
        func normalized(_ date: Date) -> Date {
            Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded(.up) / 1000)
        }
        let activeCorrections = corrections.filter {
            (useRecordedDates ? $0.recordedAt ?? .distantPast : $0.values.playedAt?.date ?? $0.recordedAt ?? .distantPast) > cutoff
        }
        func correctionDate(_ correction: BestCorrection) -> Date {
            useRecordedDates ? correction.recordedAt! : correction.values.playedAt?.date ?? correction.recordedAt!
        }
        var supersededAt: [ObservationID: Date] = [:]
        for correction in activeCorrections {
            for id in correction.baselineIDs { supersededAt[id] = correctionDate(correction) }
        }
        var events = observations.compactMap { play -> Event? in
            // Sheet import time is known even when the actual achievement date is not.
            let date = useRecordedDates || play.original.source == .consultantSheet
                ? play.original.firstSeenAt : play.values.playedAt?.date ?? play.original.firstSeenAt
            guard date > cutoff else { return nil }
            // Keep the chart's history before its correction; never replay the superseded attempt afterward.
            if let correction = supersededAt[play.original.id], normalized(date) >= normalized(correction) { return nil }
            return Event(chart: play.original.chartID, values: play.values, date: normalized(date), correction: false)
        }
        events += activeCorrections.map {
            Event(chart: $0.chartID, values: $0.values, date: normalized(correctionDate($0)), correction: true)
        }
        events.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            // Apply explicit corrections before new eligible attempts at the same instant.
            return $0.correction && !$1.correction
        }
        let calculator = RatingCalculator(catalog: catalog)
        let initial = try calculator.rank(bestScores: initialScores).potentialUnits
        var best = Dictionary(uniqueKeysWithValues: initialScores.map { ($0.chartID, $0) })
        var lastUnits = initial
        var points: [PotentialPoint] = []
        var index = 0
        let anchorMicro = Int64((anchorValue.doubleValue * 1_000_000).rounded())
        while index < events.count {
            let date = events[index].date
            repeat {
                let event = events[index]
                let previous = event.correction ? nil : best[event.chart]
                let clear = [previous?.bestClear, event.values.bestClear, event.values.playClear]
                    .compactMap { $0 }.max { $0.precedence < $1.precedence }
                let values = (previous?.values.score ?? -1) > event.values.score ? previous!.values : event.values
                best[event.chart] = BestScore(accountID: accountID, chartID: event.chart, observationID: nil,
                    values: values, bestClear: clear, isOverridden: false, isBestCorrection: event.correction)
                index += 1
            } while index < events.count && events[index].date == date
            let units = try calculator.rank(bestScores: Array(best.values)).potentialUnits
            guard units != lastUnits || (includeFirstPoint && points.isEmpty) else { continue }
            lastUnits = units
            let millis = Int64((date.timeIntervalSince1970 * 1000).rounded())
            let timestamp = SourceTimestamp(value: millis, unit: .milliseconds)
            // Carry changes from the real official value, not the absolute B50 estimate.
            let micro = min(30_000_000, max(0, anchorMicro + (units - initial) * 5 / 3))
            points.append(PotentialPoint(accountID: accountID, sourceID: "continuation:\(millis)",
                timestamp: timestamp, value: PotentialValue(rawValue: micro, decimalPlaces: 6),
                series: .localEstimate, firstSeenAt: date))
        }
        return points
    }
}
