import Foundation

public struct RankedScore: Hashable, Codable, Sendable {
    public let best: BestScore
    public let ratingUnits: Int64?
    public let rank: Int?
}
public struct RankingSnapshot: Hashable, Codable, Sendable {
    public let rows: [RankedScore]
    public let potentialUnits: Int64
    public let best50AverageUnits: Int64
    public let missingConstants: Int
    public let unknownClears: Int
    public let ruleVersion: String
    public let isEstimate: Bool
}

public struct RatingCalculator: Sendable {
    public static let scale: Int64 = 600_000
    public let catalog: ChartCatalog
    public init(catalog: ChartCatalog) { self.catalog = catalog }
    public static func base(constant: ChartConstant, score: Int) throws -> Int64 {
        guard (1...200).contains(constant.tenths), (0...10_100_000).contains(score) else {
            throw ArchiveError.invalidRecord("Chart constant or score is outside the supported range")
        }
        let modifier: Int64
        if score >= 10_000_000 { modifier = 2 * scale }
        else if score >= 9_800_000 { modifier = scale + Int64(score - 9_800_000) * 3 }
        else { modifier = Int64(score - 9_500_000) * 2 }
        return max(0, Int64(constant.tenths) * 60_000 + modifier)
    }
    public static func play(constant: ChartConstant, score: Int, clear: ClearType?) throws -> Int64 {
        try base(constant: constant, score: score) + (clear?.hasRatingBonus == true ? scale / 5 : 0)
    }
    public static func display(_ units: Int64, rounded: Bool = false) -> String {
        let milli = (units + (rounded ? 300 : 0)) / 600
        return String(format: "%lld.%03lld", locale: Locale(identifier: "en_US_POSIX"), milli / 1_000, milli % 1_000)
    }
    public func rank(observations: [ScoreObservation]) throws -> RankingSnapshot {
        guard Set(observations.map(\.accountID)).count <= 1 else { throw ArchiveError.accountMismatch }
        for observation in observations { try ArchiveValidation.observation(observation, metadata: catalog[observation.chartID]) }
        let effective = observations.map { EffectiveObservation(original: $0, values: $0.values, isOverridden: false) }
        let account = observations.first?.accountID ?? AccountID("empty")
        return try rank(bestScores: ScoreReconciler.best(accountID: account, observations: effective))
    }
    public func rank(bestScores: [BestScore]) throws -> RankingSnapshot {
        guard Set(bestScores.map(\.accountID)).count <= 1 else { throw ArchiveError.accountMismatch }
        guard Set(bestScores.map(\.chartID)).count == bestScores.count else {
            throw ArchiveError.invalidRecord("Rank one best score per chart")
        }
        var rows = try bestScores.map { best -> RankedScore in
            let units = try catalog[best.chartID]?.usableConstant.map {
                try Self.play(constant: $0, score: best.values.score, clear: best.bestClear)
            }
            return RankedScore(best: best, ratingUnits: units, rank: nil)
        }
        rows.sort {
            if $0.ratingUnits != $1.ratingUnits { return ($0.ratingUnits ?? -1) > ($1.ratingUnits ?? -1) }
            if $0.best.values.score != $1.best.values.score { return $0.best.values.score > $1.best.values.score }
            return $0.best.chartID.key < $1.best.chartID.key
        }
        var rank = 0, weighted: Int64 = 0, sum: Int64 = 0
        rows = rows.map { row in
            guard let units = row.ratingUnits else { return row }
            rank += 1
            if rank <= 50 { weighted += units * (rank <= 10 ? 2 : 1); sum += units }
            return RankedScore(best: row.best, ratingUnits: units, rank: rank)
        }
        return RankingSnapshot(rows: rows, potentialUnits: weighted / 60, best50AverageUnits: sum / 50,
                               missingConstants: rows.filter { $0.ratingUnits == nil }.count,
                               unknownClears: rows.filter { $0.best.bestClear == nil }.count,
                               ruleVersion: "arcpot-2026-09", isEstimate: true)
    }
}
