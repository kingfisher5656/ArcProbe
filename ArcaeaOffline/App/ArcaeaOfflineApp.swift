import ArcaeaCore
import SwiftUI

@main
struct ArcaeaOfflineApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var container: AppContainer?
    @State private var startupError: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let container { RootView().environment(container.model).environment(container.runtime) }
                else if let startupError { ContentUnavailableView("Archive unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError)) }
                else { ProgressView("Opening archive…") }
            }
            .onOpenURL { url in ConsultantProbeModel.shared.auth.resume(url) }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, let container else { return }
                container.model.perform { try container.model.reload() }
                Task { await container.runtime.refreshStatus() }
            }
            .task {
                guard container == nil else { return }
                do {
                    let shared = try AppContainer.shared()
                    container = shared
                    await shared.runtime.refreshStatus()
                } catch { startupError = error.localizedDescription }
            }
        }
    }
}
