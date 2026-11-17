import Foundation
import CSQLite

public enum GameDataError: Error, LocalizedError, Equatable {
    case notFound, unreadableScores, stalePreview
    public var errorDescription: String? {
        switch self {
        case .notFound: localized("No Arcaea data was found in this folder. Choose the folder that holds Arcaea's Documents and Library folders, or a folder above it.")
        case .unreadableScores: localized("Arcaea's score file in this folder could not be read. Open Arcaea once, then try again.")
        case .stalePreview: localized("Your scores changed after this folder was read. Read the folder again before importing.")
        }
    }
}

/// One chart best as the game keeps it on the device. The game's date column is unreliable and is not read.
public struct GameScore: Hashable, Sendable {
    public let chartID: ChartID
    public let score: Int
    public let judgments: Judgments?
    public let bestClear: ClearType?
    public let modifier: Int?
    public let health: Int?
    public init(chartID: ChartID, score: Int, judgments: Judgments? = nil, bestClear: ClearType? = nil,
                modifier: Int? = nil, health: Int? = nil) {
        self.chartID = chartID; self.score = score; self.judgments = judgments
        self.bestClear = bestClear; self.modifier = modifier; self.health = health
    }
}

/// Arcaea's data container: `Documents/st3` holds the scores, `Library/Application Support/cb/active/songs`
/// the song list and jackets. Everything here only reads.
public struct GameDataFolder: Sendable {
    public let root: URL
    private let scoreFile: URL
    private var songs: URL { root.appendingPathComponent("Library/Application Support/cb/active/songs", isDirectory: true) }

    /// Accepts the container itself, its Documents folder, or a folder up to three levels above the container.
    public static func locate(in picked: URL) throws -> GameDataFolder {
        let manager = FileManager.default
        func container(_ url: URL) -> GameDataFolder? {
            let file = url.appendingPathComponent("Documents/st3")
            return manager.fileExists(atPath: file.path) ? GameDataFolder(root: url, scoreFile: file) : nil
        }
        if let found = container(picked) { return found }
        let inside = picked.appendingPathComponent("st3")
        if picked.lastPathComponent == "Documents", manager.fileExists(atPath: inside.path) {
            return GameDataFolder(root: picked.deletingLastPathComponent(), scoreFile: inside)
        }
        var level = [picked], examined = 0
        for _ in 0..<3 {
            var next: [URL] = [], found: [GameDataFolder] = []
            for folder in level {
                let children = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    examined += 1
                    guard examined <= 2_000 else { break }
                    if let match = container(child) { found.append(match) } else { next.append(child) }
                }
            }
            if let best = found.max(by: { $0.rank < $1.rank }) { return best }
            level = next
        }
        throw GameDataError.notFound
    }
    /// With several containers, prefer the one LiveContainer labels as Arcaea, then the most recently played.
    private var rank: (Int, Date) {
        let info = (try? Data(contentsOf: root.appendingPathComponent("LCContainerInfo.plist")))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let modified = (try? scoreFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return ((info?["appIdentifier"] as? String) == "moe.low.arc" ? 1 : 0, modified)
    }

    /// Reads a private copy, so the game's own file is never opened or locked.
    public func scores() throws -> [GameScore] {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent("arcprobe-st3-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("st3")
        do {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: scoreFile.path + suffix)
                guard manager.fileExists(atPath: source.path) else { continue }
                let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 64 * 1_024 * 1_024 else { throw GameDataError.unreadableScores }
                try manager.copyItem(at: source, to: URL(fileURLWithPath: copy.path + suffix))
            }
        } catch { throw GameDataError.unreadableScores }
        var handle: OpaquePointer?
        defer { sqlite3_close_v2(handle) }
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { throw GameDataError.unreadableScores }
        let columns = "s.songId, s.songDifficulty, s.score, s.shinyPerfectCount, s.perfectCount, s.nearCount, s.missCount, s.modifier, s.health"
        let lamp = "(SELECT c.clearType FROM cleartypes c WHERE c.songId=s.songId AND c.songDifficulty=s.songDifficulty ORDER BY c.id DESC LIMIT 1)"
        var statement: OpaquePointer?
        // Older score files may have no clear-lamp table; the scores are still usable.
        if sqlite3_prepare_v2(handle, "SELECT \(columns), \(lamp) FROM scores s ORDER BY s.id", -1, &statement, nil) != SQLITE_OK {
            guard sqlite3_prepare_v2(handle, "SELECT \(columns), NULL FROM scores s ORDER BY s.id", -1, &statement, nil) == SQLITE_OK else {
                throw GameDataError.unreadableScores
            }
        }
        defer { sqlite3_finalize(statement) }
        var best: [ChartID: GameScore] = [:], rows = 0
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW, rows < 100_000 else { throw GameDataError.unreadableScores }
            rows += 1
            func int(_ column: Int32) -> Int? {
                sqlite3_column_type(statement, column) == SQLITE_INTEGER ? Int(exactly: sqlite3_column_int64(statement, column)) : nil
            }
            guard let text = sqlite3_column_text(statement, 0), let rawDifficulty = int(1), let difficulty = Difficulty(rawValue: rawDifficulty),
                  let score = int(2), (1...10_100_000).contains(score) else { continue }
            let chart = ChartID(songID: String(cString: text), difficulty: difficulty)
            guard (try? ArchiveValidation.chartID(chart)) != nil else { continue }
            var judgments: Judgments?
            if let shiny = int(3), let pure = int(4), let far = int(5), let lost = int(6),
               [shiny, pure, far, lost].allSatisfy({ (0...100_000).contains($0) }), shiny <= pure {
                judgments = Judgments(pure: pure, shinyPure: shiny, far: far, lost: lost)
            }
            let entry = GameScore(chartID: chart, score: score, judgments: judgments,
                bestClear: int(9).flatMap(ClearType.init(rawValue:)),
                modifier: int(7).flatMap { (0...65_535).contains($0) ? $0 : nil },
                health: int(8).flatMap { (0...100).contains($0) ? $0 : nil })
            if (best[chart]?.score ?? 0) < score { best[chart] = entry }
        }
        return best.values.sorted { $0.chartID.key < $1.chartID.key }
    }

    /// The game's own song list, when this folder holds downloaded game content.
    public func songList(fetchedAt: Date = Date()) -> SongListSnapshot? {
        guard let data = small(songs.appendingPathComponent("songlist"), limit: 8 * 1_024 * 1_024) else { return nil }
        return try? SongListSnapshot.parse(data, fetchedAt: fetchedAt, source: SongListSnapshot.gameProvenance)
    }
    /// The game's own pack list, when present.
    public func packList() -> [Pack]? {
        small(songs.appendingPathComponent("packlist"), limit: 2 * 1_024 * 1_024).flatMap { try? PackCatalog.parsePackList($0) }
    }
    /// The player name the game last signed in with. Nothing else is read from the game's settings.
    public func playerName() -> String? {
        guard let data = small(root.appendingPathComponent("Library/Preferences/moe.low.arc.plist"), limit: 4 * 1_024 * 1_024),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = (values["lastLoggedInUsername"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, name.utf8.count <= 200 else { return nil }
        return name
    }
    public func gameVersion() -> String? {
        guard let data = small(root.appendingPathComponent("Library/Application Support/cb/meta.cb"), limit: 16 * 1_024 * 1_024),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = values["versionNumber"] as? String,
              version.range(of: "^[0-9][0-9A-Za-z.]{0,19}$", options: .regularExpression) != nil else { return nil }
        return version
    }
    /// The jacket shared by a song's charts.
    public func songJacket(songID: String) -> URL? { jacket(songID: songID, names: ["1080_base.jpg", "base.jpg"]) }
    /// A jacket of its own for one difficulty (for example a Beyond chart with different art), if the game has one.
    public func chartJacket(for chart: ChartID) -> URL? {
        jacket(songID: chart.songID, names: ["1080_\(chart.difficulty.rawValue).jpg", "\(chart.difficulty.rawValue).jpg"])
    }
    private func jacket(songID: String, names: [String]) -> URL? {
        guard (try? ArchiveValidation.chartID(ChartID(songID: songID, difficulty: .past))) != nil else { return nil }
        for folder in ["dl_" + songID, songID] {
            for name in names {
                let url = songs.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }
    private func small(_ url: URL, limit: Int) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= limit else { return nil }
        return try? Data(contentsOf: url)
    }
}
