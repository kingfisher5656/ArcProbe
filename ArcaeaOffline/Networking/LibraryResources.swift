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
        case .unavailable: "The public resource could not be downloaded. Existing data is retained."
        case .tooLarge: "The download exceeded the size limit. Existing data is retained."
        case .missingCover: "This cover is not available on the official asset server."
        case .invalidImage: "The server did not return a supported cover image."
        case .cooldown(let date): "The server asked us to wait until \(date.formatted(date: .omitted, time: .shortened))."
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
        request.setValue("ArcProbe/0.2", forHTTPHeaderField: "User-Agent")
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
    private(set) var refreshingConstants = false
    private(set) var progress = ""
    private(set) var constantsDate: Date? = UserDefaults.standard.object(forKey: "constantsFetchedAt") as? Date
    var message: String?
    private var downloadTask: Task<Void, Never>?

    static func coverKey(_ identifier: String) -> String {
        SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func coverURL(_ identifier: String) -> URL? {
        guard ArtworkPolicy.validIdentifier(identifier) else { return nil }
        return URL(string: "https://webassets.lowiro.com/\(identifier).jpg")
    }
    private func file(_ identifier: String) throws -> URL {
        let folder = try ArchiveLocation.directory().appendingPathComponent("covers", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(Self.coverKey(identifier) + ".jpg")
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
    func refreshConstants(store: ArchiveStore) async throws {
        guard !refreshingConstants else { return }
        refreshingConstants = true; defer { refreshingConstants = false }
        try checkCooldown("constantsCooldown")
        do {
            let data = try await loader.load(URL(string: "https://arcaea.miraheze.org/wiki/Data:ChartConstant.json?action=raw")!, limit: 8 * 1024 * 1024)
            let snapshot = try await Task.detached { try ConstantSnapshot.parse(data) }.value
            try await Task.detached { try store.replaceConstants(snapshot) }.value
            constantsDate = snapshot.fetchedAt
            UserDefaults.standard.set(snapshot.fetchedAt, forKey: "constantsFetchedAt")
            message = "Updated \(snapshot.charts.count) chart constants."
        } catch { saveCooldown(error, key: "constantsCooldown"); throw error }
    }
    func downloadCovers(charts: [ChartMetadata], refresh: Bool = false) {
        guard !downloading else { return }
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
                    progress = "Cover \(index + 1) of \(identifiers.count)"
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
                message = identifiers.isEmpty ? "No official cover identifiers yet. Import your main account’s scores first." : "Saved \(saved) covers; \(missing) unavailable. Previously cached covers retained."
            } catch is CancellationError { message = "Cover download cancelled. Completed covers are retained." }
            catch { saveCooldown(error, key: "coverCooldown"); message = error.localizedDescription }
        }
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
