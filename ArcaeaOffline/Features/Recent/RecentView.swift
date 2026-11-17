import ArcaeaCore
import SwiftUI

/// Plays gathered the way a browser gathers its history: one group per recent day, one per older month.
struct RecentGroup: Identifiable, Equatable {
    enum Kind: Hashable {
        case today, yesterday
        /// A day earlier this week, as the start of that day.
        case day(Date)
        /// Everything older, as the start of the month.
        case month(Date)
        /// Plays whose date was never recorded.
        case unknown
    }
    let kind: Kind
    var plays: [EffectiveObservation]
    var id: Kind { kind }
    /// Today and yesterday start open; older groups start closed.
    var opensByDefault: Bool { kind == .today || kind == .yesterday }
    /// Rows in a one-day group show only the time; the group already names the day.
    var isSingleDay: Bool { if case .month = kind { false } else { kind != .unknown } }

    /// Newest group first, newest play first inside each. Plays without a date come last and are never given one.
    static func groups(_ plays: [EffectiveObservation], now: Date, calendar: Calendar = .current) -> [RecentGroup] {
        let today = calendar.startOfDay(for: now)
        func kind(_ date: Date) -> Kind {
            let day = calendar.startOfDay(for: date)
            let age = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            if age <= 0 { return .today } // a clock that runs ahead must not open a group for "tomorrow"
            if age == 1 { return .yesterday }
            if age < 7 { return .day(day) }
            return .month(calendar.dateInterval(of: .month, for: date)?.start ?? day)
        }
        var groups: [RecentGroup] = []
        let dated = plays.compactMap { play in play.values.playedAt?.date.map { (date: $0, play: play) } }
            .sorted { ($0.date, $0.play.original.id.rawValue) > ($1.date, $1.play.original.id.rawValue) }
        for (date, play) in dated {
            let kind = kind(date)
            if groups.last?.kind == kind { groups[groups.count - 1].plays.append(play) } else { groups.append(RecentGroup(kind: kind, plays: [play])) }
        }
        let undated = plays.filter { $0.values.playedAt?.date == nil }
            .sorted { ($0.original.firstSeenAt, $0.original.id.rawValue) > ($1.original.firstSeenAt, $1.original.id.rawValue) }
        if !undated.isEmpty { groups.append(RecentGroup(kind: .unknown, plays: undated)) }
        return groups
    }
}

struct RecentView: View {
    @Environment(ArchiveModel.self) private var model
    @State private var recentOnly = true
    /// Groups opened or closed by hand. The others follow `RecentGroup.opensByDefault`.
    @State private var opened: [RecentGroup.Kind: Bool] = [:]
    @State private var editor: ScoreEditorDestination?

    var body: some View {
        let plays = recentOnly ? model.recentObservations : model.observations
        let groups = RecentGroup.groups(plays, now: Date())
        // Compared against every saved play of the chart, not only the tracked ones.
        let changes = PlayHistory.changes(model.observations)
        List {
            Section { TrackingStatusCard(showsActions: true) }
            Section {
                Picker("Show", selection: $recentOnly) { Text("Tracked plays").tag(true); Text("All saved plays").tag(false) }.pickerStyle(.segmented)
            }
            if plays.isEmpty {
                Section {
                    Group {
                        if recentOnly {
                            ContentUnavailableView("No tracked plays yet", systemImage: "clock", description: Text("Plays appear here as you finish them while Arcaea is open."))
                        } else {
                            EmptyArchiveView(title: "No saved plays", systemImage: "clock") { editor = .add }
                        }
                    }.padding(.vertical, 24).listRowBackground(Color.clear)
                }
            }
            ForEach(groups) { group in
                let isOpen = opened[group.kind] ?? group.opensByDefault
                Section {
                    Button { withAnimation { opened[group.kind] = !isOpen } } label: { header(group, changes: changes, isOpen: isOpen) }
                        .buttonStyle(.plain).accessibilityIdentifier("recent.group")
                        .accessibilityValue(isOpen ? Text("Expanded") : Text("Collapsed"))
                    if isOpen {
                        ForEach(group.plays, id: \.original.id) { play in
                            NavigationLink { ScoreDetailView(chart: play.original.chartID) } label: {
                                ScoreRow(chart: play.original.chartID, values: play.values, override: play.isOverridden, showsPlayRating: true,
                                         clear: play.values.playClear, detail: detail(play, in: group), change: changes[play.original.id])
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent plays")
        .sheet(item: $editor) { ScoreEditorView(destination: $0) }
    }

    private func header(_ group: RecentGroup, changes: [ObservationID: PlayChange], isOpen: Bool) -> some View {
        let bests = group.plays.filter { changes[$0.original.id]?.isNewBest == true }.count
        return HStack(spacing: 10) {
            // On the leading side, so it is not mistaken for the chevron of a row that opens a screen.
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                .rotationEffect(.degrees(isOpen ? 90 : 0)).frame(width: 14)
            Text(title(group.kind)).font(.headline)
            Spacer(minLength: 8)
            // Two counted phrases, each with its own singular and plural in the string catalog.
            (bests > 0 ? Text("\(group.plays.count) plays") + Text(verbatim: " · ") + Text("\(bests) new bests") : Text("\(group.plays.count) plays"))
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 4).contentShape(Rectangle())
    }
    private func title(_ kind: RecentGroup.Kind) -> String {
        switch kind {
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .day(let day): day.formatted(.dateTime.weekday(.wide).month().day())
        case .month(let month): month.formatted(.dateTime.month(.wide).year())
        case .unknown: String(localized: "Date unknown")
        }
    }
    /// The line under the badges: the time (or the full date in a month group), and where the play came from
    /// when the list mixes sources.
    private func detail(_ play: EffectiveObservation, in group: RecentGroup) -> String? {
        var parts: [String] = []
        if let date = play.values.playedAt?.date {
            parts.append(group.isSingleDay ? date.formatted(date: .omitted, time: .shortened) : date.formatted(date: .abbreviated, time: .shortened))
        }
        if !recentOnly { parts.append(model.sourceLabel(play)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
