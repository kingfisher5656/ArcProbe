import Foundation

/// Transport proved that the write was not submitted or was rejected before application.
public struct ConsultantWriteNotSent: Error {
    public let underlying: any Error
    public init(underlying: any Error) { self.underlying = underlying }
}

@MainActor public protocol ConsultantExportRemote {
    func exportSnapshot(fileID: String, inputTab: String) async throws -> ConsultantExportSnapshot
    func writeScores(fileID: String, inputTab: String, changes: [ConsultantScoreWrite]) async throws
}
public struct ConsultantExportJournal: Codable, Sendable {
    public let fileID: String, inputTab: String, accountID: AccountID, changes: [ConsultantScoreWrite], createdAt: Date
    func validate() throws {
        guard fileID.range(of: "^[A-Za-z0-9_-]{1,200}$", options: .regularExpression) != nil,
              !inputTab.isEmpty, inputTab.utf8.count <= 1000, !accountID.rawValue.isEmpty,
              !changes.isEmpty, changes.count <= 10_000, Set(changes.map(\.row)).count == changes.count,
              createdAt.timeIntervalSince1970.isFinite,
              changes.allSatisfy({ (5...10_004).contains($0.row) && (1...100_000).contains($0.notes) && (0...10_000_000 + $0.notes).contains($0.score) && !$0.identity.isEmpty }) else { throw ConsultantExportError.layout }
    }
}
@MainActor public protocol ConsultantExportJournalStore {
    func load() throws -> ConsultantExportJournal?
    func save(_ journal: ConsultantExportJournal) throws
    func clear() throws
}
/// No retries or rollback writes: ambiguous outcomes must be inspected before another send.
@MainActor public final class ConsultantExportService {
    private let remote: any ConsultantExportRemote
    private let journal: any ConsultantExportJournalStore
    private var running = false
    public init(remote: any ConsultantExportRemote, journal: any ConsultantExportJournalStore) { self.remote = remote; self.journal = journal }
    public func send(_ plan: ConsultantExportPlan, fileID: String, inputTab: String, store: ArchiveStore,
                     validateSelection: () throws -> Void = {}) async throws -> Int {
        guard !running, try journal.load() == nil else { throw ConsultantExportError.pending }
        running = true; defer { running = false }
        let current = try await remote.exportSnapshot(fileID: fileID, inputTab: inputTab)
        let refreshed = try store.previewConsultantExport(current, accountID: plan.accountID, mode: plan.mode)
        guard current == plan.snapshot, refreshed.entries == plan.entries, refreshed.archiveScores == plan.archiveScores else { throw ConsultantExportError.stale }
        try validateSelection(); try Task.checkCancellation()
        guard !plan.changes.isEmpty else { return 0 }
        let pending = ConsultantExportJournal(fileID: fileID, inputTab: inputTab, accountID: plan.accountID, changes: plan.changes, createdAt: Date())
        try pending.validate()
        try journal.save(pending)
        do {
            try await remote.writeScores(fileID: fileID, inputTab: inputTab, changes: pending.changes)
        } catch let error as ConsultantWriteNotSent {
            try journal.clear()
            throw error.underlying
        }
        return try await verify(pending)
    }
    public func verifyPending(fileID: String) async throws -> Int {
        guard !running else { throw ConsultantExportError.pending }
        running = true; defer { running = false }
        guard let pending = try journal.load() else { return 0 }
        guard pending.fileID == fileID else { throw ConsultantExportError.selection }
        return try await verify(pending)
    }
    private func verify(_ pending: ConsultantExportJournal) async throws -> Int {
        try pending.validate()
        let snapshot = try await remote.exportSnapshot(fileID: pending.fileID, inputTab: pending.inputTab)
        let rows = Dictionary(uniqueKeysWithValues: snapshot.rows.map { ($0.number, $0) })
        guard pending.changes.allSatisfy({ change in
            guard let row = rows[change.row] else { return false }
            return row.identity == change.identity && row.localizedIdentity == change.localizedIdentity && row.notes == change.notes
                && row.raw == .number(Double(change.score)) && row.score == change.score
        }) else { throw ConsultantExportError.unverified }
        try journal.clear()
        return pending.changes.count
    }
    /// Explicit user acknowledgment only; this forgets local bookkeeping and never changes sheet cells.
    public func dismissPendingAfterReview(now: Date = Date()) throws {
        guard !running else { throw ConsultantExportError.pending }
        guard let pending = try journal.load() else { return }
        guard now.timeIntervalSince(pending.createdAt) >= 300 else { throw ConsultantExportError.tooSoon }
        try journal.clear()
    }
}

@MainActor public final class FileConsultantExportJournal: ConsultantExportJournalStore {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> ConsultantExportJournal? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 8 * 1024 * 1024 else { throw ConsultantExportError.layout }
        let result = try JSONDecoder().decode(ConsultantExportJournal.self, from: data)
        try result.validate(); return result
    }
    public func save(_ journal: ConsultantExportJournal) throws {
        try journal.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(journal).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    public func clear() throws { try FileManager.default.removeItem(at: url) }
}
