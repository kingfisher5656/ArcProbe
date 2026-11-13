import ArcaeaCore
import UIKit

/// The single set of stores shared by the visible app and background Shortcut actions.
///
/// Shortcut actions run inside the app process, often while no window exists. Sharing
/// one container means a play saved by an action shows up in an open window right away.
@MainActor final class AppContainer {
    let model: ArchiveModel
    let runtime: OnlineRuntime
    private static var cached: AppContainer?

    private init() throws {
        let catalog = try ChartCatalog.bundled()
        let store = try ArchiveStore(url: ArchiveLocation.url(), catalog: catalog)
        let model = try ArchiveModel(store: store, catalog: catalog)
        runtime = try OnlineRuntime(store: store, directory: ArchiveLocation.directory())
        self.model = model
        runtime.onArchiveChanged = {
            // In the background nothing is on screen; the next activation reloads anyway.
            guard UIApplication.shared.applicationState != .background else { return }
            model.perform { try model.reload() }
        }
    }

    static func shared() throws -> AppContainer {
        if let cached { return cached }
        let container = try AppContainer()
        cached = container
        return container
    }
}
