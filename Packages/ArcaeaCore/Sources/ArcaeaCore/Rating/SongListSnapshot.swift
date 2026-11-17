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
    /// Song ID to the game's `set` value: the pack the song belongs to.
    public let songPacks: [String: String]
    public let fetchedAt: Date
    /// Where the list came from; recorded on every chart it changes.
    public let source: String

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
    private struct Song: Decodable {
        let id: String
        let title_localized: [String: String]?
        let artist: String?
        let deleted: Bool?
        let set: String?
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
    public static func parse(_ data: Data, fetchedAt: Date = Date(), source: String = provenance) throws -> SongListSnapshot {
        guard data.count <= 8 * 1_024 * 1_024 else { throw ArchiveError.invalidRecord("Song list is too large") }
        let songs = try JSONDecoder().decode(Root.self, from: data).songs
        guard songs.count <= 10_000 else { throw ArchiveError.invalidRecord("Oversized song list") }
        var charts: [ChartID: Entry] = [:], songPacks: [String: String] = [:]
        for song in songs.compactMap(\.value) where song.deleted != true {
            var listed = false
            defer { if listed, let set = song.set, PackCatalog.validID(set) { songPacks[song.id] = set } }
            for chart in (song.difficulties ?? []).compactMap(\.value) {
                // A rating of 0 marks a placeholder slot, not a playable chart.
                guard let difficulty = Difficulty(rawValue: chart.ratingClass), (1...20).contains(chart.rating) else { continue }
                let id = ChartID(songID: song.id, difficulty: difficulty)
                let entry = Entry(level: "\(chart.rating)" + (chart.ratingPlus == true ? "+" : ""),
                    difficultyLabel: difficulty == .beyond && chart.ratingClassAlias == 1 ? "INS" : nil,
                    title: clean(chart.title_localized?["en"] ?? song.title_localized?["en"]),
                    artist: clean(chart.artist ?? song.artist))
                let metadata = ChartMetadata(id: id, level: entry.level, difficultyLabel: entry.difficultyLabel,
                    title: entry.title, artist: entry.artist, provenance: source)
                guard (try? ArchiveValidation.metadata(metadata)) != nil else { continue }
                charts[id] = entry; listed = true
            }
        }
        guard !charts.isEmpty else { throw ArchiveError.invalidRecord("No chart levels returned") }
        return SongListSnapshot(charts: charts, songPacks: songPacks, fetchedAt: fetchedAt, source: source)
    }

    public static let provenance = "Levels from Arcaea Wiki song list; CC BY-SA 4.0"
    public static let gameProvenance = "Levels from the song list in the Arcaea game folder"
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
        try locked { try database.transaction { try applySongListUnlocked(snapshot) } }
    }
    /// How many charts `applySongList` would change, without changing anything.
    public func songListChangeCount(_ snapshot: SongListSnapshot) throws -> Int {
        try locked { try database.transaction(write: false) { try songListChanges(snapshot).count } }
    }
    @discardableResult internal func applySongListUnlocked(_ snapshot: SongListSnapshot) throws -> Int {
        let changes = try songListChanges(snapshot)
        for chart in changes {
            try database.execute("INSERT INTO charts(song_id,difficulty,payload) VALUES(?,?,?) ON CONFLICT(song_id,difficulty) DO UPDATE SET payload=excluded.payload",
                [.text(chart.id.songID), .integer(Int64(chart.id.difficulty.rawValue)), .blob(try encoder.encode(chart))])
        }
        return changes.count
    }
    internal func songListChanges(_ snapshot: SongListSnapshot) throws -> [ChartMetadata] {
        // Read the stored rows directly: the catalog view fills missing titles from bundled aliases.
        let stored: [ChartMetadata] = try records("SELECT payload FROM charts")
        let existing = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var changes: [ChartMetadata] = []
        for (id, entry) in snapshot.charts {
            let old = existing[id]
            let oldTitle = old?.title.flatMap { $0.isEmpty || $0 == id.songID ? nil : $0 }
            var chart = ChartMetadata(id: id, constant: old?.constant, isOutdated: old?.isOutdated ?? false,
                level: entry.level, difficultyLabel: entry.difficultyLabel ?? old?.difficultyLabel, noteCount: old?.noteCount,
                title: oldTitle ?? entry.title, artist: old?.artist ?? entry.artist,
                artworkIdentifier: old?.artworkIdentifier, provenance: old?.provenance ?? snapshot.source)
            guard chart != old else { continue }
            if !chart.provenance.contains(snapshot.source) {
                chart = ChartMetadata(id: id, constant: chart.constant, isOutdated: chart.isOutdated, level: chart.level,
                    difficultyLabel: chart.difficultyLabel, noteCount: chart.noteCount, title: chart.title, artist: chart.artist,
                    artworkIdentifier: chart.artworkIdentifier, provenance: chart.provenance + "; " + snapshot.source)
            }
            try ArchiveValidation.metadata(chart)
            changes.append(chart)
        }
        return changes
    }
}
