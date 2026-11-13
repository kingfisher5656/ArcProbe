import Foundation

public enum ProbeError: Error, LocalizedError {
    case restricted, pending, unsupported, conflict, restorationPending, uncertainWrite, uncertainRestore, busy, invalidSelection
    public var errorDescription: String? {
        switch self {
        case .restricted: "Temporary writes are allowed only on the designated disposable test workbook."
        case .pending: "A previous test needs restoration before another test can start."
        case .unsupported: "The expected chart, empty score, or workbook layout changed. Check any pending recovery before retrying."
        case .conflict: "The test cell or chart changed. Restore the original score manually in Google Sheets, then check recovery again."
        case .restorationPending: "Restoration has not been verified. Keep this app installed and use Check / restore pending test."
        case .uncertainWrite: "The timed-out write has not been observed on the server. Recovery remains pending; retry later. If the score stays at 0, report this result before clearing the recovery record."
        case .uncertainRestore: "A restoration request timed out and may still complete. The recovery record is retained. Keep other editors closed and share the diagnostic report before further tests."
        case .busy: "A sheet operation is already running."
        case .invalidSelection: "Google did not return exactly one valid spreadsheet selection. Please try selecting again."
        }
    }
}
public struct ProbeSnapshot: Codable, Equatable, Sendable {
    public var input: Double
    public var decoded: Double?
    public var rating: Double?
    public var priority: Double?
    public var identity: String
    public init(input: Double, decoded: Double?, rating: Double?, priority: Double?, identity: String = "Sayonara Hatsukoi [PST]") {
        self.input = input; self.decoded = decoded; self.rating = rating; self.priority = priority; self.identity = identity
    }
}
public struct ProbeJournal: Codable, Sendable {
    public let fileID: String
    public let inputTab: String
    public let baseline: ProbeSnapshot
    public var writeResolved = false
    public var restoreUnresolved = false
    public init(fileID: String, inputTab: String, baseline: ProbeSnapshot) {
        self.fileID = fileID; self.inputTab = inputTab; self.baseline = baseline
    }
}
@MainActor public protocol ProbeSheet {
    func snapshot(fileID: String, inputTab: String) async throws -> ProbeSnapshot
    func write(fileID: String, inputTab: String, value: Double) async throws
}
@MainActor public protocol ProbeJournalStore {
    func load() throws -> ProbeJournal?
    func save(_ journal: ProbeJournal) throws
    func clear() throws
}
@MainActor public final class ProbeRunner {
    public static let testFileID = "1qdhEGNs4hBTrfYUEAiUqaQNI-L9zHmaAjgmWGa7uRcc"
    public static let testScore: Double = 9_975_813
    private let sheet: any ProbeSheet
    private let journal: any ProbeJournalStore
    private let pause: @MainActor () async throws -> Void
    private var running = false
    public init(sheet: any ProbeSheet, journal: any ProbeJournalStore,
                pause: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(3)) }) {
        self.sheet = sheet; self.journal = journal; self.pause = pause
    }
    public func run(fileID: String, inputTab: String) async throws -> Bool {
        guard !running else { throw ProbeError.busy }
        running = true; defer { running = false }
        guard try journal.load() == nil else { throw ProbeError.pending }
        guard fileID == Self.testFileID else { throw ProbeError.restricted }
        let baseline = try await sheet.snapshot(fileID: fileID, inputTab: inputTab)
        guard baseline.identity == "Sayonara Hatsukoi [PST]", baseline.input == 0,
              baseline.decoded == 0, baseline.rating == 0, baseline.priority != nil else { throw ProbeError.unsupported }
        // A second read narrows the race with another editor; Sheets has no cell compare-and-swap.
        guard try await sheet.snapshot(fileID: fileID, inputTab: inputTab) == baseline else { throw ProbeError.conflict }
        var entry = ProbeJournal(fileID: fileID, inputTab: inputTab, baseline: baseline)
        try journal.save(entry) // Must be durable BEFORE a potentially ambiguous network write.
        try await sheet.write(fileID: fileID, inputTab: inputTab, value: Self.testScore)
        entry.writeResolved = true
        try journal.save(entry)
        var passed = false
        for attempt in 0..<5 {
            if attempt > 0 { try await pause() }
            let current = try await sheet.snapshot(fileID: fileID, inputTab: inputTab)
            guard current.identity == baseline.identity, current.input == Self.testScore else { throw ProbeError.conflict }
            if current.decoded == Self.testScore, let rating = current.rating, abs(rating - 3.579065) < 0.000001,
               current.priority != nil, current.priority != baseline.priority {
                passed = true; break
            }
        }
        try await restoreEntry(entry)
        return passed
    }
    public func restore() async throws {
        guard !running else { throw ProbeError.busy }
        running = true; defer { running = false }
        guard let entry = try journal.load() else { return }
        try await restoreEntry(entry)
    }
    private func restoreEntry(_ entry: ProbeJournal) async throws {
        guard !entry.restoreUnresolved else { throw ProbeError.uncertainRestore }
        guard entry.fileID == Self.testFileID, entry.baseline.input == 0,
              entry.baseline.identity == "Sayonara Hatsukoi [PST]" else { throw ProbeError.restricted }
        let current = try await sheet.snapshot(fileID: entry.fileID, inputTab: entry.inputTab)
        guard current.identity == entry.baseline.identity,
              current.input == Self.testScore || current.input == entry.baseline.input else { throw ProbeError.conflict }
        if current.input == Self.testScore {
            var resolved = entry; resolved.writeResolved = true; resolved.restoreUnresolved = true
            try journal.save(resolved)
            try await sheet.write(fileID: entry.fileID, inputTab: entry.inputTab, value: entry.baseline.input)
            resolved.restoreUnresolved = false
            try journal.save(resolved)
        } else if !entry.writeResolved {
            // Baseline alone cannot prove that a timed-out POST will not commit later.
            // Preserve this journal until the test write is observed or manually investigated.
            throw ProbeError.uncertainWrite
        }
        for attempt in 0..<5 {
            if attempt > 0 { try await pause() }
            let restored = try await sheet.snapshot(fileID: entry.fileID, inputTab: entry.inputTab)
            if restored == entry.baseline { try journal.clear(); return }
        }
        throw ProbeError.restorationPending
    }
}

@MainActor public final class FileProbeJournal: ProbeJournalStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> ProbeJournal? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ProbeJournal.self, from: Data(contentsOf: url))
    }
    public func save(_ journal: ProbeJournal) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(journal).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    public func clear() throws { try FileManager.default.removeItem(at: url) }
}
