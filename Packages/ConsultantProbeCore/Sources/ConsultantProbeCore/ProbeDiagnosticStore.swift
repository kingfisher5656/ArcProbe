import Foundation

/// Stores only caller-sanitized status lines, never auth state or raw HTTP/browser data.
public struct ProbeDiagnosticStore {
    public let reportURL: URL
    private let directory: URL
    private var historyURL: URL { directory.appendingPathComponent("events.json") }
    public init(directory: URL) {
        self.directory = directory
        reportURL = directory.appendingPathComponent("diagnostic-report.txt")
    }
    public func loadLines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return [] }
        return Array(try JSONDecoder().decode([String].self, from: Data(contentsOf: historyURL)).suffix(50))
    }
    public func save(lines: [String], report: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        try JSONEncoder().encode(Array(lines.suffix(50))).write(to: historyURL, options: options)
        try Data(report.utf8).write(to: reportURL, options: options)
    }
}
