import Foundation
import CSQLite

public enum TrackingError: Error, Equatable, Sendable {
    case alreadyFetching, cooldown(until: Date), trackingStopped, staleGeneration, expiredLease, database
}

public struct TrackingStatus: Codable, Sendable {
    public var observer: AccountID?
    public var target: AccountID?
    public var isActive = false
    public var generation: UUID?
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    public var lastNewPlayAt: Date?
    public var lastPlayAt: Date?
    public var nextEligibleAt: Date?
    public var lastStatus: FetchStatus?
    fileprivate var lease: FetchLease?
    fileprivate var consecutiveFailures = 0
    public init() {}
}

public struct FetchLease: Codable, Sendable {
    public let id: UUID
    public let generation: UUID?
    public let expiresAt: Date
}

/// A SQLite BEGIN IMMEDIATE lease protects UI and Shortcuts even in different processes.
/// No secrets are stored here. A separate archive transaction deduplicates after process interruption.
public final class TrackingStore: @unchecked Sendable {
    private let lock = NSLock()
    private var database: OpaquePointer?
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw TrackingError.database }
        sqlite3_busy_timeout(database, 3_000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("CREATE TABLE IF NOT EXISTS tracking_state(id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL)")
        try transaction { _ in () }
    }
    deinit { sqlite3_close(database) }

    public func status() throws -> TrackingStatus {
        lock.lock(); defer { lock.unlock() }
        return try read()
    }

    @discardableResult public func start() throws -> UUID {
        let generation = UUID()
        try transaction { state in state.isActive = true; state.generation = generation }
        return generation
    }

    public func bind(configuration: RecentConfiguration?) throws {
        try transaction { state in
            let cooldown = state.nextEligibleAt
            let attempted = state.lastAttemptAt
            state = TrackingStatus()
            state.nextEligibleAt = cooldown; state.lastAttemptAt = attempted
            state.observer = configuration?.observer; state.target = configuration?.target
        }
    }

    public func stop() throws {
        try transaction { state in state.isActive = false }
    }

    public func acquire(generation: UUID?, now: Date = Date(), deadline: TimeInterval = 20) throws -> FetchLease {
        try transaction { state in
            try validateGeneration(generation, state: state)
            if let lease = state.lease, lease.expiresAt > now { throw TrackingError.alreadyFetching }
            if let next = state.nextEligibleAt, next > now { throw TrackingError.cooldown(until: next) }
            let lease = FetchLease(id: UUID(), generation: generation, expiresAt: now.addingTimeInterval(min(60, max(1, deadline)) + 5))
            state.lease = lease; state.lastAttemptAt = now; state.nextEligibleAt = now.addingTimeInterval(60)
            return lease
        }
    }

    public func finish(lease: FetchLease, status: FetchStatus, now: Date = Date(), cooldownUntil: Date? = nil) throws {
        try transaction { state in
            guard state.lease?.id == lease.id else { return }
            state.lease = nil; state.lastStatus = status
            if let until = cooldownUntil { state.nextEligibleAt = max(state.nextEligibleAt ?? now, until) }
            if [.offline, .failed, .deadlineExceeded].contains(status) {
                state.consecutiveFailures = min(5, state.consecutiveFailures + 1)
                state.nextEligibleAt = max(state.nextEligibleAt ?? now, now.addingTimeInterval(min(900, 60 * pow(2, Double(state.consecutiveFailures - 1)))))
            }
        }
    }

    /// Holds the durable lease/generation lock while the archive's single transaction executes.
    /// Returns the number of newly added observations supplied by the archive receipt.
    @discardableResult public func commit(lease: FetchLease, now: Date = Date(), latestPlay: Date? = nil, operation: () throws -> Int) throws -> Int {
        try transaction { state in
            guard state.lease?.id == lease.id, lease.expiresAt > now else { throw TrackingError.expiredLease }
            try validateGeneration(lease.generation, state: state)
            try Task.checkCancellation()
            let count = try operation()
            state.lease = nil; state.lastSuccessAt = now; state.consecutiveFailures = 0
            state.lastStatus = count > 0 ? .success : .unchanged
            if let play = latestPlay { state.lastPlayAt = max(state.lastPlayAt ?? play, play) }
            if count > 0 { state.lastNewPlayAt = latestPlay ?? now }
            return count
        }
    }

    private func validateGeneration(_ generation: UUID?, state: TrackingStatus) throws {
        guard let generation else { return }
        guard state.generation == generation else { throw TrackingError.staleGeneration }
        guard state.isActive else { throw TrackingError.trackingStopped }
    }

    private func transaction<T>(_ body: (inout TrackingStatus) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            var state = try read()
            let result = try body(&state)
            let data = try JSONEncoder().encode(state)
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO tracking_state(id,payload) VALUES(1,?)", -1, &statement, nil) == SQLITE_OK else { throw TrackingError.database }
            defer { sqlite3_finalize(statement) }
            let bind = data.withUnsafeBytes { bytes in sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard bind == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw TrackingError.database }
            try execute("COMMIT")
            return result
        } catch { try? execute("ROLLBACK"); throw error }
    }

    private func read() throws -> TrackingStatus {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM tracking_state WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw TrackingError.database }
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return TrackingStatus() }
        guard step == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw TrackingError.database }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        return try JSONDecoder().decode(TrackingStatus.self, from: data)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw TrackingError.database }
    }
}
