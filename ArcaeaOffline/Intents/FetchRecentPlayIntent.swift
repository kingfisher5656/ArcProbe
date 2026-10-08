import AppIntents
import Foundation

struct FetchRecentPlayIntent: AppIntent {
    static let title: LocalizedStringResource = "Fetch Recent Play"
    static let description = IntentDescription("Make one short recent-data request using the isolated configured account. Returns JSON with status, added count, last play, last success, and next eligible time. Does not open the app.")
    static let openAppWhenRun = false
    @Parameter(title: "Tracking Generation") var generation: String?
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: try await ShortcutActions.fetch(runtime: OnlineRuntime.shared(), generation: generation))
    }
}
