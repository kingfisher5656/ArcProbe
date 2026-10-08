import ArcaeaCore
import SwiftUI

struct ScoresView: View {
    @Environment(ArchiveModel.self) private var model
    @State private var query = ""
    @State private var difficulty: Difficulty?
    @State private var editor: ScoreEditorDestination?
    private var filtered: [BestScore] {
        model.bestScores.filter { (difficulty == nil || $0.chartID.difficulty == difficulty) && (query.isEmpty || model.title($0.chartID).localizedCaseInsensitiveContains(query) || $0.chartID.songID.localizedCaseInsensitiveContains(query)) }
            .sorted { model.title($0.chartID).localizedStandardCompare(model.title($1.chartID)) == .orderedAscending }
    }
    var body: some View {
        List {
            Section {
                Picker("Difficulty", selection: $difficulty) { Text("All").tag(Difficulty?.none); ForEach(Difficulty.allCases, id: \.self) { Text($0.label).tag(Optional($0)) } }.pickerStyle(.segmented)
            }
            Section("\(filtered.count) chart bests") {
                ForEach(filtered, id: \.chartID) { best in
                    NavigationLink { ScoreDetailView(chart: best.chartID) } label: { ScoreRow(chart: best.chartID, values: best.values, override: best.isOverridden || best.isBestCorrection) }
                }
            }
        }
        .overlay { if model.bestScores.isEmpty { ContentUnavailableView("No saved scores", systemImage: "music.note.list", description: Text("Tap + to record a play. Everything works offline.")) } else if filtered.isEmpty { ContentUnavailableView.search(text: query) } }
        .navigationTitle("Scores").searchable(text: $query, prompt: "Search song title or ID")
        .toolbar { Button("Add score", systemImage: "plus") { editor = .add }.accessibilityIdentifier("addScore") }
        .sheet(item: $editor) { ScoreEditorView(destination: $0) }
    }
}
