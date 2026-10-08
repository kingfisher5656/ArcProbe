import CryptoKit
import Foundation
import ImageIO
import UIKit

/// Serial background image preparation keeps file reads and JPEG decoding out of SwiftUI rendering.
actor CoverImageLoader {
    static let shared = CoverImageLoader()
    private let folder: URL?
    private let cache = NSCache<NSString, UIImage>()
    private var missing: Set<String> = []
    private var revision = -1
    init(folder: URL? = nil) {
        self.folder = folder ?? (try? ArchiveLocation.directory().appendingPathComponent("covers", isDirectory: true))
        cache.totalCostLimit = 48 * 1024 * 1024
    }
    func image(identifiers: [String], pixels: Int, revision: Int) -> UIImage? {
        if self.revision != revision {
            self.revision = revision
            cache.removeAllObjects(); missing.removeAll()
        }
        guard let folder else { return nil }
        let limit = min(1536, max(128, pixels))
        for identifier in identifiers {
            let key = identifier + ":" + String(limit)
            if let image = cache.object(forKey: key as NSString) { return image }
            if missing.contains(key) { continue }
            let hash = SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
            let url = folder.appendingPathComponent(hash + ".jpg")
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: limit,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else {
                if missing.count >= 2000 { missing.removeAll() }
                missing.insert(key); continue
            }
            let image = UIImage(cgImage: cg)
            cache.setObject(image, forKey: key as NSString, cost: cg.bytesPerRow * cg.height)
            return image
        }
        return nil
    }
}
