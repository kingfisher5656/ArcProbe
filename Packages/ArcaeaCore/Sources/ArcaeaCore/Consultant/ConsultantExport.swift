import Foundation
import CoreFoundation

public enum ConsultantExportError: Error, LocalizedError {
    case layout, stale, account, pending, unverified, selection, tooSoon
    public var errorDescription: String? {
        switch self {
        case .layout: "The sheet layout is not supported for sending scores. Only consultant v9.0.2a-beta is supported."
        case .stale: "The archive or sheet changed after this preview. Refresh the preview before sending."
        case .account: "Select an existing ArcProbe account before sending scores."
        case .pending: "A previous send still needs verification. Check it before sending again."
        case .unverified: "The sent scores have not all been verified. Check the pending send again after the sheet finishes calculating. No automatic resend was made."
        case .selection: "The selected account or workbook changed. Return to the original selection or refresh the preview."
        case .tooSoon: "Wait at least five minutes after the send, then check the sheet before dismissing its pending record."
        }
    }
}

public struct ConsultantExportSnapshot: Equatable, Sendable {
    enum RawCell: Equatable, Sendable {
        case empty, number(Double), text(String), boolean(Bool), invalid
        init(_ value: Any?) {
            if value == nil || value is NSNull || (value as? String) == "" { self = .empty }
            else if let n = value as? NSNumber {
                if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .boolean(n.boolValue) }
                else { self = n.doubleValue.isFinite ? .number(n.doubleValue) : .invalid }
            } else if let s = value as? String { self = .text(s) }
            else { self = .invalid }
        }
        var writable: Bool { switch self { case .empty, .number: true; case .text(let text): !text.hasPrefix("="); default: false } }
        var formula: Bool { if case .text(let text) = self { return text.hasPrefix("=") }; return false }
    }
    struct Row: Equatable, Sendable {
        let number: Int, identity: String, localizedIdentity: String
        let notes: Int?, score: Int?, raw: RawCell
    }
    let rows: [Row]
    public static func decode(evaluated: Data, raw: Data) throws -> Self {
        guard evaluated.count <= 8 * 1024 * 1024, raw.count <= 2 * 1024 * 1024,
              let root = try JSONSerialization.jsonObject(with: evaluated) as? [String: Any],
              let ranges = root["valueRanges"] as? [[String: Any]], ranges.count == 4,
              (ranges[0]["values"] as? [[String]])?.first?.first == "v9.0.2a-beta",
              let computed = ranges[1]["values"] as? [[Any]], computed.count <= 10_001,
              computed.first as? [String] == ["곡명_난이도", "체감보면상수", "노트수", "점수_나"],
              let input = ranges[2]["values"] as? [[Any]], input.count <= 10_000,
              let rawRoot = try JSONSerialization.jsonObject(with: raw) as? [String: Any],
              (ranges[3]["values"] as? [[String]])?.first == ["점수", "L"] else { throw ConsultantExportError.layout }
        let rawValues = rawRoot["values"] as? [[Any]] ?? []
        guard rawValues.count <= 10_001, RawCell(rawValues.first?.first) == .text("점수") else { throw ConsultantExportError.layout }
        var lookup: [String: [[Any]]] = [:]
        for cells in computed.dropFirst() {
            if let identity = cells.first as? String { lookup[identity, default: []].append(cells) }
        }
        var rows: [Row] = []
        for (index, cells) in input.enumerated() {
            let identity = cells.first as? String ?? ""
            let localized = cells.count > 1 ? cells[1] as? String ?? "" : ""
            let raw = RawCell(rawValues.indices.contains(index + 1) ? rawValues[index + 1].first : nil)
            if identity.isEmpty && localized.isEmpty && raw == .empty { continue }
            guard identity.utf8.count <= 1000, localized.utf8.count <= 1000 else { throw ConsultantExportError.layout }
            let matches = lookup[localized] ?? []
            let computed = matches.count == 1 ? matches[0] : []
            let notes = computed.count > 2 ? integer(computed[2]) : nil
            let score = computed.count > 3 ? integer(computed[3]) : nil
            rows.append(Row(number: index + 5, identity: identity, localizedIdentity: localized, notes: notes, score: score, raw: raw))
        }
        return Self(rows: rows)
    }
    private static func integer(_ value: Any) -> Int? {
        let number: Double?
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { number = n.doubleValue }
        else if let s = value as? String { number = Double(s) }
        else { number = nil }
        guard let number, number.isFinite, (0...10_100_000).contains(number) else { return nil }
        return Int(exactly: number)
    }
}

public struct ConsultantScoreWrite: Codable, Equatable, Sendable {
    public let row: Int
    public let identity: String
    public let localizedIdentity: String
    public let notes: Int
    public let score: Int
}
public enum ConsultantExportMode: String, CaseIterable, Codable, Sendable {
    case improvementsOnly, matchArcProbe
}

public struct ConsultantExportPlan: Sendable {
    public enum Disposition: String, Sendable { case increase, decrease, clear, unchanged, keepHigher, formula, unmapped, ambiguous, invalid, duplicate }
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: Int, title: String, chartID: ChartID?, previousScore: Int?, score: Int?, disposition: Disposition
        public var changesScore: Bool { [.increase, .decrease, .clear].contains(disposition) }
    }
    public let accountID: AccountID
    public let mode: ConsultantExportMode
    public let archiveScores: [String: Int]
    public let entries: [Entry]
    let snapshot: ConsultantExportSnapshot
    public var changes: [ConsultantScoreWrite] {
        let rows = Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.number, $0) })
        return entries.compactMap { entry in
            guard entry.changesScore, let row = rows[entry.id], let notes = row.notes, let score = entry.score else { return nil }
            return ConsultantScoreWrite(row: entry.id, identity: row.identity, localizedIdentity: row.localizedIdentity, notes: notes, score: score)
        }
    }
}

extension ArchiveStore {
    public func previewConsultantExport(_ snapshot: ConsultantExportSnapshot, accountID: AccountID, mode: ConsultantExportMode) throws -> ConsultantExportPlan {
        try locked { try database.transaction(write: false) {
            guard try database.integer("SELECT 1 FROM profiles WHERE account_id=?", [.text(accountID.rawValue)]) != nil else { throw ConsultantExportError.account }
            let catalog = try catalogUnlocked()
            let corrections: [BestCorrection] = try records("SELECT payload FROM best_corrections WHERE account_id=?", [.text(accountID.rawValue)])
            let best = ScoreReconciler.best(accountID: accountID, observations: try effectiveUnlocked(accountID: accountID, includeSuppressed: false), corrections: corrections)
            let scores = Dictionary(uniqueKeysWithValues: best.map { ($0.chartID, $0.values.score) })
            var matches: [String: Set<ChartID>] = [:]
            for alias in ConsultantTitles.aliases {
                guard let difficulty = Difficulty(rawValue: alias.difficulty) else { continue }
                let id = ChartID(songID: alias.songID, difficulty: difficulty)
                if catalog[id] != nil { matches[ConsultantTitles.key(alias.title, difficulty), default: []].insert(id) }
            }
            for chart in catalog.charts.values {
                if let title = chart.title { matches[ConsultantTitles.key(title, chart.id.difficulty), default: []].insert(chart.id) }
            }
            var entries: [ConsultantExportPlan.Entry] = []
            for row in snapshot.rows {
                var chart: ChartID?, score: Int?, disposition = ConsultantExportPlan.Disposition.invalid
                if let (title, difficulty) = ConsultantTitles.split(row.identity) {
                    let found = matches[ConsultantTitles.key(title, difficulty)] ?? []
                    if found.isEmpty { disposition = .unmapped }
                    else if found.count > 1 { disposition = .ambiguous }
                    else if let id = found.first {
                        chart = id; score = scores[id] ?? 0
                        if row.raw.formula { disposition = .formula }
                        else if let old = row.score, let notes = row.notes, (1...100_000).contains(notes), old <= 10_000_000 + notes,
                                let new = score, (0...10_000_000 + notes).contains(new), new == 0 || new >= 2237,
                                catalog[id]?.noteCount == nil || catalog[id]?.noteCount == notes, row.raw.writable, row.raw != .empty || old == 0 {
                            if new == old { disposition = .unchanged }
                            else if new > old { disposition = .increase }
                            else if mode == .improvementsOnly { disposition = .keepHigher }
                            else { disposition = new == 0 ? .clear : .decrease }
                        }
                    }
                }
                entries.append(.init(id: row.number, title: row.identity, chartID: chart, previousScore: row.score, score: score, disposition: disposition))
            }
            let counts = Dictionary(grouping: entries.compactMap(\.chartID), by: { $0 }).mapValues(\.count)
            entries = entries.map { entry in
                guard let id = entry.chartID, (counts[id] ?? 0) > 1 else { return entry }
                return .init(id: entry.id, title: entry.title, chartID: id, previousScore: entry.previousScore, score: entry.score, disposition: .duplicate)
            }
            return ConsultantExportPlan(accountID: accountID, mode: mode, archiveScores: Dictionary(uniqueKeysWithValues: scores.map { ($0.key.key, $0.value) }), entries: entries, snapshot: snapshot)
        } }
    }
}
