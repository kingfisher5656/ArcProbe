import Foundation

/// Levels (7, 9+, 11…) and names read from the Arcaea Wiki copy of the game's song list.
public struct SongListSnapshot: Sendable {
    public struct Entry: Sendable, Equatable {
        public let level: String
        public let difficultyLabel: String?
        public let title: String?
        public let artist: String?
    }
    public let charts: [ChartID: Entry]
    public let fetchedAt: Date

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
    private struct Song: Decodable {
        let id: String
        let title_localized: [String: String]?
        let artist: String?
        let deleted: Bool?
        let difficulties: [Lossy<Chart>]?
    }
    private struct Chart: Decodable {
        let ratingClass: Int
        let rating: Int
        let ratingPlus: Bool?
        let ratingClassAlias: Int?
        let title_localized: [String: String]?
        let artist: String?
    }
    private struct Root: Decodable { let songs: [Lossy<Song>] }

    /// Entries the app cannot read are skipped, so one unusual song never blocks the rest.
    public static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> SongListSnapshot {
        guard data.count <= 8 * 1_024 * 1_024 else { throw ArchiveError.invalidRecord("Song list is too large") }
        let songs = try JSONDecoder().decode(Root.self, from: data).songs
        guard songs.count <= 10_000 else { throw ArchiveError.invalidRecord("Oversized song list") }
        var charts: [ChartID: Entry] = [:]
        for song in songs.compactMap(\.value) where song.deleted != true {
            for chart in (song.difficulties ?? []).compactMap(\.value) {
                // A rating of 0 marks a placeholder slot, not a playable chart.
                guard let difficulty = Difficulty(rawValue: chart.ratingClass), (1...20).contains(chart.rating) else { continue }
                let id = ChartID(songID: song.id, difficulty: difficulty)
                let entry = Entry(level: "\(chart.rating)" + (chart.ratingPlus == true ? "+" : ""),
                    difficultyLabel: difficulty == .beyond && chart.ratingClassAlias == 1 ? "INS" : nil,
                    title: clean(chart.title_localized?["en"] ?? song.title_localized?["en"]),
                    artist: clean(chart.artist ?? song.artist))
                let metadata = ChartMetadata(id: id, level: entry.level, difficultyLabel: entry.difficultyLabel,
                    title: entry.title, artist: entry.artist, provenance: provenance)
                guard (try? ArchiveValidation.metadata(metadata)) != nil else { continue }
                charts[id] = entry
            }
        }
        guard !charts.isEmpty else { throw ArchiveError.invalidRecord("No chart levels returned") }
        return SongListSnapshot(charts: charts, fetchedAt: fetchedAt)
    }

    static let provenance = "Levels from Arcaea Wiki song list; CC BY-SA 4.0"
    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

extension ArchiveStore {
    /// Sets the level of every listed chart and adds charts the archive has not seen yet.
    /// Titles and artists only fill gaps: names from the official site are kept.
    /// Returns how many charts changed.
    @discardableResult public func applySongList(_ snapshot: SongListSnapshot) throws -> Int {
        try locked {
            try database.transaction {
                // Read the stored rows directly: the catalog view fills missing titles from bundled aliases.
                let stored: [ChartMetadata] = try records("SELECT payload FROM charts")
                let existing = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                var changed = 0
                for (id, entry) in snapshot.charts {
                    let old = existing[id]
                    let oldTitle = old?.title.flatMap { $0.isEmpty || $0 == id.songID ? nil : $0 }
                    var chart = ChartMetadata(id: id, constant: old?.constant, isOutdated: old?.isOutdated ?? false,
                        level: entry.level, difficultyLabel: entry.difficultyLabel ?? old?.difficultyLabel, noteCount: old?.noteCount,
                        title: oldTitle ?? entry.title, artist: old?.artist ?? entry.artist,
                        artworkIdentifier: old?.artworkIdentifier, provenance: old?.provenance ?? SongListSnapshot.provenance)
                    guard chart != old else { continue }
                    if !chart.provenance.contains(SongListSnapshot.provenance) {
                        chart = ChartMetadata(id: id, constant: chart.constant, isOutdated: chart.isOutdated, level: chart.level,
                            difficultyLabel: chart.difficultyLabel, noteCount: chart.noteCount, title: chart.title, artist: chart.artist,
                            artworkIdentifier: chart.artworkIdentifier, provenance: chart.provenance + "; " + SongListSnapshot.provenance)
                    }
                    try ArchiveValidation.metadata(chart)
                    try database.execute("INSERT INTO charts(song_id,difficulty,payload) VALUES(?,?,?) ON CONFLICT(song_id,difficulty) DO UPDATE SET payload=excluded.payload",
                        [.text(id.songID), .integer(Int64(id.difficulty.rawValue)), .blob(try encoder.encode(chart))])
                    changed += 1
                }
                return changed
            }
        }
    }
}
