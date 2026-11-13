import Foundation
import CoreFoundation

public enum ConsultantImportError: Error, LocalizedError {
    case unsupportedLayout, stalePreview
    public var errorDescription: String? {
        switch self {
        case .unsupportedLayout: "This sheet version or score layout is not supported. The first import version supports consultant v9.0.2a-beta. No scores were imported."
        case .stalePreview: "The archive changed after this preview. Refresh the preview before importing."
        }
    }
}

public struct ConsultantSnapshot: Sendable {
    struct Row: Sendable { let number: Int; let identity: String; let score: Int?; let notes: Int? }
    let rows: [Row]
    public let emptyCount: Int
    public let version: String
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 8 * 1024 * 1024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ranges = root["valueRanges"] as? [[String: Any]], ranges.count == 2,
              let version = (ranges[0]["values"] as? [[String]])?.first?.first, version == "v9.0.2a-beta",
              let values = ranges[1]["values"] as? [[Any]], values.count <= 10_001,
              let header = values.first as? [String], header == ["곡명_난이도", "체감보면상수", "노트수", "점수_나"] else {
            throw ConsultantImportError.unsupportedLayout
        }
        var rows: [Row] = [], empty = 0
        for (index, cells) in values.dropFirst().enumerated() {
            let scoreValue = cells.count > 3 ? cells[3] : nil
            let score = integer(scoreValue)
            if scoreValue == nil || scoreValue is NSNull || (scoreValue as? String) == "" || score == 0 { empty += 1; continue }
            let identity = cells.first as? String ?? ""
            guard identity.utf8.count <= 1_000 else { throw ConsultantImportError.unsupportedLayout }
            rows.append(Row(number: index + 3, identity: identity, score: score,
                            notes: cells.count > 2 ? integer(cells[2]) : nil))
        }
        return Self(rows: rows, emptyCount: empty, version: version)
    }
    private static func integer(_ value: Any?) -> Int? {
        let number: Double?
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { number = n.doubleValue }
        else if let s = value as? String { number = Double(s) }
        else { number = nil }
        guard let number, number.isFinite, (0...10_100_000).contains(number) else { return nil }
        return Int(exactly: number)
    }
}

public struct ConsultantImportPlan: Sendable {
    public enum Disposition: String, Sendable { case add, keepExisting, manualProtected, unmapped, ambiguous, invalid, duplicate }
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: Int
        public let title: String
        public let chartID: ChartID?
        public let score: Int?
        public let previousScore: Int?
        public let disposition: Disposition
    }
    public let accountID: AccountID
    public let entries: [Entry]
    public let emptyCount: Int
    public var addCount: Int { entries.filter { $0.disposition == .add }.count }
    let snapshot: ConsultantSnapshot
}

enum ConsultantTitles {
    static let aliases = BundledSongTitles.aliases
    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
    static func key(_ title: String, _ difficulty: Difficulty) -> String { normalize(title) + "|" + String(difficulty.rawValue) }
    static func split(_ identity: String) -> (String, Difficulty)? {
        for (label, difficulty) in [("PST", Difficulty.past), ("PRS", .present), ("FTR", .future), ("BYD", .beyond), ("ETR", .eternal), ("INS", .beyond)] {
            let suffix = " [" + label + "]"
            if identity.hasSuffix(suffix) { return (String(identity.dropLast(suffix.count)), difficulty) }
        }
        return nil
    }
}

extension ArchiveStore {
    public func previewConsultantImport(_ snapshot: ConsultantSnapshot, accountID: AccountID) throws -> ConsultantImportPlan {
        try locked { try database.transaction(write: false) { try consultantPlanUnlocked(snapshot, accountID: accountID) } }
    }
    /// Revalidation and insertion share one transaction, including protection from concurrent Shortcut imports.
    public func importConsultant(_ plan: ConsultantImportPlan, fileID: String, importedAt: Date = Date()) throws -> ImportReceipt {
        try locked {
            guard fileID.range(of: "^[A-Za-z0-9_-]{1,200}$", options: .regularExpression) != nil else { throw ArchiveError.invalidRecord("Invalid sheet selection") }
            try ArchiveValidation.date(importedAt)
            return try database.transaction {
                let current = try consultantPlanUnlocked(plan.snapshot, accountID: plan.accountID)
                guard current.entries == plan.entries else { throw ConsultantImportError.stalePreview }
                let additions = current.entries.filter { $0.disposition == .add }
                // Do not create a phantom profile or receipt for an empty import.
                if additions.isEmpty { return ImportReceipt(accountID: plan.accountID, kind: .consultantSheet, importedAt: importedAt, addedCount: 0, duplicateCount: 0, addedPotentialCount: 0) }
                let profile = AccountProfile(id: plan.accountID)
                try database.execute("INSERT OR IGNORE INTO profiles(account_id, payload) VALUES(?, ?)", [.text(plan.accountID.rawValue), .blob(try encoder.encode(profile))])
                let catalog = try catalogUnlocked()
                var added = 0
                for entry in additions {
                    guard let chart = entry.chartID, let score = entry.score else { throw ConsultantImportError.stalePreview }
                    let parts = [plan.accountID.rawValue, fileID, chart.key, String(score)]
                    let id = ObservationID("consultant-v1:" + parts.map { "\($0.utf8.count):\($0)" }.joined())
                    // Suppressions remain effective even when a user reimports the same workbook.
                    if try database.integer("SELECT 1 FROM observations WHERE observation_id=?", [.text(id.rawValue)]) != nil { continue }
                    let observation = ScoreObservation(id: id, accountID: plan.accountID, chartID: chart,
                        source: .consultantSheet, values: ScoreValues(score: score), firstSeenAt: importedAt, identityConfidence: .payloadOnly)
                    try ArchiveValidation.observation(observation, metadata: catalog[chart])
                    try putObservation(observation); added += 1
                }
                let receipt = ImportReceipt(accountID: plan.accountID, kind: .consultantSheet, importedAt: importedAt, addedCount: added, duplicateCount: additions.count - added, addedPotentialCount: 0)
                try putReceipt(receipt)
                return receipt
            }
        }
    }
    private func consultantPlanUnlocked(_ snapshot: ConsultantSnapshot, accountID: AccountID) throws -> ConsultantImportPlan {
        try ArchiveValidation.account(accountID)
        let catalog = try catalogUnlocked()
        var matches: [String: Set<ChartID>] = [:]
        for alias in ConsultantTitles.aliases {
            guard let difficulty = Difficulty(rawValue: alias.difficulty) else { continue }
            let id = ChartID(songID: alias.songID, difficulty: difficulty)
            if catalog[id] != nil { matches[ConsultantTitles.key(alias.title, difficulty), default: []].insert(id) }
        }
        for chart in catalog.charts.values {
            if let title = chart.title { matches[ConsultantTitles.key(title, chart.id.difficulty), default: []].insert(chart.id) }
        }
        let corrections: [BestCorrection] = try records("SELECT payload FROM best_corrections WHERE account_id=?", [.text(accountID.rawValue)])
        let edited: [ScoreObservation] = try records("SELECT o.payload FROM observations o WHERE account_id=? AND (EXISTS(SELECT 1 FROM overrides v WHERE v.observation_id=o.observation_id) OR EXISTS(SELECT 1 FROM suppressions s WHERE s.observation_id=o.observation_id))", [.text(accountID.rawValue)])
        let protected = Set(corrections.map(\.chartID) + edited.map(\.chartID))
        let best = ScoreReconciler.best(accountID: accountID, observations: try effectiveUnlocked(accountID: accountID, includeSuppressed: false), corrections: corrections)
        let previous = Dictionary(uniqueKeysWithValues: best.map { ($0.chartID, $0.values.score) })
        var entries: [ConsultantImportPlan.Entry] = []
        for row in snapshot.rows {
            var chart: ChartID?, disposition = ConsultantImportPlan.Disposition.invalid
            if let score = row.score, score > 0, let notes = row.notes, (1...100_000).contains(notes), score <= 10_000_000 + notes,
               let (title, difficulty) = ConsultantTitles.split(row.identity) {
                let found = matches[ConsultantTitles.key(title, difficulty)] ?? []
                if found.isEmpty { disposition = .unmapped }
                else if found.count > 1 { disposition = .ambiguous }
                else if let id = found.first {
                    chart = id
                    if let known = catalog[id]?.noteCount, known != notes { disposition = .invalid }
                    else if protected.contains(id) { disposition = .manualProtected }
                    else if let old = previous[id], old >= score { disposition = .keepExisting }
                    else { disposition = .add }
                }
            }
            entries.append(.init(id: row.number, title: row.identity, chartID: chart, score: row.score, previousScore: chart.flatMap { previous[$0] }, disposition: disposition))
        }
        let counts = Dictionary(grouping: entries.compactMap(\.chartID), by: { $0 }).mapValues(\.count)
        entries = entries.map { entry in
            guard let id = entry.chartID, (counts[id] ?? 0) > 1 else { return entry }
            return .init(id: entry.id, title: entry.title, chartID: id, score: entry.score, previousScore: entry.previousScore, disposition: .duplicate)
        }
        return .init(accountID: accountID, entries: entries, emptyCount: snapshot.emptyCount, snapshot: snapshot)
    }
}
