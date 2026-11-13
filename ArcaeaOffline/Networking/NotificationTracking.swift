import ArcaeaCore
import Foundation
import UserNotifications

/// Experimental alternative to the Repeat/Wait loop for systems that cut long automations short.
///
/// Instead of one Shortcut waiting between checks, each check schedules a silent local
/// notification, and a Notification automation runs the next check when it arrives.
/// The timing and stop rules are exactly those of the normal loop (`OnlineRuntime.pollTracking`).
@MainActor protocol PulseDelivery {
    func authorized() async -> Bool
    func schedule(session: UUID, after seconds: Int) async throws
    func cancel()
}

@MainActor final class SystemPulseDelivery: PulseDelivery {
    /// One fixed identifier: scheduling again replaces the pending pulse, so the chain can never fork.
    static let identifier = "arcprobe.tracking.pulse"
    private let center = UNUserNotificationCenter.current()
    func authorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }
    func schedule(session: UUID, after seconds: Int) async throws {
        let content = UNMutableNotificationContent()
        content.title = NotificationTracking.title
        content.body = NotificationTracking.message(session: session)
        content.threadIdentifier = "arcprobe-tracking"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
    }
    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
}

enum NotificationTrackingError: Error, LocalizedError {
    case permission, invalidMessage
    var errorDescription: String? {
        switch self {
        case .permission: "Allow notifications for ArcProbe first: ArcProbe → Settings → Tracking → Notification method."
        case .invalidMessage: "Pass the received notification’s Message (body) to Process Tracking Notification."
        }
    }
}

@MainActor final class NotificationTracking {
    static let title = "ArcProbe tracking pulse"
    static let shared = NotificationTracking(delivery: SystemPulseDelivery())
    private let delivery: any PulseDelivery
    init(delivery: any PulseDelivery) { self.delivery = delivery }

    static func message(session: UUID) -> String { "arcprobe:\(session.uuidString)" }
    static func session(from message: String) throws -> UUID {
        guard let range = message.range(of: #"arcprobe:[A-Fa-f0-9-]{36}"#, options: .regularExpression),
              let session = UUID(uuidString: String(message[range].dropFirst("arcprobe:".count))) else { throw NotificationTrackingError.invalidMessage }
        return session
    }

    func authorized() async -> Bool { await delivery.authorized() }
    func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
    }

    /// Arcaea opened: start a session, check once, and schedule the first pulse.
    func start(runtime: OnlineRuntime) async throws {
        guard await delivery.authorized() else { throw NotificationTrackingError.permission }
        let session = try await runtime.startTracking()
        try await step(session: session, runtime: runtime)
    }

    /// A pulse arrived: run one check and schedule the next pulse. Returns the seconds until it, or 0 when tracking ended.
    @discardableResult func process(message: String, runtime: OnlineRuntime) async throws -> Int {
        try await step(session: Self.session(from: message), runtime: runtime)
    }

    @discardableResult private func step(session: UUID, runtime: OnlineRuntime) async throws -> Int {
        switch await runtime.pollTracking(session: session) {
        case .wait(let seconds):
            try await delivery.schedule(session: session, after: seconds)
            return seconds
        case .fetch:
            try await delivery.schedule(session: session, after: 5)
            return 5
        case .stop(.superseded):
            // A newer session owns the pending pulse; leave it alone.
            return 0
        case .stop(.finished):
            delivery.cancel(); return 0
        case .stop(.needsAttention):
            delivery.cancel(); throw TrackingSetupError.needsAttention
        case .stop(.notConfigured):
            delivery.cancel(); throw TrackingSetupError.notConfigured
        }
    }
}
