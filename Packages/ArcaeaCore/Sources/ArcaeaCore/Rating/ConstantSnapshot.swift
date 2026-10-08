import Foundation

public struct ConstantSnapshot: Sendable {
    public let charts: [ChartID: ChartMetadata]
    public let fetchedAt: Date
    public static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> ConstantSnapshot {
        struct Entry: Decodable { let constant: Decimal; let old: Bool }
        guard data.count <= 8 * 1_024 * 1_024 else { throw ArchiveError.invalidRecord("Constant table is too large") }
        let source = try JSONDecoder().decode([String: [Entry?]].self, from: data)
        guard !source.isEmpty, source.count <= 10_000 else { throw ArchiveError.invalidRecord("Empty or oversized constant table") }
        var charts: [ChartID: ChartMetadata] = [:]
        for (song, entries) in source {
            guard !entries.isEmpty, entries.count <= 5 else { throw ArchiveError.invalidRecord("Unsupported chart difficulties") }
            for (index, entry) in entries.enumerated() {
                guard let entry else { continue }
                let scaled = NSDecimalNumber(decimal: entry.constant * 10)
                guard scaled.decimalValue == Decimal(scaled.intValue), (1...200).contains(scaled.intValue), let difficulty = Difficulty(rawValue: index) else {
                    throw ArchiveError.invalidRecord("Chart constants must be exact tenths from 0.1 through 20.0")
                }
                let chart = ChartMetadata(id: ChartID(songID: song, difficulty: difficulty), constant: ChartConstant(tenths: scaled.intValue), isOutdated: entry.old,
                    provenance: "Arcaea Wiki contributors; CC BY-SA 4.0; fetched \(fetchedAt.ISO8601Format())")
                try ArchiveValidation.metadata(chart)
                charts[chart.id] = chart
            }
        }
        guard !charts.isEmpty else { throw ArchiveError.invalidRecord("No constants returned") }
        return ConstantSnapshot(charts: charts, fetchedAt: fetchedAt)
    }
}

extension ArchiveStore {
    /// A complete validated snapshot replaces constants only; account scores and other metadata stay intact.
    public func replaceConstants(_ snapshot: ConstantSnapshot) throws {
        try locked {
            try database.transaction {
                let existing = try catalogUnlocked()
                for id in Set(existing.charts.keys).union(snapshot.charts.keys) {
                    let old = existing[id], fresh = snapshot.charts[id]
                    let chart = ChartMetadata(id: id, constant: fresh?.constant, isOutdated: fresh?.isOutdated ?? true,
                        level: old?.level, difficultyLabel: old?.difficultyLabel, noteCount: old?.noteCount,
                        title: old?.title, artist: old?.artist, artworkIdentifier: old?.artworkIdentifier,
                        provenance: fresh?.provenance ?? "Absent from Arcaea Wiki constant snapshot fetched \(snapshot.fetchedAt.ISO8601Format()); previous descriptive metadata retained")
                    try ArchiveValidation.metadata(chart)
                    try database.execute("INSERT INTO charts(song_id,difficulty,payload) VALUES(?,?,?) ON CONFLICT(song_id,difficulty) DO UPDATE SET payload=excluded.payload",
                        [.text(id.songID), .integer(Int64(id.difficulty.rawValue)), .blob(try encoder.encode(chart))])
                }
            }
        }
    }
}
