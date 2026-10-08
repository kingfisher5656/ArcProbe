import AppIntents
import Foundation

struct ConfigureBurnerIntent: AppIntent {
    static let title: LocalizedStringResource = "Configure Recent Account"
    static let description = IntentDescription("Enter credentials once to configure the isolated recent account. Friend mode uses the main account connected in the app. Remove literal credentials from the saved setup Shortcut afterward.")
    static let openAppWhenRun = false
    @Parameter(title: "Email") var email: String
    @Parameter(title: "Password") var password: String
    @Parameter(title: "Source", default: .ownAccountTesting) var mode: ShortcutRecentMode
    static var parameterSummary: some ParameterSummary { Summary("Configure recent account \(\.$email) using \(\.$mode)") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let runtime = try OnlineRuntime.shared()
        try await runtime.configureRecent(email: email, password: password, mode: mode.coreMode)
        return .result(dialog: "Recent account configured. Remove literal credentials from this saved setup action; recurring fetches use secure storage.")
    }
}
