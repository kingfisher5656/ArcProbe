import Foundation

/// Serialized synchronous transactions; safe to call from a service actor or a background task.
public final class ArchiveStore: @unchecked Sendable {
    internal let database: ArchiveDatabase
    private let lock = NSRecursiveLock()
    internal let encoder: JSONEncoder
    internal let decoder = JSONDecoder()

    public init(url: URL, catalog: ChartCatalog? = nil) throws {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        database = try ArchiveDatabase(url: url)
        try Migrations.run(database)
        if let catalog {
            try database.transaction {
                for chart in catalog.charts.values {
                    try ArchiveValidation.metadata(chart)
                    try database.execute("INSERT OR IGNORE INTO charts(song_id, difficulty, payload) VALUES(?, ?, ?)",
                        [.text(chart.id.songID), .integer(Int64(chart.id.difficulty.rawValue)), .blob(try encoder.encode(chart))])
                }
            }
        }
    }
    public func profiles() throws -> [AccountProfile] {
        try locked { try records("SELECT payload FROM profiles ORDER BY account_id") }
    }
    public func apply(batch: ImportBatch) throws -> ImportReceipt {
        try locked {
            try ArchiveValidation.profile(batch.profile); try ArchiveValidation.date(batch.importedAt)
            guard batch.observations.count <= 100_000, batch.potentialPoints.count <= 100_000, batch.charts.count <= 20_000 else {
                throw ArchiveError.invalidRecord("Import collection is too large")
            }
            return try database.transaction {
                try database.execute("INSERT INTO profiles(account_id, payload) VALUES(?, ?) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload",
                    [.text(batch.profile.id.rawValue), .blob(try encoder.encode(batch.profile))])
                for chart in batch.charts { try putChart(chart) }
                let catalog = try catalogUnlocked()
                var added = 0, duplicate = 0, points = 0
                for incoming in batch.observations {
                    guard incoming.accountID == batch.profile.id else { throw ArchiveError.accountMismatch }
                    try ArchiveValidation.observation(incoming, metadata: catalog[incoming.chartID])
                    let observation = try resolveObservation(incoming)
                    if let existing: ScoreObservation = try record("SELECT payload FROM observations WHERE observation_id=?", [.text(observation.id.rawValue)]) {
                        let captures = try capturesUnlocked(observationID: observation.id)
                        guard compatible(existing, observation), captures.allSatisfy({ compatible($0, observation) }) else {
                            throw ArchiveError.identityCollision(observation.id.rawValue)
                        }
                        try putCapture(observation)
                        duplicate += 1
                    } else { try putObservation(observation); added += 1 }
                }
                for point in batch.potentialPoints {
                    guard point.accountID == batch.profile.id else { throw ArchiveError.accountMismatch }
                    try ArchiveValidation.potential(point)
                    let key: [SQLValue] = [.text(point.accountID.rawValue), .text(point.series.rawValue), .text(point.sourceID)]
                    if let existing: PotentialPoint = try record("SELECT payload FROM potential_points WHERE account_id=? AND series=? AND source_id=?", key) {
                        guard existing.timestamp.milliseconds == point.timestamp.milliseconds,
                              existing.value.equivalent(to: point.value) else {
                            throw ArchiveError.identityCollision(point.sourceID)
                        }
                    } else {
                        try database.execute("INSERT INTO potential_points(account_id, series, source_id, payload) VALUES(?, ?, ?, ?)",
                                             key + [.blob(try encoder.encode(point))])
                        points += 1
                    }
                }
                try capturePotentialBaseline(batch)
                let receipt = ImportReceipt(accountID: batch.profile.id, kind: batch.kind, importedAt: batch.importedAt,
                    addedCount: added, duplicateCount: duplicate, addedPotentialCount: points)
                try putReceipt(receipt)
                return receipt
            }
        }
    }
    public func observations(accountID: AccountID, includeSuppressed: Bool = false) throws -> [EffectiveObservation] {
        try locked { try database.transaction(write: false) { try effectiveUnlocked(accountID: accountID, includeSuppressed: includeSuppressed) } }
    }
    public func sourceObservations(accountID: AccountID) throws -> [ScoreObservation] {
        try locked { try records("SELECT payload FROM observations WHERE account_id=? ORDER BY observation_id", [.text(accountID.rawValue)]) }
    }
    /// Every immutable payload captured for a canonical attempt, including later enrichment.
    public func sourceCaptures(observationID: ObservationID) throws -> [ScoreObservation] {
        try locked { try capturesUnlocked(observationID: canonicalID(observationID)) }
    }
    public func captureSources(accountID: AccountID) throws -> [ObservationID: Set<ObservationSource>] {
        try locked {
            let captures: [ScoreObservation] = try records("SELECT c.payload FROM observation_captures c JOIN observations o ON o.observation_id=c.observation_id WHERE o.account_id=?",
                [.text(accountID.rawValue)])
            return Dictionary(grouping: captures, by: \.id).mapValues { Set($0.map(\.source)) }
        }
    }
    public func bestScores(accountID: AccountID) throws -> [BestScore] {
        try locked {
            try database.transaction(write: false) {
                let observations = try effectiveUnlocked(accountID: accountID, includeSuppressed: false)
                let corrections: [BestCorrection] = try records("SELECT payload FROM best_corrections WHERE account_id=?", [.text(accountID.rawValue)])
                return ScoreReconciler.best(accountID: accountID, observations: observations, corrections: corrections)
            }
        }
    }
    public func potentialHistory(accountID: AccountID, series: PotentialSeries = .official) throws -> [PotentialPoint] {
        try locked {
            let points: [PotentialPoint] = try records("SELECT payload FROM potential_points WHERE account_id=? AND series=?", [.text(accountID.rawValue), .text(series.rawValue)])
            return points.sorted {
                if $0.timestamp.milliseconds != $1.timestamp.milliseconds { return ($0.timestamp.milliseconds ?? 0) < ($1.timestamp.milliseconds ?? 0) }
                return $0.sourceID < $1.sourceID
            }
        }
    }
    public func chartCatalog() throws -> ChartCatalog { try locked { try catalogUnlocked() } }
    public func receipts(accountID: AccountID? = nil) throws -> [ImportReceipt] {
        try locked {
            let receipts: [ImportReceipt]
            if let accountID { receipts = try records("SELECT payload FROM receipts WHERE account_id=?", [.text(accountID.rawValue)]) }
            else { receipts = try records("SELECT payload FROM receipts") }
            return receipts.sorted { $0.importedAt == $1.importedAt ? $0.id.uuidString < $1.id.uuidString : $0.importedAt < $1.importedAt }
        }
    }

    internal func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }; return try body()
    }
    internal func records<T: Decodable>(_ sql: String, _ bindings: [SQLValue] = []) throws -> [T] {
        try database.dataRows(sql, bindings).map { try decoder.decode(T.self, from: $0) }
    }
    internal func record<T: Decodable>(_ sql: String, _ bindings: [SQLValue] = []) throws -> T? {
        try records(sql, bindings).first
    }
    internal func putObservation(_ observation: ScoreObservation) throws {
        try database.execute("INSERT INTO observations(observation_id, account_id, song_id, difficulty, payload) VALUES(?, ?, ?, ?, ?)",
            [.text(observation.id.rawValue), .text(observation.accountID.rawValue), .text(observation.chartID.songID),
             .integer(Int64(observation.chartID.difficulty.rawValue)), .blob(try encoder.encode(observation))])
        try putCapture(observation)
    }
    internal func putCapture(_ observation: ScoreObservation) throws {
        let captures = try capturesUnlocked(observationID: observation.id)
        if captures.contains(where: { $0.source == observation.source && $0.values == observation.values
            && $0.identityConfidence == observation.identityConfidence }) { return }
        guard captures.count < 256 else { throw ArchiveError.invalidRecord("Too many payload variants for one attempt") }
        struct CaptureIdentity: Encodable { let source: ObservationSource; let values: ScoreValues; let confidence: IdentityConfidence }
        let captureID = try encoder.encode(CaptureIdentity(source: observation.source, values: observation.values,
            confidence: observation.identityConfidence)).base64EncodedString()
        try database.execute("INSERT OR IGNORE INTO observation_captures(observation_id, capture_id, payload) VALUES(?, ?, ?)",
            [.text(observation.id.rawValue), .text(captureID), .blob(try encoder.encode(observation))])
    }
    internal func putReceipt(_ receipt: ImportReceipt) throws {
        try database.execute("INSERT INTO receipts(id, account_id, payload) VALUES(?, ?, ?)",
            [.text(receipt.id.uuidString), receipt.accountID.map { .text($0.rawValue) } ?? .null, .blob(try encoder.encode(receipt))])
    }
    internal func putChart(_ chart: ChartMetadata) throws {
        try ArchiveValidation.metadata(chart)
        let existing: ChartMetadata? = try record("SELECT payload FROM charts WHERE song_id=? AND difficulty=?",
            [.text(chart.id.songID), .integer(Int64(chart.id.difficulty.rawValue))])
        let merged: ChartMetadata
        if let old = existing {
            merged = ChartMetadata(id: chart.id, constant: chart.constant ?? old.constant,
                isOutdated: chart.constant == nil ? old.isOutdated : chart.isOutdated,
                level: chart.level ?? old.level, difficultyLabel: chart.difficultyLabel ?? old.difficultyLabel,
                noteCount: chart.noteCount ?? old.noteCount, title: chart.title ?? old.title,
                artist: chart.artist ?? old.artist, artworkIdentifier: chart.artworkIdentifier ?? old.artworkIdentifier,
                provenance: old.provenance.contains(chart.provenance) ? old.provenance : old.provenance + "; " + chart.provenance)
        } else { merged = chart }
        try ArchiveValidation.metadata(merged)
        try database.execute("INSERT INTO charts(song_id, difficulty, payload) VALUES(?, ?, ?) ON CONFLICT(song_id, difficulty) DO UPDATE SET payload=excluded.payload",
            [.text(chart.id.songID), .integer(Int64(chart.id.difficulty.rawValue)), .blob(try encoder.encode(merged))])
    }
    internal func catalogUnlocked() throws -> ChartCatalog {
        ChartCatalog(charts: try records("SELECT payload FROM charts"))
    }
    internal func effectiveUnlocked(accountID: AccountID, includeSuppressed: Bool) throws -> [EffectiveObservation] {
        let rows: [ScoreObservation] = try records("SELECT o.payload FROM observations o WHERE o.account_id=? "
            + (includeSuppressed ? "" : "AND NOT EXISTS(SELECT 1 FROM suppressions s WHERE s.observation_id=o.observation_id) ")
            + "ORDER BY o.observation_id", [.text(accountID.rawValue)])
        return try rows.map { row in
            let override: ScoreValues? = try record("SELECT payload FROM overrides WHERE observation_id=?", [.text(row.id.rawValue)])
            let captures = try capturesUnlocked(observationID: row.id)
            let chosen = captures.sorted {
                let a = detailCount($0.values), b = detailCount($1.values)
                if a != b { return a > b }
                if $0.source != $1.source { return $0.source.rawValue < $1.source.rawValue }
                return $0.firstSeenAt < $1.firstSeenAt
            }.first ?? row
            let bestClear = captures.flatMap { [$0.values.playClear, $0.values.bestClear].compactMap { $0 } }.max { $0.precedence < $1.precedence }
            let v = chosen.values
            let enriched = ScoreValues(score: v.score, playedAt: v.playedAt, judgments: v.judgments,
                                       playClear: v.playClear, bestClear: bestClear, modifier: v.modifier, health: v.health)
            return EffectiveObservation(original: chosen, values: override ?? enriched, isOverridden: override != nil)
        }
    }
    internal func capturesUnlocked(observationID: ObservationID) throws -> [ScoreObservation] {
        try records("SELECT payload FROM observation_captures WHERE observation_id=? ORDER BY capture_id", [.text(observationID.rawValue)])
    }
    internal func compatible(_ lhs: ScoreObservation, _ rhs: ScoreObservation) -> Bool {
        func shared<T: Equatable>(_ a: T?, _ b: T?) -> Bool { a == nil || b == nil || a == b }
        guard lhs.accountID == rhs.accountID, lhs.chartID == rhs.chartID,
              (lhs.source == .manual) == (rhs.source == .manual), lhs.score == rhs.score,
              shared(lhs.values.playedAt?.milliseconds, rhs.values.playedAt?.milliseconds),
              shared(lhs.values.playClear, rhs.values.playClear),
              shared(lhs.values.health, rhs.values.health), shared(lhs.values.modifier, rhs.values.modifier) else { return false }
        let a = lhs.values.judgments, b = rhs.values.judgments
        return shared(a?.pure, b?.pure) && shared(a?.shinyPure, b?.shinyPure) && shared(a?.far, b?.far)
            && shared(a?.lost, b?.lost) && shared(a?.early, b?.early) && shared(a?.late, b?.late)
    }
    private func detailCount(_ values: ScoreValues) -> Int {
        [values.judgments?.pure, values.judgments?.shinyPure, values.judgments?.far,
         values.judgments?.lost, values.judgments?.early, values.judgments?.late, values.health, values.modifier].compactMap { $0 }.count
            + (values.playedAt == nil ? 0 : 1) + (values.playClear == nil ? 0 : 1)
    }
}
