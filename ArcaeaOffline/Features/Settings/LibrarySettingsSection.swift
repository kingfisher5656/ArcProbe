import ArcaeaCore
import SwiftUI
import UniformTypeIdentifiers

struct LibrarySettingsSection: View {
    @Environment(ArchiveModel.self) private var model
    @State private var wiki = false
    @State private var importingCovers = false
    @State private var coverShare: ShareFile?
    @State private var exportedCoverURL: URL?
    private var resources: LibraryResources { .shared }
    var body: some View {
        Section {
            if let date = resources.constantsDate { LabeledContent("Constants refreshed", value: date.formatted(date: .abbreviated, time: .shortened)) }
            Button(resources.refreshingConstants ? "Refreshing constants…" : "Refresh chart constants") {
                Task { do { try await resources.refreshConstants(store: model.store); try model.reload() } catch { model.errorMessage = error.localizedDescription } }
            }.disabled(resources.refreshingConstants)
            Button("Download sharper wiki covers") { wiki = true }.disabled(resources.managingCoverBackup)
            Button("Download missing official covers") { resources.downloadCovers(charts: Array(model.catalog.charts.values)) }.disabled(resources.downloading || resources.managingCoverBackup)
            Button("Refresh downloaded covers") { resources.downloadCovers(charts: Array(model.catalog.charts.values), refresh: true) }.disabled(resources.downloading || resources.managingCoverBackup)
            Button("Export cover backup", systemImage: "square.and.arrow.up") {
                Task {
                    do {
                        let url = try await resources.exportCoverBackup()
                        exportedCoverURL = url
                        coverShare = ShareFile(url: url)
                    } catch { model.errorMessage = error.localizedDescription }
                }
            }.disabled(resources.downloading || resources.managingCoverBackup)
            Button("Restore cover backup", systemImage: "square.and.arrow.down") { importingCovers = true }
                .disabled(resources.downloading || resources.managingCoverBackup)
            if resources.managingCoverBackup { ProgressView("Preparing cover backup…") }
            if resources.downloading {
                Text(resources.progress).font(.footnote)
                Button("Cancel cover download", role: .cancel) { resources.cancelDownload() }
            }
            if let message = resources.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
        } header: { Text("Chart data & cover art") } footer: {
            Text("Constants come from the Arcaea community wiki on Miraheze. Covers use the artwork identifiers supplied by your main account’s score import and are downloaded from lowiro’s asset server. Import scores first. Sharper wiki covers use original files with matching song IDs and difficulty labels; official images remain the fallback. Downloaded covers work offline. Export a separate cover backup to Files before reinstalling, then restore it to avoid downloading again. Cover backups preserve original files and difficulty variants; restore merges them and keeps existing images of equal or higher resolution.")
        }
        .sheet(isPresented: $wiki) { WikiArtworkView() }
        .sheet(item: $coverShare, onDismiss: {
            if let url = exportedCoverURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            exportedCoverURL = nil
        }) { ShareSheet(file: $0) }
        .fileImporter(isPresented: $importingCovers, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url):
                Task { do { try await resources.restoreCoverBackup(from: url) } catch { model.errorMessage = error.localizedDescription } }
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
    }
}
