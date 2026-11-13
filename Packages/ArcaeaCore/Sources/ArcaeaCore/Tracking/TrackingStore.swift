import Foundation
import CSQLite

public enum TrackingError: Error, Equatable, Sendable {
    case alreadyFetching, cooldown(until: Date), expiredLease, database
}

/// Timing rules for the Shortcut polling loop. The app owns the schedule; the Shortcut only waits.
public enum TrackingPolicy {
    /// Normal spacing between two recent-play requests while Arcaea is open.
    public static let pollInterval: ClosedRange<TimeInterval> = 65...80
    /// Extra checks after Arcaea closes, so a play uploaded right before closing is still caught.
    public static let closingPolls = 2
    public static let closingInterval: TimeInterval = 60
    /// A closing loop never outlives this, even when the server keeps asking us to wait.
    public static let closingLimit: TimeInterval = 600
    /// Soft failures (bad gateway pages, schema hiccups) only lock the account after this many in a row.
    public static let failuresBeforeAttention = 3
    /// The loop is considered stalled when no check arrives this long after one was due.
    public static let stallGrace: TimeInterval = 90
}

public enum PollStopReason: String, Sendable {
    /// A newer loop owns tracking; this one is a leftover from an earlier open.
    case superseded
    /// Arcaea closed and the closing checks are done.
    case finished
    /// No tracker account is set up.
    case notConfigured
    /// The tracker login needs the user (expired, rejected, or challenged).
    case needsAttention
}

public enum PollDecision: Equatable, Sendable {
    case stop(PollStopReason)
    case wait(seconds: Int)
    case fetch
}

public struct TrackingStatus: Codable, Sendable {
    public var observer: AccountID?
    public var target: AccountID?
    /// Arcaea is believed to be open.
    public var isActive = false
    /// Identifies the one Shortcut loop allowed to drive polling. A new open replaces it.
    public var session: UUID?
    public var startedAt: Date?
    public var closedAt: Date?
    public var closingPollsRemaining = 0
    /// Last time the Shortcut loop checked in, whether or not it fetched.
    public var lastPollAt: Date?
    /// Shared schedule: survives close/reopen so rapid reopening never restarts the wait.
    public var nextPollAt: Date?
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    public var lastNewPlayAt: Date?
    public var lastPlayAt: Date?
    /// Server rate limits and failure backoff. Applies to every request, manual or automatic.
    public var cooldownUntil: Date?
    public var lastStatus: FetchStatus?
    public var consecutiveFailures = 0
    fileprivate var lease: FetchLease?
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case observer, target, isActive, session, startedAt, closedAt, closingPollsRemaining, lastPollAt, nextPollAt
        case lastAttemptAt, lastSuccessAt, lastNewPlayAt, lastPlayAt, cooldownUntil, lastStatus, consecutiveFailures, lease
        // Written by versions before 0.3.
        case protectedCooldownUntil
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        observer = try values.decodeIfPresent(AccountID.self, forKey: .observer)
        target = try values.decodeIfPresent(AccountID.self, forKey: .target)
        session = try values.decodeIfPresent(UUID.self, forKey: .session)
        // A loop from before the update cannot continue: it does not know the new actions.
        isActive = session == nil ? false : try values.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        startedAt = try values.decodeIfPresent(Date.self, forKey: .startedAt)
        closedAt = try values.decodeIfPresent(Date.self, forKey: .closedAt)
        closingPollsRemaining = try values.decodeIfPresent(Int.self, forKey: .closingPollsRemaining) ?? 0
        lastPollAt = try values.decodeIfPresent(Date.self, forKey: .lastPollAt)
        nextPollAt = try values.decodeIfPresent(Date.self, forKey: .nextPollAt)
        lastAttemptAt = try values.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        lastSuccessAt = try values.decodeIfPresent(Date.self, forKey: .lastSuccessAt)
        lastNewPlayAt = try values.decodeIfPresent(Date.self, forKey: .lastNewPlayAt)
        lastPlayAt = try values.decodeIfPresent(Date.self, forKey: .lastPlayAt)
        cooldownUntil = try values.decodeIfPresent(Date.self, forKey: .cooldownUntil)
            ?? values.decodeIfPresent(Date.self, forKey: .protectedCooldownUntil)
        // Older builds stored statuses that no longer exist.
        lastStatus = (try? values.decodeIfPresent(FetchStatus.self, forKey: .lastStatus)) ?? nil
        consecutiveFailures = try values.decodeIfPresent(Int.self, forKey: .consecutiveFailures) ?? 0
        lease = (try? values.decodeIfPresent(FetchLease.self, forKey: .lease)) ?? nil
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(observer, forKey: .observer)
        try values.encodeIfPresent(target, forKey: .target)
        try values.encode(isActive, forKey: .isActive)
        try values.encodeIfPresent(session, forKey: .session)
        try values.encodeIfPresent(startedAt, forKey: .startedAt)
        try values.encodeIfPresent(closedAt, forKey: .closedAt)
        try values.encode(closingPollsRemaining, forKey: .closingPollsRemaining)
        try values.encodeIfPresent(lastPollAt, forKey: .lastPollAt)
        try values.encodeIfPresent(nextPollAt, forKey: .nextPollAt)
        try values.encodeIfPresent(lastAttemptAt, forKey: .lastAttemptAt)
        try values.encodeIfPresent(lastSuccessAt, forKey: .lastSuccessAt)
        try values.encodeIfPresent(lastNewPlayAt, forKey: .lastNewPlayAt)
        try values.encodeIfPresent(lastPlayAt, forKey: .lastPlayAt)
        try values.encodeIfPresent(cooldownUntil, forKey: .cooldownUntil)
        try values.encodeIfPresent(lastStatus, forKey: .lastStatus)
        try values.encode(consecutiveFailures, forKey: .consecutiveFailures)
        try values.encodeIfPresent(lease, forKey: .lease)
    }

    /// Arcaea is open but the Shortcut loop has gone quiet, so plays are not being recorded.
    public func isStalled(now: Date = Date()) -> Bool {
        guard isActive, let reference = [nextPollAt, lastPollAt, startedAt].compactMap({ $0 }).max() else { return false }
        return now.timeIntervalSince(reference) > TrackingPolicy.stallGrace
    }
}

public struct FetchLease: Codable, Sendable {
    public let id: UUID
    public let expiresAt: Date
}

/// Durable tracking state shared by the app UI and background Shortcut actions.
///
/// One SQLite row behind BEGIN IMMEDIATE guards every transition, so overlapping
/// Shortcut runs and the foreground app cannot fetch twice or corrupt the schedule.
/// No secrets are stored here.
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

    /// Replaces the tracked account. Ends any session but keeps server cooldowns.
    public func bind(configuration: RecentConfiguration?) throws {
        try transaction { state in
            let cooldown = state.cooldownUntil
            state = TrackingStatus()
            state.cooldownUntil = cooldown
            state.observer = configuration?.observer; state.target = configuration?.target
        }
    }

    // MARK: Session

    /// Arcaea opened. The returned session supersedes every earlier loop, while the
    /// polling schedule carries over so that reopening quickly cannot postpone a fetch.
    @discardableResult public func start(now: Date = Date()) throws -> UUID {
        let session = UUID()
        try transaction { state in
            state.isActive = true; state.session = session; state.startedAt = now
            state.closedAt = nil; state.closingPollsRemaining = 0; state.lastPollAt = nil
        }
        return session
    }

    /// Arcaea closed. The current loop gets a few closing checks, then ends.
    /// Repeated close events without an open in between leave the countdown alone.
    public func stop(now: Date = Date()) throws {
        try transaction { state in
            guard state.isActive else { return }
            state.isActive = false; state.closedAt = now
            state.closingPollsRemaining = TrackingPolicy.closingPolls
        }
    }

    // MARK: Polling loop

    /// Called by the loop before each request. Decides whether to fetch, wait or end.
    public func beginPoll(session: UUID, now: Date = Date()) throws -> PollDecision {
        try transaction { state in
            guard state.session == session else { return .stop(.superseded) }
            state.lastPollAt = now
            guard state.observer != nil else { return .stop(.notConfigured) }
            if !state.isActive, closingFinished(state, now: now) { return .stop(.finished) }
            if let lease = state.lease, lease.expiresAt > now { return .wait(seconds: 5) }
            let due = [state.nextPollAt, state.cooldownUntil].compactMap { $0 }.max() ?? now
            if due.timeIntervalSince(now) > 1 { return .wait(seconds: seconds(until: due, now: now)) }
            return .fetch
        }
    }

    /// Called by the loop after its request. Schedules the next check.
    /// - Parameter interval: the normal spacing to use; pass a random value from `TrackingPolicy.pollInterval`.
    public func completePoll(session: UUID, status: FetchStatus, now: Date = Date(),
                             interval: TimeInterval = .random(in: TrackingPolicy.pollInterval)) throws -> PollDecision {
        try transaction { state in
            guard state.session == session else { return .stop(.superseded) }
            if status.needsAttention {
                state.isActive = false; state.closingPollsRemaining = 0
                return .stop(.needsAttention)
            }
            var spacing = interval
            if !state.isActive {
                // Only requests that actually went out after closing count as closing checks.
                if let closed = state.closedAt, let attempt = state.lastAttemptAt, attempt >= closed, status.reachedServer {
                    state.closingPollsRemaining = max(0, state.closingPollsRemaining - 1)
                }
                if closingFinished(state, now: now) { return .stop(.finished) }
                spacing = TrackingPolicy.closingInterval
            }
            let next = max(now.addingTimeInterval(spacing), state.cooldownUntil ?? now)
            state.nextPollAt = next
            return .wait(seconds: seconds(until: next, now: now))
        }
    }

    private func closingFinished(_ state: TrackingStatus, now: Date) -> Bool {
        guard state.closingPollsRemaining > 0, let closed = state.closedAt else { return true }
        return now.timeIntervalSince(closed) > TrackingPolicy.closingLimit
    }

    private func seconds(until date: Date, now: Date) -> Int {
        max(1, Int(date.timeIntervalSince(now).rounded(.up)))
    }

    // MARK: Single request

    /// Reserves the one in-flight request slot. Rejects while another request runs or a cooldown applies.
    public func acquire(now: Date = Date(), deadline: TimeInterval = 20) throws -> FetchLease {
        try transaction { state in
            if let lease = state.lease, lease.expiresAt > now { throw TrackingError.alreadyFetching }
            if let cooldown = state.cooldownUntil, cooldown > now { throw TrackingError.cooldown(until: cooldown) }
            let lease = FetchLease(id: UUID(), expiresAt: now.addingTimeInterval(min(60, max(1, deadline)) + 5))
            state.lease = lease; state.lastAttemptAt = now
            return lease
        }
    }

    /// Releases a failed request. Returns how many requests have failed in a row.
    @discardableResult public func finish(lease: FetchLease, status: FetchStatus, now: Date = Date(), cooldownUntil: Date? = nil) throws -> Int {
        try transaction { state in
            guard state.lease?.id == lease.id else { return state.consecutiveFailures }
            state.lease = nil; state.lastStatus = status
            if let until = cooldownUntil { state.cooldownUntil = max(state.cooldownUntil ?? now, until) }
            if status.backsOff {
                state.consecutiveFailures = min(10, state.consecutiveFailures + 1)
                // 60 s, 120 s, 240 s, then 300 s. Being offline never reached the server, so it only waits for the next poll.
                let delay = min(300, 60 * pow(2, Double(state.consecutiveFailures - 1)))
                state.cooldownUntil = max(state.cooldownUntil ?? now, now.addingTimeInterval(delay))
            }
            return state.consecutiveFailures
        }
    }

    /// Runs the archive write while holding the lease, so a result is saved exactly once.
    /// Returns the number of newly added plays reported by `operation`.
    @discardableResult public func commit(lease: FetchLease, now: Date = Date(), latestPlay: Date? = nil, operation: () throws -> Int) throws -> Int {
        try transaction { state in
            guard state.lease?.id == lease.id, lease.expiresAt > now else { throw TrackingError.expiredLease }
            try Task.checkCancellation()
            let count = try operation()
            state.lease = nil; state.lastSuccessAt = now; state.consecutiveFailures = 0
            state.lastStatus = count > 0 ? .success : .unchanged
            if let play = latestPlay { state.lastPlayAt = max(state.lastPlayAt ?? play, play) }
            if count > 0 { state.lastNewPlayAt = latestPlay ?? now }
            return count
        }
    }

    // MARK: Storage

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
        // An unreadable row must never block tracking; start clean instead.
        return (try? JSONDecoder().decode(TrackingStatus.self, from: data)) ?? TrackingStatus()
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw TrackingError.database }
    }
}
