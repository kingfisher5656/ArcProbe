import ArcaeaCore
import SwiftUI

struct ScoresView: View {
    enum Sort: String, CaseIterable, Identifiable {
        // The raw values are what is saved in the user's settings; `title` is what is shown.
        case name = "Name", rating = "Play rating", score = "Score", constant = "Chart constant", date = "Date played"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .name: String(localized: "Name")
            case .rating: String(localized: "Play rating")
            case .score: String(localized: "Score")
            case .constant: String(localized: "Chart constant")
            case .date: String(localized: "Date played")
            }
        }
    }
    @Environment(ArchiveModel.self) private var model
    @AppStorage("scores.sort") private var sort = Sort.name
    @State private var query = ""
    @State private var difficulties: Set<Difficulty> = []
    @State private var packID: String?
    @State private var level: String?
    @State private var clear: ClearType?
    @State private var editor: ScoreEditorDestination?
    private var packs: PackCatalog { LibraryResources.shared.packs }
    /// Only packs that hold at least one saved score are offered.
    private var packGroups: [PackCatalog.Group] { packs.groups(forSongs: model.bestScores.map(\.chartID.songID)) }
    /// A pack that no longer holds a score (another account, a deleted play) stops filtering.
    private var activePack: Pack? { packGroups.lazy.flatMap(\.packs).first { $0.id == packID } }
    /// Levels that have a saved score, lowest first ("9", "9+", "10").
    private var levels: [String] {
        func order(_ level: String) -> Double {
            (Double(level.prefix { $0.isNumber }) ?? 99) + (level.hasSuffix("+") ? 0.5 : 0)
        }
        return Set(model.bestScores.compactMap { model.catalog[$0.chartID]?.level }).sorted { (order($0), $0) < (order($1), $1) }
    }
    private var activeLevel: String? { level.flatMap { levels.contains($0) ? $0 : nil } }
    private var filtering: Bool { activePack != nil || activeLevel != nil || clear != nil || !difficulties.isEmpty }

    private func visible(ratings: [ChartID: Int64]) -> [BestScore] {
        let pack = activePack?.id, level = activeLevel
        let matches = model.bestScores.filter { best in
            let chart = best.chartID
            return (difficulties.isEmpty || difficulties.contains(chart.difficulty))
                && (pack == nil || packs.pack(forSong: chart.songID)?.id == pack)
                && (level == nil || model.catalog[chart]?.level == level)
                && (clear == nil || best.bestClear == clear)
                && (query.isEmpty || model.title(chart).localizedCaseInsensitiveContains(query) || chart.songID.localizedCaseInsensitiveContains(query))
        }
        func byName(_ first: BestScore, _ second: BestScore) -> Bool {
            let comparison = model.title(first.chartID).localizedStandardCompare(model.title(second.chartID))
            return comparison == .orderedSame ? first.chartID.key < second.chartID.key : comparison == .orderedAscending
        }
        /// Highest first; charts where the value is unknown go last, in name order.
        func descending<Value: Comparable>(_ value: (BestScore) -> Value?) -> [BestScore] {
            matches.sorted { first, second in
                switch (value(first), value(second)) {
                case let (a?, b?) where a != b: a > b
                case (_?, nil): true
                case (nil, _?): false
                default: byName(first, second)
                }
            }
        }
        return switch sort {
        case .name: matches.sorted(by: byName)
        case .rating: descending { ratings[$0.chartID] }
        case .score: descending { $0.values.score }
        case .constant: descending { model.catalog[$0.chartID]?.usableConstant?.tenths }
        case .date: descending { $0.values.playedAt?.date }
        }
    }

    var body: some View {
        let ratings = Dictionary((model.ranking?.rows ?? []).compactMap { row in row.ratingUnits.map { (row.best.chartID, $0) } }, uniquingKeysWith: { first, _ in first })
        let rows = visible(ratings: ratings)
        List {
            Section {
                ForEach(rows, id: \.chartID) { best in
                    NavigationLink { ScoreDetailView(chart: best.chartID) } label: {
                        ScoreRow(chart: best.chartID, values: best.values, override: best.isOverridden || best.isBestCorrection,
                                 clear: best.bestClear, rating: ratings[best.chartID].map { RatingCalculator.display($0) } ?? String(localized: "Unrated"))
                    }
                }
            } header: {
                if !model.bestScores.isEmpty {
                    let total = model.bestScores.count
                    if rows.count == total { Text("\(total) chart bests") } else { Text("\(rows.count) of \(total) chart bests") }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { if !model.bestScores.isEmpty { filterBar } }
        .overlay { if model.bestScores.isEmpty { EmptyArchiveView(title: "No saved scores", systemImage: "music.note.list") { editor = .add } } else if rows.isEmpty {
            if query.isEmpty { ContentUnavailableView("No scores match", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try other filters.")) }
            else { ContentUnavailableView.search(text: query) }
        } }
        .navigationTitle("Scores").searchable(text: $query, prompt: "Search song title or ID")
        .toolbar { Button("Add score", systemImage: "plus") { editor = .add }.accessibilityIdentifier("addScore") }
        .sheet(item: $editor) { ScoreEditorView(destination: $0) }
    }

    /// Stays in place above the list, so sorting and filtering are one tap away at any scroll position.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Sort by", selection: $sort) { ForEach(Sort.allCases) { Text($0.title).tag($0) } }
                } label: { chip(sort.title, systemImage: "arrow.up.arrow.down") }.accessibilityLabel("Sort by \(sort.title)").accessibilityIdentifier("scores.sort")
                Divider().frame(height: 22)
                ForEach(Difficulty.allCases, id: \.self) { difficulty in
                    let on = difficulties.contains(difficulty)
                    Button { if on { difficulties.remove(difficulty) } else { difficulties.insert(difficulty) } } label: {
                        chip(difficulty.label, tint: on ? difficulty.color : nil, menu: false)
                    }.accessibilityAddTraits(on ? .isSelected : [])
                }
                Divider().frame(height: 22)
                if !packGroups.isEmpty {
                    let counts = Dictionary(model.bestScores.compactMap { packs.pack(forSong: $0.chartID.songID)?.id }.map { ($0, 1) }, uniquingKeysWith: +)
                    Menu {
                        Picker("Pack", selection: Binding(get: { activePack?.id }, set: { packID = $0 })) {
                            Text("All packs").tag(String?.none)
                            ForEach(packGroups) { group in
                                Section(group.title) { ForEach(group.packs) { Text(verbatim: "\($0.name) (\(counts[$0.id] ?? 0))").tag(Optional($0.id)) } }
                            }
                        }
                    } label: { chip(activePack?.name ?? String(localized: "Pack"), tint: activePack == nil ? nil : .accentColor) }.accessibilityIdentifier("scores.pack")
                }
                if !levels.isEmpty {
                    Menu {
                        Picker("Level", selection: Binding(get: { activeLevel }, set: { level = $0 })) {
                            Text("All levels").tag(String?.none)
                            ForEach(levels, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                    } label: { chip(activeLevel.map { String(localized: "Level \($0)") } ?? String(localized: "Level"), tint: activeLevel == nil ? nil : .accentColor) }.accessibilityIdentifier("scores.level")
                }
                Menu {
                    Picker("Clear", selection: $clear) {
                        Text("Any clear").tag(ClearType?.none)
                        ForEach(ClearType.allCases.sorted { $0.precedence > $1.precedence }, id: \.self) { Text(DisplayFormat.clear($0)).tag(Optional($0)) }
                    }
                } label: { chip(clear.map(DisplayFormat.clear) ?? String(localized: "Clear"), tint: clear == nil ? nil : .accentColor) }.accessibilityIdentifier("scores.clear")
                if filtering {
                    Button("Clear filters", systemImage: "xmark.circle.fill") { difficulties = []; packID = nil; level = nil; clear = nil }
                        .labelStyle(.iconOnly).font(.title3).foregroundStyle(.secondary).accessibilityIdentifier("scores.clearFilters")
                }
            }
            .buttonStyle(.plain).padding(.horizontal, 20).padding(.vertical, 8)
        }
        .background(.bar)
    }

    /// One look for every control in the bar. A tint marks a filter that is switched on.
    private func chip(_ title: String, systemImage: String? = nil, tint: Color? = nil, menu: Bool = true) -> some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.caption.weight(.semibold)) }
            Text(title).lineLimit(1)
            if menu { Image(systemName: "chevron.down").font(.caption2.weight(.bold)).opacity(0.6) }
        }
        .font(.subheadline.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 7)
        .foregroundStyle(tint ?? Color.primary)
        .background((tint ?? Color(.systemFill)).opacity(tint == nil ? 1 : 0.16), in: Capsule())
        .overlay { if let tint { Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1) } }
        .contentShape(Capsule())
    }
}
