import ArcaeaCore
import SwiftUI

@main
struct ArcaeaOfflineApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: ArchiveModel?
    @State private var runtime: OnlineRuntime?
    @State private var startupError: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let model, let runtime { RootView().environment(model).environment(runtime) }
                else if let startupError { ContentUnavailableView("Archive unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text(startupError)) }
                else { ProgressView("Opening archive…") }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model?.perform { try model?.reload() }; Task { await runtime?.refreshStatus() } }
            }
            .task {
                guard model == nil else { return }
                do {
                    let catalog = try ChartCatalog.bundled()
                    let store = try ArchiveStore(url: ArchiveLocation.url(), catalog: catalog)
                    model = try ArchiveModel(store: store, catalog: catalog)
                    runtime = try OnlineRuntime(store: store, directory: ArchiveLocation.directory())
                    await runtime?.refreshStatus()
                } catch { startupError = error.localizedDescription }
            }
        }
    }
}
