import AppIntents
import ArcaeaCore
import Foundation

// The Shortcut side of tracking is deliberately tiny:
//
//   Start Arcaea Tracking            → Session
//   Repeat
//     Check Recent Play (Session)    → Seconds
//     If Seconds < 1: Stop This Shortcut
//     Wait Seconds
//
// The app decides when to fetch, how long to wait and when the loop is over.
// See docs/shortcuts.md.

struct StartTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Arcaea Tracking"
    static let description = IntentDescription("Run when Arcaea opens. Returns a session to pass to Check Recent Play. Starting again replaces any earlier loop.")
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: try await TrackingActions.start(runtime: AppContainer.shared().runtime))
    }
}

struct CheckRecentPlayIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Recent Play"
    static let description = IntentDescription("Saves the newest play when one is due, then returns how many seconds to wait before checking again. Returns 0 when the loop should end: Arcaea closed, or a newer loop took over.")
    static let openAppWhenRun = false
    @Parameter(title: "Session", description: "The result of Start Arcaea Tracking.") var session: String
    static var parameterSummary: some ParameterSummary { Summary("Check recent play for \(\.$session)") }
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        .result(value: try await TrackingActions.check(runtime: AppContainer.shared().runtime, session: session))
    }
}

struct StopTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Arcaea Tracking"
    static let description = IntentDescription("Run when Arcaea closes. The running loop makes its closing checks and ends by itself.")
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult {
        try AppContainer.shared().runtime.stopTracking()
        return .result()
    }
}

struct FetchRecentPlayIntent: AppIntent {
    static let title: LocalizedStringResource = "Fetch Recent Play Once"
    static let description = IntentDescription("Makes a single request for the newest play and returns a short summary. Not needed inside the tracking loop.")
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = try await AppContainer.shared().runtime.fetchRecent()
        return .result(value: result.summary)
    }
}

struct StartNotificationTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Notification Tracking"
    static let description = IntentDescription("Experimental alternative to the Repeat loop. Run when Arcaea opens; each ArcProbe tracking notification then needs to run Process Tracking Notification.")
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult {
        try await NotificationTracking.shared.start(runtime: AppContainer.shared().runtime)
        return .result()
    }
}

struct ProcessTrackingNotificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Process Tracking Notification"
    static let description = IntentDescription("Experimental. Pass the Message of the received ArcProbe tracking notification. Checks once and schedules the next notification.")
    static let openAppWhenRun = false
    @Parameter(title: "Notification Message") var message: String
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        .result(value: try await NotificationTracking.shared.process(message: message, runtime: AppContainer.shared().runtime))
    }
}

struct ArcProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FetchRecentPlayIntent(), phrases: ["Fetch recent play with \(.applicationName)"], shortTitle: "Fetch Recent Play", systemImageName: "arrow.clockwise")
    }
}

/// Action logic kept apart from AppIntents so it can be tested directly.
@MainActor enum TrackingActions {
    static func start(runtime: OnlineRuntime) async throws -> String {
        try await runtime.startTracking().uuidString
    }

    /// Seconds the Shortcut should wait before the next check; 0 ends the loop.
    /// Problems the user must fix are thrown, so Shortcuts shows them as a notification.
    static func check(runtime: OnlineRuntime, session: String) async throws -> Int {
        guard let id = UUID(uuidString: session.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw TrackingSetupError.invalidSession }
        switch await runtime.pollTracking(session: id) {
        case .wait(let seconds): return seconds
        case .fetch: return 5
        case .stop(.superseded), .stop(.finished): return 0
        case .stop(.needsAttention): throw TrackingSetupError.needsAttention
        case .stop(.notConfigured): throw TrackingSetupError.notConfigured
        }
    }
}

extension FetchResult {
    /// One line for people: used by the in-app button and the one-shot Shortcut action.
    var summary: String {
        switch status {
        case .success: "Saved \(addedCount) new play\(addedCount == 1 ? "" : "s")"
        case .unchanged: "No new play"
        case .cooldown, .rateLimited: "The server asked us to wait" + (nextEligibleAt.map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? "")
        case .alreadyFetching: "Another check is already running"
        case .authenticationRequired, .attentionRequired: "The tracker account needs to sign in again"
        case .wrongAccount: "The tracker account can no longer see the watched account"
        case .locked: "Unlock the device once, then try again"
        case .offline: "No connection"
        case .deadlineExceeded: "The server took too long"
        case .cancelled: "Cancelled"
        case .unsupportedSchema: "The website sent something unexpected"
        case .failed: "The check failed; it will be retried"
        }
    }
}
