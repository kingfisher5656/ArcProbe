import Foundation

public struct NotificationPulseState: Codable, Sendable {
    public var minimumSeconds = 65
    public var maximumSeconds = 80
    public var generation: UUID?
    public var token: UUID?
    public var nextAt: Date?
    public var isActive: Bool { token != nil && generation != nil }
    public init() {}
}

/// Durable single-use tokens protect the notification chain across process restarts and overlapping actions.
public final class NotificationPulseStore: @unchecked Sendable {
    private let database: ArchiveDatabase
    private let lock = NSLock()
    public init(url: URL) throws {
        database = try ArchiveDatabase(url: url)
        try database.execute("CREATE TABLE IF NOT EXISTS notification_pulse(id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL)")
    }
    public func state() throws -> NotificationPulseState {
        lock.lock(); defer { lock.unlock() }
        return try read()
    }
    public func configure(minimum: Int, maximum: Int) throws {
        guard (60...3_600).contains(minimum), (minimum...3_600).contains(maximum) else { throw ArchiveError.invalidRecord("Choose intervals from 60 to 3600 seconds, with maximum at least minimum") }
        try update { $0.minimumSeconds = minimum; $0.maximumSeconds = maximum }
    }
    public func start(generation: UUID, now: Date, randomDelay: Int, notBefore: Date? = nil) throws -> NotificationPulseState {
        try update { state in
            state.generation = generation
            Self.schedule(&state, now: now, randomDelay: randomDelay, notBefore: notBefore)
            return state
        }
    }
    public func advance(token: UUID, generation: UUID, now: Date, randomDelay: Int, notBefore: Date? = nil) throws -> NotificationPulseState? {
        try update { state in
            guard state.token == token, state.generation == generation,
                  let next = state.nextAt, now >= next.addingTimeInterval(-2) else { return nil }
            Self.schedule(&state, now: now, randomDelay: randomDelay, notBefore: notBefore)
            return state
        }
    }
    @discardableResult public func stop(expectedToken: UUID? = nil) throws -> NotificationPulseState? {
        try update { state in
            guard expectedToken == nil || state.token == expectedToken else { return nil }
            let previous = state
            state.token = nil; state.generation = nil; state.nextAt = nil
            return previous
        }
    }
    private static func schedule(_ state: inout NotificationPulseState, now: Date, randomDelay: Int, notBefore: Date?) {
        let delay = min(state.maximumSeconds, max(state.minimumSeconds, randomDelay))
        state.token = UUID()
        state.nextAt = max(now.addingTimeInterval(Double(delay)), notBefore ?? now)
    }
    private func read() throws -> NotificationPulseState {
        guard let data = try database.dataRows("SELECT payload FROM notification_pulse WHERE id=1").first else { return NotificationPulseState() }
        return try JSONDecoder().decode(NotificationPulseState.self, from: data)
    }
    private func update<T>(_ body: (inout NotificationPulseState) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        return try database.transaction {
            var state = try read()
            let result = try body(&state)
            try database.execute("INSERT OR REPLACE INTO notification_pulse(id,payload) VALUES(1,?)", [.blob(try JSONEncoder().encode(state))])
            return result
        }
    }
}
