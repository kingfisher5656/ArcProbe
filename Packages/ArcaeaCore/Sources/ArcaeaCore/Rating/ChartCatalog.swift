import Foundation

public struct ChartConstant: Hashable, Codable, Sendable {
    public let tenths: Int
    public init(tenths: Int) { self.tenths = tenths }
    public var value: Double { Double(tenths) / 10 }
}

public struct ChartMetadata: Hashable, Codable, Sendable {
    public let id: ChartID
    public let constant: ChartConstant?
    public let isOutdated: Bool
    public let level: String?
    public let difficultyLabel: String?
    public let noteCount: Int?
    public let title: String?
    public let artist: String?
    public let artworkIdentifier: String?
    public let provenance: String
    public init(id: ChartID, constant: ChartConstant? = nil, isOutdated: Bool = false,
                level: String? = nil, difficultyLabel: String? = nil, noteCount: Int? = nil,
                title: String? = nil, artist: String? = nil, artworkIdentifier: String? = nil,
                provenance: String) {
        self.id = id; self.constant = constant; self.isOutdated = isOutdated; self.level = level
        self.difficultyLabel = difficultyLabel; self.noteCount = noteCount; self.provenance = provenance
        self.title = title; self.artist = artist; self.artworkIdentifier = artworkIdentifier
    }
    public var usableConstant: ChartConstant? { isOutdated ? nil : constant }
    public var displayDifficulty: String { difficultyLabel ?? id.difficulty.label }
}

public struct ChartCatalog: Sendable {
    public let charts: [ChartID: ChartMetadata]
    public init(charts: [ChartMetadata]) { self.charts = Dictionary(charts.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new }) }
    public subscript(id: ChartID) -> ChartMetadata? { charts[id] }
    public static func bundled() throws -> ChartCatalog {
        struct ConstantEntry: Decodable { let constant: Decimal; let old: Bool }
        struct LevelEntry: Decodable { let difficultyLabel: String; let level: String }
        struct Levels: Decodable { let charts: [String: LevelEntry] }
        guard let constantsURL = Bundle.module.url(forResource: "chart-constants", withExtension: "json"),
              let levelsURL = Bundle.module.url(forResource: "chart-levels", withExtension: "json") else {
            throw ArchiveError.notFound("Bundled chart metadata")
        }
        let decoder = JSONDecoder()
        let constants = try decoder.decode([String: [ConstantEntry?]].self, from: Data(contentsOf: constantsURL))
        let levels = try decoder.decode(Levels.self, from: Data(contentsOf: levelsURL)).charts
        var charts: [ChartID: ChartMetadata] = [:]
        for (song, entries) in constants {
            for (index, entry) in entries.enumerated() {
                guard let difficulty = Difficulty(rawValue: index), let entry else { continue }
                let scaled = entry.constant * 10
                let number = NSDecimalNumber(decimal: scaled)
                guard number.decimalValue == Decimal(number.intValue), (1...200).contains(number.intValue) else {
                    throw ArchiveError.invalidRecord("Bundled constant is not an exact tenth")
                }
                let id = ChartID(songID: song, difficulty: difficulty)
                charts[id] = ChartMetadata(id: id, constant: ChartConstant(tenths: number.intValue),
                    isOutdated: entry.old, provenance: "Arcaea Wiki contributors; CC BY-SA 4.0; snapshot 2026-09-09")
            }
        }
        for (key, level) in levels {
            let parts = key.split(separator: ":")
            guard parts.count == 2, let raw = Int(parts[1]), let difficulty = Difficulty(rawValue: raw) else {
                throw ArchiveError.invalidRecord("Invalid bundled chart ID")
            }
            let id = ChartID(songID: String(parts[0]), difficulty: difficulty), old = charts[id]
            charts[id] = ChartMetadata(id: id, constant: old?.constant, isOutdated: old?.isOutdated ?? false,
                level: level.level, difficultyLabel: level.difficultyLabel,
                provenance: ((old?.provenance).map { $0 + "; " } ?? "") + "ArcPotApk public game7.0.255 difficulty index")
        }
        for chart in charts.values { try ArchiveValidation.metadata(chart) }
        return ChartCatalog(charts: Array(charts.values))
    }
}
