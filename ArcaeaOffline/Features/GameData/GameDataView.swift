import ArcaeaCore
import SwiftUI
import UniformTypeIdentifiers

/// Scores, song data and cover art read straight from Arcaea's own data folder.
struct GameDataView: View {
    @Environment(ArchiveModel.self) private var archive
    @State private var model = GameDataModel.shared
    @State private var picking = false
    private enum Confirm { case otherPlayer, remove }
    @State private var confirm: Confirm?

    private var account: AccountID { archive.selectedAccountID ?? AccountID("local") }
    private var accountName: String {
        if let name = archive.selectedProfile?.displayName { return name }
        return account == AccountID("local") ? String(localized: "the local archive") : account.rawValue
    }
    /// A reading made for another account must not be imported into this one.
    private var reading: GameDataReading? { model.readAccount == account ? model.reading : nil }
    private var otherPlayer: String? {
        guard let player = reading?.playerName, let name = archive.selectedProfile?.displayName,
              player.caseInsensitiveCompare(name) != .orderedSame else { return nil }
        return player
    }

    var body: some View {
        List {
            Section {
                if let reading {
                    LabeledContent(String(localized: "Player"), value: reading.playerName ?? String(localized: "Unknown"))
                    if let version = reading.gameVersion { LabeledContent("Game content", value: version) }
                }
                if model.hasFolder {
                    Button("Read folder again", systemImage: "arrow.clockwise") { Task { await model.refresh(archive: archive) } }
                        .disabled(model.busy).accessibilityIdentifier("gamedata.refresh")
                }
                Button(model.hasFolder ? "Choose a different folder" : "Choose Arcaea folder", systemImage: "folder") { picking = true }
                    .disabled(model.busy).accessibilityIdentifier("gamedata.choose")
            } header: { Text("Arcaea folder") } footer: {
                Text("In the folder picker open LiveContainer, then Data, then Application, and choose it. ArcProbe finds Arcaea inside and remembers the folder. Sign in to that Arcaea first so its scores are on this device. Nothing in the folder is changed.")
            }
            if model.busy { Section { HStack(spacing: 12) { ProgressView(); Text(model.progress) } } }
            if let reading {
                if let otherPlayer {
                    Section {
                        Label("This folder is signed in as \(otherPlayer), but ArcProbe is showing \(accountName).", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                Section {
                    LabeledContent(String(localized: "New or higher scores"), value: String(localized: "\(reading.plan.addCount) of \(reading.scoreCount)"))
                    ForEach(skipped(reading.plan), id: \.label) { LabeledContent($0.label, value: String($0.count)).foregroundStyle(.secondary) }
                    if reading.hasSongList { LabeledContent("Charts with new song data", value: String(reading.plan.chartChangeCount)) }
                    if reading.coverTotal > 0 {
                        Toggle(isOn: $model.includeCovers) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Copy cover art")
                                Text(reading.covers.isEmpty ? "All \(reading.coverTotal) covers are already copied" : "\(reading.covers.count) new covers, \(ByteCountFormatter.string(fromByteCount: Int64(reading.coverBytes), countStyle: .file))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(reading.covers.isEmpty)
                    } else {
                        Text(reading.hasSongList ? "No cover art was found in this folder." : "No song data or covers were found here. Choosing a folder above Arcaea's Documents folder includes them.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button(importTitle(reading)) { if otherPlayer != nil { confirm = .otherPlayer } else { Task { await model.apply(archive: archive) } } }
                        .buttonStyle(.borderedProminent).disabled(model.busy || nothingToDo(reading))
                        .accessibilityIdentifier("gamedata.import")
                } header: { Text("Import into \(accountName)") } footer: {
                    Text("A score is added only when it beats the one ArcProbe already has, so plays that were never uploaded are kept. Play dates stay unknown. A later main-account import does not remove these scores.")
                }
                if !reading.plan.additions.isEmpty {
                    Section("Scores to add") {
                        ForEach(reading.plan.additions) { entry in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(archive.catalog[entry.chartID]?.title ?? reading.titles[entry.chartID] ?? entry.chartID.songID).font(.headline).lineLimit(1)
                                    ChartBadge(chart: entry.chartID, level: archive.catalog[entry.chartID]?.level)
                                }
                                Spacer(minLength: 4)
                                VStack(alignment: .trailing, spacing: 5) {
                                    Text(DisplayFormat.score(entry.score)).font(.headline.monospacedDigit())
                                    Text(entry.previousScore.map { String(localized: "now \(DisplayFormat.score($0))") } ?? String(localized: "no score yet")).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 2)
                        }
                    }
                }
            }
            if let message = model.message {
                Section { Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("gamedata.message") }
            }
            if model.importedScoreCount > 0 {
                Section {
                    Button("Remove \(model.importedScoreCount) game-folder scores", systemImage: "trash", role: .destructive) { confirm = .remove }.tint(.red).disabled(model.busy)
                } footer: { Text("Takes back every score that came from a game folder, for example after importing another account's folder. Song data and covers stay.") }
            }
        }
        .navigationTitle("Arcaea game folder").navigationBarTitleDisplayMode(.inline)
        .task(id: account) { await model.refresh(archive: archive) }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): Task { await model.choose(url, archive: archive) }
            case .failure(let error): archive.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(confirm == .remove ? "Remove \(model.importedScoreCount) game-folder scores?" : "Import another player's scores?",
                            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            if confirm == .remove {
                Button("Remove scores", role: .destructive) { Task { await model.removeImported(archive: archive) } }
            } else {
                Button("Import into \(accountName)") { Task { await model.apply(archive: archive) } }
            }
        } message: {
            Text(confirm == .remove ? String(localized: "Scores from other sources are not touched.") : String(localized: "The folder is signed in as \(otherPlayer ?? "someone else"). Its scores would be mixed into \(accountName)."))
        }
    }

    private func nothingToDo(_ reading: GameDataReading) -> Bool {
        reading.plan.addCount == 0 && reading.plan.chartChangeCount == 0 && (reading.covers.isEmpty || !model.includeCovers)
    }
    private func importTitle(_ reading: GameDataReading) -> String {
        if nothingToDo(reading) { return String(localized: "Everything is up to date") }
        let count = reading.plan.addCount
        return count == 0 ? String(localized: "Update song data and covers") : String(localized: "Import \(count) scores")
    }
    private func skipped(_ plan: GameDataImportPlan) -> [(label: String, count: Int)] {
        let labels: [(GameDataImportPlan.Disposition, String)] = [
            (.keepExisting, String(localized: "Already equal or higher in ArcProbe")), (.removedEarlier, String(localized: "Deleted or edited in ArcProbe")),
            (.unknownChart, String(localized: "Not an official chart")), (.invalid, String(localized: "Unreadable"))
        ]
        return labels.compactMap { kind, label in
            let count = plan.entries.filter { $0.disposition == kind }.count
            return count == 0 ? nil : (label, count)
        }
    }
}
