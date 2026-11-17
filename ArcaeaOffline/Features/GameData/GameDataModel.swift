import ArcaeaCore
import Foundation
import ImageIO
import Observation

/// One pass over the chosen folder. Nothing in ArcProbe changes until the user imports.
struct GameDataReading: Sendable {
    struct Cover: Sendable, Equatable { let source: URL; let key: String; let bytes: Int }
    let playerName: String?
    let gameVersion: String?
    let plan: GameDataImportPlan
    let scoreCount: Int
    let hasSongList: Bool
    /// Names for charts ArcProbe has not seen yet, so the preview can show them before the import.
    let titles: [ChartID: String]
    let packs: [Pack]?
    let songPacks: [String: String]
    /// Jackets in the folder that ArcProbe does not have yet.
    let covers: [Cover]
    let coverTotal: Int
    var coverBytes: Int { covers.reduce(0) { $0 + $1.bytes } }
}

/// File work for the game-folder import. Runs off the main thread and only reads from the game's folder.
enum GameDataReader {
    static func read(picked: URL, store: ArchiveStore, accountID: AccountID, coverFolder: URL) throws -> GameDataReading {
        let folder = try GameDataFolder.locate(in: picked)
        let scores = try folder.scores()
        let songList = folder.songList()
        let plan = try store.previewGameDataImport(scores, songList: songList, accountID: accountID)
        let charts = Set(try store.chartCatalog().charts.keys).union(songList?.charts.keys.map { $0 } ?? [])
        var covers: [GameDataReading.Cover] = [], total = 0
        func consider(_ source: URL?, key: String) {
            guard let source, let bytes = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  bytes > 0, bytes <= CoverBackup.maximumImageBytes else { return }
            total += 1
            let saved = coverFolder.appendingPathComponent(LibraryResources.coverKey(key) + ".jpg")
            if (try? saved.resourceValues(forKeys: [.fileSizeKey]).fileSize) != bytes { covers.append(.init(source: source, key: key, bytes: bytes)) }
        }
        for songID in Set(charts.map(\.songID)).sorted() { consider(folder.songJacket(songID: songID), key: LibraryResources.gameCoverKey(songID: songID)) }
        for chart in charts.sorted(by: { $0.key < $1.key }) { consider(folder.chartJacket(for: chart), key: LibraryResources.gameCoverKey(chart)) }
        var titles: [ChartID: String] = [:]
        for (chart, entry) in songList?.charts ?? [:] { titles[chart] = entry.title }
        return GameDataReading(playerName: folder.playerName(), gameVersion: folder.gameVersion(), plan: plan, scoreCount: scores.count,
            hasSongList: songList != nil, titles: titles, packs: folder.packList(), songPacks: songList?.songPacks ?? [:], covers: covers, coverTotal: total)
    }

    /// Copies the game's image bytes unchanged. Returns how many covers were saved.
    static func copy(_ covers: [GameDataReading.Cover], into coverFolder: URL) throws -> Int {
        try FileManager.default.createDirectory(at: coverFolder, withIntermediateDirectories: true)
        var saved = 0
        for cover in covers {
            try Task.checkCancellation()
            guard let data = try? Data(contentsOf: cover.source), data.count <= CoverBackup.maximumImageBytes,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  (64...4096).contains(width), (64...4096).contains(height) else { continue }
            try data.write(to: coverFolder.appendingPathComponent(LibraryResources.coverKey(cover.key) + ".jpg"), options: .atomic)
            saved += 1
        }
        return saved
    }
}

@MainActor @Observable final class GameDataModel {
    static let shared = GameDataModel()
    private static let bookmarkKey = "gameDataFolderBookmark"
    private static let lastImportKey = "gameDataLastImport"

    private(set) var reading: GameDataReading?
    private(set) var readAccount: AccountID?
    private(set) var busy = false
    private(set) var progress = ""
    private(set) var message: String?
    private(set) var importedScoreCount = 0
    private(set) var lastImport: Date? = UserDefaults.standard.object(forKey: GameDataModel.lastImportKey) as? Date
    private(set) var hasFolder = false
    var includeCovers = true

    private enum FolderError: LocalizedError {
        case lost
        var errorDescription: String? { String(localized: "ArcProbe can no longer open the folder you chose. Choose it again.") }
    }

    init() { hasFolder = savedFolder() != nil }

    /// Remembers the folder so later imports are one tap, then reads it.
    func choose(_ url: URL, archive: ArchiveModel) async {
        let accessed = url.startAccessingSecurityScopedResource()
        let bookmark = try? url.bookmarkData()
        if accessed { url.stopAccessingSecurityScopedResource() }
        guard let bookmark else { message = FolderError.lost.localizedDescription; return }
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        hasFolder = true; reading = nil
        await refresh(archive: archive)
    }

    func refresh(archive: ArchiveModel) async {
        let account = archive.selectedAccountID ?? AccountID("local")
        importedScoreCount = (try? archive.store.gameDataScoreCount(accountID: account)) ?? 0
        guard hasFolder, !busy else { return }
        busy = true; progress = String(localized: "Reading the folder…"); defer { busy = false }
        do {
            let store = archive.store, covers = try LibraryResources.coverFolder()
            reading = try await withFolder { try GameDataReader.read(picked: $0, store: store, accountID: account, coverFolder: covers) }
            readAccount = account
        } catch {
            reading = nil
            message = error.localizedDescription
        }
    }

    func apply(archive: ArchiveModel) async {
        guard let reading, !busy else { return }
        busy = true; progress = String(localized: "Importing…")
        var summary: [String] = []
        do {
            let store = archive.store, plan = reading.plan
            let receipt = try await Task.detached(priority: .userInitiated) { try store.importGameData(plan) }.value
            summary.append(String(localized: "Added \(receipt.addedCount) scores."))
            if plan.chartChangeCount > 0 { summary.append(String(localized: "Updated song data for \(plan.chartChangeCount) charts.")) }
            LibraryResources.shared.updatePacks(packs: reading.packs, songPacks: reading.songPacks)
            if includeCovers, !reading.covers.isEmpty {
                progress = String(localized: "Copying \(reading.covers.count) covers…")
                let covers = reading.covers, folder = try LibraryResources.coverFolder()
                let saved = try await withFolder { _ in try GameDataReader.copy(covers, into: folder) }
                LibraryResources.shared.coversChanged()
                summary.append(String(localized: "Copied \(saved) covers."))
            }
            try archive.reload()
            lastImport = Date()
            UserDefaults.standard.set(lastImport, forKey: Self.lastImportKey)
            message = summary.joined(separator: " ")
        } catch {
            archive.perform { try archive.reload() }
            message = error.localizedDescription
        }
        busy = false
        await refresh(archive: archive)
    }

    func removeImported(archive: ArchiveModel) async {
        guard !busy, let account = archive.selectedAccountID else { return }
        do {
            let removed = try archive.store.removeGameDataScores(accountID: account)
            try archive.reload()
            message = String(localized: "Removed \(removed) game-folder scores.")
        } catch { message = error.localizedDescription }
        await refresh(archive: archive)
    }

    private func savedFolder() -> Data? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["ARCAEA_TEST_GAME_FOLDER"] != nil { return Data() }
        #endif
        return UserDefaults.standard.data(forKey: Self.bookmarkKey)
    }
    /// The folder belongs to another app: access is opened only for the duration of `body`.
    private func withFolder<T: Sendable>(_ body: @escaping @Sendable (URL) throws -> T) async throws -> T {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["ARCAEA_TEST_GAME_FOLDER"] {
            return try await Task.detached(priority: .userInitiated) { try body(URL(fileURLWithPath: path)) }.value
        }
        #endif
        guard let bookmark = savedFolder() else { throw GameDataError.notFound }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale) else {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            hasFolder = false
            throw FolderError.lost
        }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey) }
        return try await Task.detached(priority: .userInitiated) { try body(url) }.value
    }
}
