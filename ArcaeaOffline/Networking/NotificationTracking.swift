import ArcaeaCore
import Foundation
import UserNotifications

@MainActor protocol PulseDelivery {
    func authorized() async -> Bool
    func schedule(_ state: NotificationPulseState) async throws
    func cancel(token: UUID)
}

@MainActor final class SystemPulseDelivery: PulseDelivery {
    private let center = UNUserNotificationCenter.current()
    func authorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
    func schedule(_ state: NotificationPulseState) async throws {
        guard let token = state.token, let generation = state.generation, let date = state.nextAt else { return }
        let content = UNMutableNotificationContent()
        content.title = "ArcProbe tracking pulse"
        content.subtitle = "Recent play refresh"
        content.body = "arcprobe:\(generation.uuidString):\(token.uuidString)"
        content.threadIdentifier = "arcprobe-tracking"
        // No sound; normal notification delivery remains subject to Focus and system policies.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(identifier: token.uuidString, content: content, trigger: trigger))
    }
    func cancel(token: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [token.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [token.uuidString])
    }
}

enum NotificationTrackingError: Error, LocalizedError {
    case permission, unconfigured, invalidToken
    var errorDescription: String? {
        switch self {
        case .permission: "Enable notifications in ArcProbe Settings before starting notification tracking."
        case .unconfigured: "Configure the recent account in ArcProbe before starting notification tracking."
        case .invalidToken: "Pass the received notification’s Message (body) to Process Tracking Notification."
        }
    }
}

@MainActor final class NotificationTracking {
    private let store: NotificationPulseStore
    private let delivery: any PulseDelivery
    private static var cached: NotificationTracking?
    init(store: NotificationPulseStore, delivery: any PulseDelivery) { self.store = store; self.delivery = delivery }
    static func shared() throws -> NotificationTracking {
        if let cached { return cached }
        let value = try NotificationTracking(store: NotificationPulseStore(url: ArchiveLocation.directory().appendingPathComponent("notification-pulses.sqlite")), delivery: SystemPulseDelivery())
        cached = value; return value
    }
    func state() throws -> NotificationPulseState { try store.state() }
    func configure(minimum: Int, maximum: Int) throws { try store.configure(minimum: minimum, maximum: maximum) }
    @discardableResult func start(runtime: OnlineRuntime, now: Date = Date()) async throws -> NotificationPulseState {
        guard await delivery.authorized() else { throw NotificationTrackingError.permission }
        await runtime.refreshStatus()
        guard runtime.recentConfiguration != nil else { throw NotificationTrackingError.unconfigured }
        let previous = try store.state()
        let generation = try runtime.startTracking()
        let next = try store.start(generation: generation, now: now, randomDelay: delay(previous), notBefore: runtime.status().nextEligibleAt)
        if let token = previous.token { delivery.cancel(token: token) }
        do { try await schedule(next) }
        catch {
            if try runtime.status().generation == generation { try runtime.stopTracking() }
            throw error
        }
        return try store.state()
    }
    func stop(runtime: OnlineRuntime) throws {
        let previous = try store.stop()
        try runtime.stopTracking()
        if let token = previous?.token { delivery.cancel(token: token) }
    }
    func process(message: String, runtime: OnlineRuntime, now: Date = Date()) async throws -> String {
        let (generation, token) = try Self.parse(message)
        let tracking = try runtime.status()
        guard tracking.isActive, tracking.generation == generation else {
            if let old = try store.stop(expectedToken: token)?.token { delivery.cancel(token: old) }
            return try shortcutJSON(ShortcutFetchOutput(FetchResult(status: .staleGeneration)))
        }
        let current = try store.state()
        guard let next = try store.advance(token: token, generation: generation, now: now, randomDelay: delay(current), notBefore: tracking.nextEligibleAt) else {
            return try shortcutJSON(ShortcutFetchOutput(FetchResult(status: .unchanged)))
        }
        delivery.cancel(token: token)
        // Renew before fetching, so an offline request or action interruption does not inherently end the chain.
        try await schedule(next)
        let result = await runtime.fetchRecent(generation: generation)
        if [.attentionRequired, .authenticationRequired, .wrongAccount, .unsupportedSchema].contains(result.status),
           let stopped = try store.stop(expectedToken: next.token), let pending = stopped.token {
            delivery.cancel(token: pending)
            if try runtime.status().generation == generation { try runtime.stopTracking() }
        }
        return try shortcutJSON(ShortcutFetchOutput(result))
    }
    private func schedule(_ state: NotificationPulseState) async throws {
        guard let token = state.token else { return }
        do {
            guard await delivery.authorized() else { throw NotificationTrackingError.permission }
            try await delivery.schedule(state)
            // Stop/start may run while the system registers the request. Remove only our superseded token.
            if try store.state().token != token { delivery.cancel(token: token) }
        } catch {
            _ = try? store.stop(expectedToken: token)
            delivery.cancel(token: token)
            throw error
        }
    }
    private func delay(_ state: NotificationPulseState) -> Int { Int.random(in: state.minimumSeconds...state.maximumSeconds) }
    static func parse(_ message: String) throws -> (UUID, UUID) {
        let expression = try NSRegularExpression(pattern: #"arcprobe:([A-Fa-f0-9-]{36}):([A-Fa-f0-9-]{36})"#)
        guard let match = expression.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let a = Range(match.range(at: 1), in: message), let b = Range(match.range(at: 2), in: message),
              let generation = UUID(uuidString: String(message[a])), let token = UUID(uuidString: String(message[b])) else { throw NotificationTrackingError.invalidToken }
        return (generation, token)
    }
}
