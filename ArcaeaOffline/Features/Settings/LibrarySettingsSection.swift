import ArcaeaCore
import SwiftUI

struct LibrarySettingsSection: View {
    @Environment(ArchiveModel.self) private var model
    private var resources: LibraryResources { .shared }
    var body: some View {
        Section {
            if let date = resources.constantsDate { LabeledContent("Constants refreshed", value: date.formatted(date: .abbreviated, time: .shortened)) }
            Button(resources.refreshingConstants ? "Refreshing constants…" : "Refresh chart constants") {
                Task { do { try await resources.refreshConstants(store: model.store); try model.reload() } catch { model.errorMessage = error.localizedDescription } }
            }.disabled(resources.refreshingConstants)
            Button("Download missing official covers") { resources.downloadCovers(charts: Array(model.catalog.charts.values)) }.disabled(resources.downloading)
            Button("Refresh downloaded covers") { resources.downloadCovers(charts: Array(model.catalog.charts.values), refresh: true) }.disabled(resources.downloading)
            if resources.downloading {
                Text(resources.progress).font(.footnote)
                Button("Cancel cover download", role: .cancel) { resources.cancelDownload() }
            }
            if let message = resources.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } header: { Text("Chart data & cover art") } footer: {
            Text("Constants come from the Arcaea community wiki on Miraheze. Covers use the artwork identifiers supplied by your main account’s score import and are downloaded from lowiro’s asset server. Import scores first, then download covers for offline use. Missing artwork keeps a placeholder.")
        }
    }
}
