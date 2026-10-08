import Foundation

enum ArchiveLocation {
    static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("ArcaeaOffline", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    static func url() throws -> URL {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["ARCAEA_TEST_ARCHIVE"], UUID(uuidString: name) != nil {
            return try directory().appendingPathComponent("test-" + name + ".sqlite")
        }
        #endif
        return try directory().appendingPathComponent("archive.sqlite")
    }
}
