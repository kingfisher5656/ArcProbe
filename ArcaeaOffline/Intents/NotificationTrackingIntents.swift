import AppIntents
import Foundation

struct StartNotificationTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Notification Tracking"
    static let description = IntentDescription("Start ArcProbe tracking pulses at the interval chosen in the app. On iOS 27, configure a notification automation to run Process Tracking Notification for each pulse.")
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let state = try await NotificationTracking.shared().start(runtime: OnlineRuntime.shared())
        return .result(value: state.generation?.uuidString ?? "")
    }
}
struct StopNotificationTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Notification Tracking"
    static let description = IntentDescription("Stop tracking and cancel ArcProbe’s pending pulse. A previously delivered notification cannot restart it.")
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult {
        try NotificationTracking.shared().stop(runtime: OnlineRuntime.shared())
        return .result()
    }
}
struct ProcessTrackingNotificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Process Tracking Notification"
    static let description = IntentDescription("Pass the received ArcProbe notification Message. Valid pulses schedule the next random interval and perform one bounded recent fetch. Old or duplicate pulses are ignored.")
    static let openAppWhenRun = false
    @Parameter(title: "Notification Message") var message: String
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: try await NotificationTracking.shared().process(message: message, runtime: OnlineRuntime.shared()))
    }
}
