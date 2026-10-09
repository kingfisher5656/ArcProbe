import AppIntents
import Foundation

struct FetchRecentPlayIntent: AppIntent {
    static let title: LocalizedStringResource = "Fetch Recent Play"
    static let description = IntentDescription("Make one short recent-data request using the isolated configured account. Returns JSON with status, added count, last play, last success, and next eligible time. Final Fetch After Closing accepts the original stopped generation; wait 65 seconds in Shortcuts before each of two closing fetches. Honor nextEligibleAt if a longer cooldown applies. Does not open the app.")
    static let openAppWhenRun = false
    @Parameter(title: "Tracking Generation") var generation: String?
    @Parameter(title: "Final Fetch After Closing", default: false) var finalFetch: Bool
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: try await ShortcutActions.fetch(runtime: OnlineRuntime.shared(), generation: generation, finalFetch: finalFetch))
    }
}
