import ArcaeaCore
import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Public portrait assets use a separate cookie-free request and an on-disk cache.
actor PartnerArtworkLoader {
    static let shared = PartnerArtworkLoader()
    private let folder: URL?
    private let download: @Sendable (URL) async throws -> Data
    private static let maximumBytes = 2 * 1024 * 1024

    init(folder: URL? = nil, download: @escaping @Sendable (URL) async throws -> Data = {
        try await PublicResourceLoader().load($0, limit: 2 * 1024 * 1024, image: true)
    }) {
        self.folder = folder ?? (try? ArchiveLocation.directory().appendingPathComponent("partners", isDirectory: true))
        self.download = download
    }
    static func url(for identifier: String) -> URL? {
        guard AccountProfile.validPartnerIcon(identifier) else { return nil }
        return URL(string: "https://webassets.lowiro.com/chr/\(identifier).png")
    }
    func image(identifier: String?) async -> UIImage? {
        guard let identifier, let url = Self.url(for: identifier) else { return nil }
        let key = SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = folder?.appendingPathComponent(key + ".png")
        if let file, let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size <= Self.maximumBytes, let data = try? Data(contentsOf: file), let image = Self.decode(data) { return image }
        do {
            try Task.checkCancellation()
            let data = try await download(url)
            try Task.checkCancellation()
            guard let image = Self.decode(data) else { return nil }
            if let folder, let file {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? data.write(to: file, options: .atomic)
            }
            return image
        } catch { return nil }
    }
    private static func decode(_ data: Data) -> UIImage? {
        guard data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = info[kCGImagePropertyPixelWidth] as? Int, let height = info[kCGImagePropertyPixelHeight] as? Int,
              (16...2048).contains(width), (16...2048).contains(height),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 280,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
