import ArcaeaCore
import CryptoKit
import Foundation
import ImageIO
import Observation
import UIKit

private final class ResourceRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

enum LibraryResourceError: Error, LocalizedError {
    case unavailable, missingCover, tooLarge, invalidImage, cooldown(Date)
    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "The public resource could not be downloaded. Existing data is retained.")
        case .tooLarge: String(localized: "The download exceeded the size limit. Existing data is retained.")
        case .missingCover: String(localized: "This cover is not available on the official asset server.")
        case .invalidImage: String(localized: "The server did not return a supported cover image.")
        case .cooldown(let date): String(localized: "The server asked us to wait until \(date.formatted(date: .omitted, time: .shortened)).")
        }
    }
}

struct PublicResourceLoader: Sendable {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config, delegate: ResourceRedirectBlocker(), delegateQueue: nil)
    }
    func load(_ url: URL, limit: Int, image: Bool = false) async throws -> Data {
        guard url.scheme == "https", ["arcaea.miraheze.org", "webassets.lowiro.com"].contains(url.host ?? ""), url.user == nil, url.password == nil else { throw LibraryResourceError.unavailable }
        var request = URLRequest(url: url)
        request.setValue("ArcProbe/\(AppInfo.shortVersion)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url == url else { throw LibraryResourceError.unavailable }
        if http.statusCode == 429 { throw LibraryResourceError.cooldown(RequestPolicy.retryDate(http.value(forHTTPHeaderField: "Retry-After"), now: Date())) }
        if image, http.statusCode == 404 { throw LibraryResourceError.missingCover }
        guard http.statusCode == 200 else { throw LibraryResourceError.unavailable }
        guard response.expectedContentLength <= limit else { throw LibraryResourceError.tooLarge }
        if image, response.mimeType?.hasPrefix("image/") != true { throw LibraryResourceError.invalidImage }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw LibraryResourceError.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }
}

@MainActor @Observable final class LibraryResources {
    static let shared = LibraryResources()
    private let loader = PublicResourceLoader()
    private let memory = NSCache<NSString, UIImage>()
    private(set) var revision = 0
    private(set) var downloading = false
    private(set) var managingCoverBackup = false
    private(set) var refreshingConstants = false
    private(set) var progress = ""
    private(set) var constantsDate: Date? = UserDefaults.standard.object(forKey: "constantsFetchedAt") as? Date
    var message: String?
    /// Which pack each song belongs to: bundled with the app, replaced by the wiki or a game folder.
    private(set) var packs: PackCatalog = LibraryResources.savedPacks()
    private var downloadTask: Task<Void, Never>?

    nonisolated static func coverKey(_ identifier: String) -> String {
        SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    /// Where a chart's cover is looked for, best first: the game's own jacket for that difficulty,
    /// the game's jacket for the song, a wiki cover, then the small official thumbnail.
    nonisolated static func coverIdentifiers(chart: ChartID, official: String?) -> [String] {
        [gameCoverKey(chart), gameCoverKey(songID: chart.songID), "wiki:\(chart.songID):\(chart.difficulty.rawValue)"] + (official.map { [$0] } ?? [])
    }
    nonisolated static func gameCoverKey(_ chart: ChartID) -> String { "game:\(chart.songID):\(chart.difficulty.rawValue)" }
    nonisolated static func gameCoverKey(songID: String) -> String { "game:\(songID)" }
    nonisolated static func coverFolder() throws -> URL {
        let folder = try ArchiveLocation.directory().appendingPathComponent("covers", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    /// Call after cover files were written outside this class.
    func coversChanged() { memory.removeAllObjects(); revision += 1 }
    func hasGameCover(_ chart: ChartID) -> Bool {
        guard let folder = try? Self.coverFolder() else { return false }
        return [Self.gameCoverKey(chart), Self.gameCoverKey(songID: chart.songID)].contains {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent(Self.coverKey($0) + ".jpg").path)
        }
    }
    static func coverURL(_ identifier: String) -> URL? {
        guard ArtworkPolicy.validIdentifier(identifier) else { return nil }
        return URL(string: "https://webassets.lowiro.com/\(identifier).jpg")
    }
    private func file(_ identifier: String) throws -> URL {
        try Self.coverFolder().appendingPathComponent(Self.coverKey(identifier) + ".jpg")
    }
    func image(for identifier: String?) -> UIImage? {
        guard let identifier else { return nil }
        let key = Self.coverKey(identifier) as NSString
        if let cached = memory.object(forKey: key) { return cached }
        guard let url = try? file(identifier), let image = UIImage(contentsOfFile: url.path) else { return nil }
        memory.totalCostLimit = 48 * 1024 * 1024
        memory.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        return image
    }
    private func wikiKey(_ chart: ChartID) -> String { "wiki:\(chart.songID):\(chart.difficulty.rawValue)" }
    func hasWikiCover(_ chart: ChartID) -> Bool { image(for: wikiKey(chart)) != nil }
    func image(chart: ChartID, officialIdentifier: String?) -> UIImage? {
        Self.coverIdentifiers(chart: chart, official: officialIdentifier).lazy.compactMap { self.image(for: $0) }.first
    }
    func saveWikiCover(_ data: Data, chart: ChartID) throws {
        guard data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (256...4096).contains(width), (256...4096).contains(height),
              UIImage(data: data) != nil else { throw LibraryResourceError.invalidImage }
        let key = wikiKey(chart)
        if let current = image(for: key), let cg = current.cgImage, min(cg.width, cg.height) > min(width, height) { return }
        // Preserve the original image bytes; do not upscale or re-encode a thumbnail.
        try data.write(to: file(key), options: .atomic)
        memory.removeObject(forKey: Self.coverKey(key) as NSString)
        revision += 1
    }
    private nonisolated static func packFile() throws -> URL { try ArchiveLocation.directory().appendingPathComponent("pack-catalog.json") }
    private nonisolated static func savedPacks() -> PackCatalog {
        let bundled = PackCatalog.bundled()
        guard let file = try? packFile(), let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode(PackCatalog.self, from: data) else { return bundled }
        // A newer app can ship a newer pack list than the one saved by an older update.
        return bundled.merging(packs: saved.packs.count >= bundled.packs.count ? saved.packs : nil, songPacks: saved.songPacks)
    }
    func updatePacks(packs newPacks: [Pack]?, songPacks: [String: String]) {
        let merged = packs.merging(packs: newPacks, songPacks: songPacks)
        guard merged != packs else { return }
        packs = merged
        if let file = try? Self.packFile(), let data = try? JSONEncoder().encode(merged) { try? data.write(to: file, options: .atomic) }
    }
    /// Downloads chart constants, then levels, names and packs for charts the app has not seen yet.
    func refreshChartData(store: ArchiveStore) async throws {
        guard !refreshingConstants else { return }
        refreshingConstants = true; defer { refreshingConstants = false }
        try checkCooldown("constantsCooldown")
        do {
            let data = try await loader.load(URL(string: "https://arcaea.miraheze.org/wiki/Data:ChartConstant.json?action=raw")!, limit: 8 * 1024 * 1024)
            let snapshot = try await Task.detached { try ConstantSnapshot.parse(data) }.value
            try await Task.detached { try store.replaceConstants(snapshot) }.value
            constantsDate = snapshot.fetchedAt
            UserDefaults.standard.set(snapshot.fetchedAt, forKey: "constantsFetchedAt")
            // Constants are already saved; a problem with the song list only costs the levels.
            do {
                let list = try await loader.load(URL(string: "https://arcaea.miraheze.org/wiki/Data:Songlist.json?action=raw")!, limit: 8 * 1024 * 1024)
                let levels = try await Task.detached { try SongListSnapshot.parse(list) }.value
                try await Task.detached { try store.applySongList(levels) }.value
                // Songs already carry their pack ID; only the pack names depend on this last download.
                var packList: [Pack]?
                do {
                    let data = try await loader.load(URL(string: "https://arcaea.miraheze.org/wiki/Data:Packlist.json?action=raw")!, limit: 2 * 1024 * 1024)
                    packList = try await Task.detached { try PackCatalog.parsePackList(data) }.value
                } catch { saveCooldown(error, key: "constantsCooldown") }
                updatePacks(packs: packList, songPacks: levels.songPacks)
                message = packList == nil ? String(localized: "Updated constants and levels for \(levels.charts.count) charts. Pack names could not be updated.")
                    : String(localized: "Updated constants, levels and packs for \(levels.charts.count) charts.")
            } catch {
                saveCooldown(error, key: "constantsCooldown")
                message = String(localized: "Updated \(snapshot.charts.count) chart constants. Levels could not be updated: \(error.localizedDescription)")
            }
        } catch { saveCooldown(error, key: "constantsCooldown"); throw error }
    }
    func downloadCovers(charts: [ChartMetadata], refresh: Bool = false) {
        guard !downloading, !managingCoverBackup else { return }
        downloading = true; message = nil
        let identifiers = Set(charts.compactMap(\.artworkIdentifier)).sorted()
        downloadTask = Task {
            defer { downloading = false; downloadTask = nil }
            do {
                try checkCooldown("coverCooldown")
                var saved = 0
                var missing = 0
                for (index, identifier) in identifiers.enumerated() {
                    try Task.checkCancellation()
                    guard let url = Self.coverURL(identifier) else { continue }
                    let destination = try file(identifier)
                    if !refresh, FileManager.default.fileExists(atPath: destination.path) { continue }
                    progress = String(localized: "Cover \(index + 1) of \(identifiers.count)")
                    do {
                        let bytes = try await loader.load(url, limit: 4 * 1024 * 1024, image: true)
                        let thumbnail = try Self.thumbnail(bytes)
                        try Task.checkCancellation()
                        try thumbnail.write(to: destination, options: .atomic)
                        memory.removeObject(forKey: Self.coverKey(identifier) as NSString)
                        revision += 1; saved += 1
                    } catch LibraryResourceError.missingCover { missing += 1 }
                    catch LibraryResourceError.invalidImage { missing += 1 }
                    try await Task.sleep(for: .seconds(0.5))
                }
                message = identifiers.isEmpty ? String(localized: "No official cover identifiers yet. Import your main account’s scores first.") : String(localized: "Saved \(saved) covers; \(missing) unavailable. Previously cached covers retained.")
            } catch is CancellationError { message = String(localized: "Cover download cancelled. Completed covers are retained.") }
            catch { saveCooldown(error, key: "coverCooldown"); message = error.localizedDescription }
        }
    }
    func exportCoverBackup() async throws -> URL {
        guard !managingCoverBackup, !downloading else { throw LibraryResourceError.unavailable }
        managingCoverBackup = true
        defer { managingCoverBackup = false }
        let folder = try ArchiveLocation.directory().appendingPathComponent("covers", isDirectory: true)
        return try await Task.detached(priority: .userInitiated) {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ArcProbe-cover-export-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            do {
                let output = temporary.appendingPathComponent("ArcProbe-covers.arcprobe-covers")
                _ = try CoverBackup.export(from: folder, to: output)
                return output
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
        }.value
    }
    func restoreCoverBackup(from input: URL) async throws {
        guard !managingCoverBackup, !downloading else { throw LibraryResourceError.unavailable }
        managingCoverBackup = true
        // Invalidate even on a disk error after a partially completed merge.
        defer { managingCoverBackup = false; memory.removeAllObjects(); revision += 1 }
        let folder = try ArchiveLocation.directory().appendingPathComponent("covers", isDirectory: true)
        let result = try await Task.detached(priority: .userInitiated) {
            let accessed = input.startAccessingSecurityScopedResource()
            defer { if accessed { input.stopAccessingSecurityScopedResource() } }
            return try CoverBackup.restore(from: input, into: folder)
        }.value
        message = String(localized: "Restored \(result.imported) covers; kept \(result.retained) existing covers of equal or higher resolution.")
    }
    func cancelDownload() { downloadTask?.cancel() }
    static func thumbnail(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(width), (1...4096).contains(height),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary),
              let encoded = UIImage(cgImage: cg).jpegData(compressionQuality: 0.9) else { throw LibraryResourceError.invalidImage }
        return encoded
    }
    private func checkCooldown(_ key: String) throws {
        if let date = UserDefaults.standard.object(forKey: key) as? Date, date > Date() { throw LibraryResourceError.cooldown(date) }
    }
    private func saveCooldown(_ error: Error, key: String) {
        if case LibraryResourceError.cooldown(let date) = error { UserDefaults.standard.set(date, forKey: key) }
    }
}
