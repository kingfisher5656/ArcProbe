import ArcaeaCore
import SwiftUI

/// Chart data and cover artwork, both downloaded on request and kept offline.
struct LibraryView: View {
    @Environment(ArchiveModel.self) private var model
    @State private var showingWiki = false
    private var resources: LibraryResources { .shared }
    private var busy: Bool { resources.downloading || resources.managingCoverBackup }
    var body: some View {
        List {
            Section {
                LabeledContent("Last updated", value: resources.constantsDate?.formatted(date: .abbreviated, time: .shortened) ?? "Bundled with the app")
                Button(resources.refreshingConstants ? "Updating…" : "Update constants and levels", systemImage: "arrow.triangle.2.circlepath") {
                    Task { do { try await resources.refreshChartData(store: model.store); try model.reload() } catch { model.errorMessage = error.localizedDescription } }
                }.disabled(resources.refreshingConstants)
            } header: { Text("Chart data") } footer: { Text("Constants, levels and song names from the Arcaea community wiki. Update after a game update adds songs or changes constants.") }
            Section {
                Button("Download missing covers", systemImage: "arrow.down.circle") { resources.downloadCovers(charts: Array(model.catalog.charts.values)) }.disabled(busy)
                Button("Download sharper wiki covers", systemImage: "sparkles") { showingWiki = true }.disabled(busy)
                    .accessibilityIdentifier("library.wiki")
                Button("Download all covers again", systemImage: "arrow.clockwise") { resources.downloadCovers(charts: Array(model.catalog.charts.values), refresh: true) }.disabled(busy)
                if resources.downloading {
                    HStack { ProgressView(); Text(resources.progress).font(.subheadline); Spacer(); Button("Cancel") { resources.cancelDownload() } }
                }
            } header: { Text("Cover art") } footer: {
                Text("Covers are known for songs that appear in a main-account import. Wiki covers are larger originals and replace the official one where the song and difficulty match exactly.")
            }
            if let message = resources.message { Section { Text(message).font(.subheadline).foregroundStyle(.secondary) } }
        }
        .navigationTitle("Charts & cover art").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingWiki) { WikiArtworkView() }
    }
}
