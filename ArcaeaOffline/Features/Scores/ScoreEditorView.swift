import ArcaeaCore
import SwiftUI

enum ScoreEditorDestination: Identifiable {
    case add, addForChart(ChartID), edit(EffectiveObservation), correctBest(ChartID, ScoreValues)
    var id: String { switch self { case .add: "add"; case .addForChart(let chart): "add:\(chart.key)"; case .edit(let play): "edit:\(play.original.id.rawValue)"; case .correctBest(let chart, _): "best:\(chart.key)" } }
    var chart: ChartID? { switch self { case .add: nil; case .addForChart(let chart), .correctBest(let chart, _): chart; case .edit(let play): play.original.chartID } }
    var values: ScoreValues? { switch self { case .edit(let play): play.values; case .correctBest(_, let values): values; default: nil } }
    var title: String { switch self { case .edit: "Edit play"; case .correctBest: "Correct chart best"; default: "Add score" } }
}

struct ScoreEditorView: View {
    @Environment(ArchiveModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let destination: ScoreEditorDestination
    @State private var chart: ChartID?
    @State private var score: String
    @State private var hasDate: Bool
    @State private var date: Date
    @State private var pure: String
    @State private var shiny: String
    @State private var far: String
    @State private var lost: String
    @State private var early: String
    @State private var late: String
    @State private var playClear: ClearType?
    @State private var bestClear: ClearType?
    @State private var modifier: String
    @State private var health: String
    @State private var choosingChart = false
    @State private var validation: String?

    init(destination: ScoreEditorDestination) {
        self.destination = destination
        let values = destination.values
        _chart = State(initialValue: destination.chart)
        _score = State(initialValue: values.map { String($0.score) } ?? "")
        _hasDate = State(initialValue: values?.playedAt != nil)
        _date = State(initialValue: values?.playedAt?.date ?? Date())
        _pure = State(initialValue: values?.judgments?.pure.map(String.init) ?? "")
        _shiny = State(initialValue: values?.judgments?.shinyPure.map(String.init) ?? "")
        _far = State(initialValue: values?.judgments?.far.map(String.init) ?? "")
        _lost = State(initialValue: values?.judgments?.lost.map(String.init) ?? "")
        _early = State(initialValue: values?.judgments?.early.map(String.init) ?? "")
        _late = State(initialValue: values?.judgments?.late.map(String.init) ?? "")
        _playClear = State(initialValue: values?.playClear)
        _bestClear = State(initialValue: values?.bestClear)
        _modifier = State(initialValue: values?.modifier.map(String.init) ?? "")
        _health = State(initialValue: values?.health.map(String.init) ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                if let validation { Section { HStack { Image(systemName: "exclamationmark.circle"); Text(validation).accessibilityIdentifier("validationMessage") }.foregroundStyle(.red) } }
                Section("Chart") {
                    Button { choosingChart = true } label: { HStack { Text(chart.map { model.title($0) } ?? "Choose a chart"); Spacer(); if let chart { ChartBadge(chart: chart) }; Image(systemName: "chevron.right").foregroundStyle(.secondary) } }.accessibilityIdentifier("chooseChart")
                        .disabled(destination.values != nil)
                }
                Section("Score and clear") {
                    TextField("Score, e.g. 9900000", text: $score).keyboardType(.numberPad).accessibilityIdentifier("scoreField")
                    clearPicker("Play clear", selection: $playClear)
                    clearPicker("Best clear lamp", selection: $bestClear)
                    DisclosureGroup("Gauge and health (optional)") { numberField("Gauge modifier", text: $modifier); numberField("Health", text: $health) }
                }
                Section {
                    Toggle("Record a play date", isOn: $hasDate)
                    if hasDate { DatePicker("Date", selection: $date) }
                } footer: { Text("Leave this off if the date is unknown. Edited dates are marked as manually recorded.") }
                Section {
                    numberField("Pure", text: $pure); numberField("Far", text: $far); numberField("Lost", text: $lost)
                    DisclosureGroup("Additional judgments") { numberField("Shiny pure", text: $shiny); numberField("Early", text: $early); numberField("Late", text: $late) }
                } header: { Text("Judgments (optional)") } footer: { Text("Blank fields remain unknown. Provided counts must be consistent with the chart’s note count when known.") }
                if case .correctBest = destination { Section { Text("This sets the chart’s local personal best, even when it is lower than an imported result. Reset it in chart details to use imported data again.").foregroundStyle(.secondary) } }
            }
            .navigationTitle(destination.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold).accessibilityIdentifier("saveScore") } }
            .sheet(isPresented: $choosingChart) { ChartPickerView(selected: $chart) }
        }
    }
    private func numberField(_ title: String, text: Binding<String>) -> some View { HStack { Text(title); Spacer(); TextField("Unknown", text: text).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 150) } }
    private func clearPicker(_ title: String, selection: Binding<ClearType?>) -> some View { Picker(title, selection: selection) { Text("Unknown").tag(ClearType?.none); ForEach(ClearType.allCases, id: \.self) { Text(DisplayFormat.clear($0)).tag(Optional($0)) } } }
    private func optionalCount(_ value: String) throws -> Int? {
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let count = Int(value), count >= 0 else { throw ArchiveError.invalidRecord("Judgment counts must be positive whole numbers or blank.") }
        return count
    }
    private func save() {
        do {
            guard let chart else { throw ArchiveError.invalidRecord("Choose a chart first.") }
            guard let value = Int(score.replacingOccurrences(of: ",", with: "")) else { throw ArchiveError.invalidRecord("Enter a whole-number score.") }
            let judgments = Judgments(pure: try optionalCount(pure), shinyPure: try optionalCount(shiny), far: try optionalCount(far), lost: try optionalCount(lost), early: try optionalCount(early), late: try optionalCount(late))
            let hasJudgments = [judgments.pure, judgments.shinyPure, judgments.far, judgments.lost, judgments.early, judgments.late].contains { $0 != nil }
            let draft = ScoreDraft(chartID: chart, score: value, playedAt: hasDate ? date : nil, judgments: hasJudgments ? judgments : nil, playClear: playClear, bestClear: bestClear, modifier: try optionalCount(modifier), health: try optionalCount(health), clearModifier: modifier.isEmpty, clearHealth: health.isEmpty)
            if case .edit(let play) = destination { try model.save(draft, editing: play.original.id) }
            else if case .correctBest = destination { try model.save(draft, correctingBest: true) }
            else { try model.save(draft) }
            dismiss()
        } catch { validation = error.localizedDescription }
    }
}

private struct ChartPickerView: View {
    @Environment(ArchiveModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: ChartID?
    @State private var search = ""
    @State private var customID = ""
    @State private var customDifficulty = Difficulty.future
    private var charts: [ChartMetadata] {
        model.catalog.charts.values.filter { search.isEmpty || model.title($0.id).localizedCaseInsensitiveContains(search) || $0.id.songID.localizedCaseInsensitiveContains(search) }.sorted { model.title($0.id) == model.title($1.id) ? $0.id.difficulty.rawValue < $1.id.difficulty.rawValue : model.title($0.id).localizedStandardCompare(model.title($1.id)) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Custom song ID", text: $customID).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("customSongID")
                    Picker("Difficulty", selection: $customDifficulty) { ForEach(Difficulty.allCases, id: \.self) { Text($0.label).tag($0) } }
                    Button("Use custom chart") { selected = ChartID(songID: customID.trimmingCharacters(in: .whitespacesAndNewlines), difficulty: customDifficulty); dismiss() }.disabled(customID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("useCustomChart")
                } header: { Text("Chart not listed?") } footer: { Text("Custom charts can be saved and edited. Their rating stays unknown until chart metadata is available.") }
                Section("Known charts") { ForEach(charts, id: \.id) { metadata in Button { selected = metadata.id; dismiss() } label: { HStack { Text(model.title(metadata.id)); Spacer(); ChartBadge(chart: metadata.id, level: metadata.level) } } } }
            }
            .navigationTitle("Choose chart").searchable(text: $search, prompt: "Song title or ID")
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}
