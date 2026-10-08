import AppIntents
import Foundation

struct SetTrackingActiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Tracking Active"
    static let description = IntentDescription("Start a new tracking generation, or stop it. Pass the returned generation to each fetch in your loop.")
    static let openAppWhenRun = false
    @Parameter(title: "Active", default: true) var active: Bool
    static var parameterSummary: some ParameterSummary { Summary("Set tracking active to \(\.$active)") }
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: try ShortcutActions.setTracking(runtime: OnlineRuntime.shared(), active: active))
    }
}
