import CryptoKit
import Foundation
import ImageIO

/// Version 1: 8-byte magic, big-endian UInt32 count, then records containing
/// 68 ASCII filename bytes, UInt32 payload length, 32 SHA256 bytes, and image bytes.
/// Cache hashes preserve official identifiers and wiki song/difficulty mappings
/// without requiring the user's score archive or re-encoding the original images.
enum CoverBackup {
    static let maximumEntries = 12_000
    static let maximumImageBytes = 8 * 1024 * 1024
    static let maximumFileBytes = 2 * 1024 * 1024 * 1024
    private static let magic = Data("APCOV001".utf8)

    struct RestoreResult: Sendable { let imported: Int; let retained: Int }
    enum Failure: LocalizedError {
        case invalid, limit, unsafeFile, empty
        var errorDescription: String? {
            switch self {
            case .invalid: "This cover backup is damaged or unsupported. No covers were restored."
            case .limit: "The cover backup exceeds the supported size or cover count."
            case .unsafeFile: "The cover backup contains an unsafe file or filename."
            case .empty: "There are no downloaded covers to export yet."
            }
        }
    }

    static func export(from folder: URL, to output: URL) throws -> Int {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.path) else { throw Failure.empty }
        try checkDirectory(folder)
        // Enumerate incrementally so even an unexpectedly large directory is bounded.
        guard let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsSubdirectoryDescendants]) else { throw Failure.unsafeFile }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard validName(url.lastPathComponent) else { throw Failure.unsafeFile }
            _ = try regularSize(url, limit: maximumImageBytes)
            guard files.count < maximumEntries else { throw Failure.limit }
            files.append(url)
        }
        guard !files.isEmpty else { throw Failure.empty }
        guard !manager.fileExists(atPath: output.path), manager.createFile(atPath: output.path, contents: nil) else { throw Failure.unsafeFile }
        let handle = try FileHandle(forWritingTo: output)
        var completed = false
        defer { try? handle.close(); if !completed { try? manager.removeItem(at: output) } }
        try handle.write(contentsOf: magic + number(files.count))
        var total = 12
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try Task.checkCancellation()
            try autoreleasepool {
                let data = try readImage(file)
                _ = try imageQuality(data)
                total += 104 + data.count
                guard total <= maximumFileBytes else { throw Failure.limit }
                try handle.write(contentsOf: Data(file.lastPathComponent.utf8) + number(data.count) + Data(SHA256.hash(data: data)))
                try handle.write(contentsOf: data)
            }
        }
        try handle.synchronize()
        completed = true
        return files.count
    }

    static func restore(from input: URL, into folder: URL) throws -> RestoreResult {
        _ = try regularSize(input, limit: maximumFileBytes)
        let handle = try FileHandle(forReadingFrom: input)
        defer { try? handle.close() }
        guard try read(handle, count: 8) == magic else { throw Failure.invalid }
        let count = try integer(handle)
        guard count > 0, count <= maximumEntries else { throw Failure.limit }
        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appendingPathComponent("ArcProbe-cover-restore-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        var names: Set<String> = []
        var entries: [(name: String, quality: Int)] = []
        var total = 12
        for _ in 0..<count {
            try Task.checkCancellation()
            try autoreleasepool {
                let rawName = try read(handle, count: 68)
                guard let name = String(data: rawName, encoding: .ascii), validName(name), names.insert(name).inserted else { throw Failure.unsafeFile }
                let size = try integer(handle)
                guard size > 0, size <= maximumImageBytes else { throw Failure.limit }
                total += 104 + size
                guard total <= maximumFileBytes else { throw Failure.limit }
                let digest = try read(handle, count: 32)
                let bytes = try read(handle, count: size)
                guard Data(SHA256.hash(data: bytes)) == digest else { throw Failure.invalid }
                let quality = try imageQuality(bytes)
                try bytes.write(to: staging.appendingPathComponent(name), options: .atomic)
                entries.append((name, quality))
            }
        }
        guard try handle.read(upToCount: 1)?.isEmpty != false else { throw Failure.invalid }
        // No cache mutation occurs before every record and destination is validated.
        if manager.fileExists(atPath: folder.path) { try checkDirectory(folder) }
        var installing: [String] = []
        for entry in entries {
            let destination = folder.appendingPathComponent(entry.name)
            if manager.fileExists(atPath: destination.path) || (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                _ = try regularSize(destination, limit: maximumImageBytes)
                let existingQuality = autoreleasepool { try? imageQuality(readImage(destination)) }
                if let existingQuality, existingQuality >= entry.quality { continue }
            }
            installing.append(entry.name)
        }
        try Task.checkCancellation()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        // Each replacement is atomic; unrelated cache entries are never removed.
        // Disk errors may leave a partial merge, with already installed covers usable.
        for name in installing {
            try autoreleasepool {
                let bytes = try readImage(staging.appendingPathComponent(name))
                try bytes.write(to: folder.appendingPathComponent(name), options: .atomic)
            }
        }
        return RestoreResult(imported: installing.count, retained: count - installing.count)
    }

    private static func validName(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        return bytes.count == 68 && name.hasSuffix(".jpg") && bytes.prefix(64).allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func checkDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.unsafeFile }
    }
    private static func regularSize(_ url: URL, limit: Int) throws -> Int {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unsafeFile }
        guard let size = values.fileSize, size > 0, size <= limit else { throw Failure.limit }
        return size
    }
    private static func readImage(_ url: URL) throws -> Data {
        let size = try regularSize(url, limit: maximumImageBytes)
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try read(handle, count: size)
        guard try handle.read(upToCount: 1)?.isEmpty != false else { throw Failure.invalid }
        return data
    }
    private static func imageQuality(_ data: Data) throws -> Int {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...4096).contains(width), (1...4096).contains(height),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              image.width == width, image.height == height,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw Failure.invalid }
        return min(width, height)
    }
    private static func read(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let chunk = try handle.read(upToCount: count - result.count), !chunk.isEmpty else { throw Failure.invalid }
            result.append(chunk)
        }
        return result
    }
    private static func integer(_ handle: FileHandle) throws -> Int {
        try read(handle, count: 4).reduce(0) { ($0 << 8) | Int($1) }
    }
    private static func number(_ value: Int) -> Data {
        Data([UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)])
    }
}
