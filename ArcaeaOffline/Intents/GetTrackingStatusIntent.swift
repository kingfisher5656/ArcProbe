import AppIntents
import Foundation

struct GetTrackingStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Tracking Status"
    static let description = IntentDescription("Return JSON with the active generation, last attempt, success and new play times, and next permitted request time. Includes no credentials or cookies.")
    static let openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: try ShortcutActions.status(runtime: OnlineRuntime.shared()))
    }
}
