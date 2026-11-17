import Foundation

/// What importing a game folder would do, worked out without changing anything.
public struct GameDataImportPlan: Sendable {
    public enum Disposition: String, Sendable { case add, keepExisting, unknownChart, invalid, removedEarlier }
    public struct Entry: Identifiable, Equatable, Sendable {
        public var id: String { chartID.key }
        public let chartID: ChartID
        public let score: Int
        public let previousScore: Int?
        public let disposition: Disposition
    }
    public let accountID: AccountID
    public let entries: [Entry]
    /// Charts the folder's song list would add or update.
    public let chartChangeCount: Int
    public var additions: [Entry] { entries.filter { $0.disposition == .add } }
    public var addCount: Int { additions.count }
    let scores: [GameScore]
    let songList: SongListSnapshot?
}

extension ArchiveStore {
    /// Game scores are extra evidence, not a replacement: one is added only when it beats the chart's current best.
    public func previewGameDataImport(_ scores: [GameScore], songList: SongListSnapshot? = nil, accountID: AccountID) throws -> GameDataImportPlan {
        try locked {
            try database.transaction(write: false) {
                try gameDataPlan(scores, songList: songList, accountID: accountID,
                                 chartChanges: songList.map { try songListChanges($0).count } ?? 0)
            }
        }
    }
    /// Applies the folder's song list, then adds the scores marked `add`. The plan is checked again in the same transaction.
    public func importGameData(_ plan: GameDataImportPlan, importedAt: Date = Date()) throws -> ImportReceipt {
        try locked {
            try ArchiveValidation.date(importedAt)
            return try database.transaction {
                let chartChanges = try plan.songList.map { try applySongListUnlocked($0) } ?? 0
                let current = try gameDataPlan(plan.scores, songList: nil, accountID: plan.accountID, chartChanges: chartChanges)
                guard current.entries == plan.entries else { throw GameDataError.stalePreview }
                let empty = ImportReceipt(accountID: plan.accountID, kind: .gameData, importedAt: importedAt, addedCount: 0, duplicateCount: 0, addedPotentialCount: 0)
                // Do not create a phantom profile or receipt when no score is added.
                guard current.addCount > 0 else { return empty }
                let profile = AccountProfile(id: plan.accountID)
                try database.execute("INSERT OR IGNORE INTO profiles(account_id, payload) VALUES(?, ?)", [.text(plan.accountID.rawValue), .blob(try encoder.encode(profile))])
                let catalog = try catalogUnlocked()
                let wanted = Set(current.additions.map(\.chartID))
                for score in plan.scores where wanted.contains(score.chartID) {
                    guard let observation = gameObservation(score, accountID: plan.accountID, metadata: catalog[score.chartID], importedAt: importedAt) else {
                        throw GameDataError.stalePreview
                    }
                    try putObservation(observation)
                }
                let receipt = ImportReceipt(accountID: plan.accountID, kind: .gameData, importedAt: importedAt, addedCount: wanted.count, duplicateCount: 0, addedPotentialCount: 0)
                try putReceipt(receipt)
                return receipt
            }
        }
    }
    public func gameDataScoreCount(accountID: AccountID) throws -> Int {
        try locked { try gameDataObservations(accountID).count }
    }
    /// Takes back every score that came from a game folder, for example after importing the wrong account's folder.
    @discardableResult public func removeGameDataScores(accountID: AccountID) throws -> Int {
        try locked {
            try database.transaction {
                let removed = Set(try gameDataObservations(accountID).map(\.id))
                for id in removed { try database.execute("DELETE FROM observations WHERE observation_id=?", [.text(id.rawValue)]) }
                // An older Undo must not try to restore an edit of a score that no longer exists.
                let undo: [ManualUndoRecord] = try records("SELECT payload FROM manual_undo")
                for record in undo {
                    let stale: Bool
                    switch record.state {
                    case .added(let id, _), .override(let id, _), .suppression(let id, _): stale = removed.contains(id)
                    case .correction: stale = false
                    }
                    if stale { try database.execute("DELETE FROM manual_undo WHERE id=?", [.text(record.token.id.uuidString)]) }
                }
                return removed.count
            }
        }
    }

    private func gameDataObservations(_ accountID: AccountID) throws -> [ScoreObservation] {
        let rows: [ScoreObservation] = try records("SELECT payload FROM observations WHERE account_id=?", [.text(accountID.rawValue)])
        return rows.filter { $0.source == .gameData }
    }
    private func gameDataPlan(_ scores: [GameScore], songList: SongListSnapshot?, accountID: AccountID, chartChanges: Int) throws -> GameDataImportPlan {
        try ArchiveValidation.account(accountID)
        guard scores.count <= 100_000 else { throw ArchiveError.invalidRecord("Import collection is too large") }
        var highest: [ChartID: GameScore] = [:]
        for score in scores where (highest[score.chartID]?.score ?? 0) < score.score { highest[score.chartID] = score }
        let scores = highest.values.sorted { $0.chartID.key < $1.chartID.key }
        let catalog = try catalogUnlocked()
        let corrections: [BestCorrection] = try records("SELECT payload FROM best_corrections WHERE account_id=?", [.text(accountID.rawValue)])
        let best = ScoreReconciler.best(accountID: accountID, observations: try effectiveUnlocked(accountID: accountID, includeSuppressed: false), corrections: corrections)
        let previous = Dictionary(best.map { ($0.chartID, $0.values.score) }, uniquingKeysWith: max)
        let now = Date()
        let entries = try scores.map { score -> GameDataImportPlan.Entry in
            let disposition: GameDataImportPlan.Disposition
            // Only songs the app or the folder's own song list knows: this leaves out custom charts.
            if catalog[score.chartID] == nil, songList?.charts[score.chartID] == nil { disposition = .unknownChart }
            else if let observation = gameObservation(score, accountID: accountID, metadata: catalog[score.chartID], importedAt: now) {
                if let old = previous[score.chartID], old >= score.score { disposition = .keepExisting }
                else if try database.integer("SELECT 1 FROM observations WHERE observation_id=?", [.text(observation.id.rawValue)]) != nil {
                    // Present but not counted: the user deleted or edited this play in ArcProbe.
                    disposition = .removedEarlier
                } else { disposition = .add }
            } else { disposition = .invalid }
            return .init(chartID: score.chartID, score: score.score, previousScore: previous[score.chartID], disposition: disposition)
        }
        return GameDataImportPlan(accountID: accountID, entries: entries, chartChangeCount: chartChanges, scores: scores, songList: songList)
    }
    /// The same score for the same chart always gets the same identity, so importing twice adds nothing.
    private func gameObservation(_ score: GameScore, accountID: AccountID, metadata: ChartMetadata?, importedAt: Date) -> ScoreObservation? {
        func values(_ judgments: Judgments?) -> ScoreValues {
            ScoreValues(score: score.score, judgments: judgments, bestClear: score.bestClear, modifier: score.modifier, health: score.health)
        }
        var chosen = values(score.judgments)
        if (try? ArchiveValidation.values(chosen, metadata: metadata)) == nil {
            // Counts from an older version of the chart can disagree with the known note count; the score still stands.
            chosen = values(nil)
            guard (try? ArchiveValidation.values(chosen, metadata: metadata)) != nil else { return nil }
        }
        let parts = [accountID.rawValue, score.chartID.key, String(score.score)]
        let id = ObservationID("gamedata-v1:" + parts.map { "\($0.utf8.count):\($0)" }.joined())
        let observation = ScoreObservation(id: id, accountID: accountID, chartID: score.chartID, source: .gameData,
            values: chosen, firstSeenAt: importedAt, identityConfidence: .payloadOnly)
        return (try? ArchiveValidation.observation(observation, metadata: metadata)) == nil ? nil : observation
    }
}
