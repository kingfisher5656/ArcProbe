import SwiftUI
import ArcaeaCore

/// The Settings screens that can be opened directly, from a row in Settings or from a button elsewhere in the app.
enum SettingsRoute: Hashable { case mainAccount, trackerAccount, shortcuts, gameFolder, sheet, library, backup, diagnostics }

/// Where the app is, beyond the selected tab. One instance, shared through the environment.
@MainActor @Observable final class AppNavigation {
    var settingsOpen = false
    /// Screens pushed on top of the Settings list.
    var settingsPath: [SettingsRoute] = []
    /// Opens Settings, at one of its screens when `route` is given.
    func openSettings(_ route: SettingsRoute? = nil) {
        settingsPath = route.map { [$0] } ?? []
        settingsOpen = true
    }
}

struct RootView: View {
    @State private var navigation = AppNavigation()
    var body: some View {
        // Four tabs fit the iPad's top bar in every orientation; a fifth scrolls out of view.
        // Settings is therefore a sheet opened by a gear button on each tab instead of a tab.
        TabView {
            Tab("Best 50", systemImage: "square.grid.2x2") { NavigationStack { OverviewView().settingsButton() } }
            Tab("Scores", systemImage: "music.note.list") { NavigationStack { ScoresView().settingsButton() } }
            Tab("Recent", systemImage: "clock.arrow.circlepath") { NavigationStack { RecentView().settingsButton() } }
            Tab("Potential", systemImage: "chart.xyaxis.line") { NavigationStack { PotentialView().settingsButton() } }
        }
        .tint(.purple)
        .feedback(active: !navigation.settingsOpen)
        .sheet(isPresented: $navigation.settingsOpen) { SettingsSheet().environment(navigation).tint(.purple) }
        .environment(navigation)
    }
}

/// Settings in its own sheet: the same screen from every tab, closed with Done.
private struct SettingsSheet: View {
    @Environment(AppNavigation.self) private var navigation
    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.settingsPath) {
            SettingsView()
                .toolbar { done }
                .navigationDestination(for: SettingsRoute.self) { route in
                    Group {
                        switch route {
                        case .mainAccount: MainAccountView()
                        case .trackerAccount: TrackerAccountView()
                        case .shortcuts: ShortcutSetupView()
                        case .gameFolder: GameDataView()
                        case .sheet: SheetView()
                        case .library: LibraryView()
                        case .backup: BackupView()
                        case .diagnostics: DiagnosticsView()
                        }
                    }.toolbar { done }
                }
        }
        .presentationSizing(.page)
        // The sheet covers the tabs, so messages and errors raised while it is open are shown on the sheet.
        .feedback(active: true)
    }
    private var done: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { navigation.settingsOpen = false }.accessibilityIdentifier("settings.done") }
    }
}

/// The message bar (with Undo) and the error alert. Shown by whichever layer is in front.
private struct Feedback: ViewModifier {
    @Environment(ArchiveModel.self) private var model
    let active: Bool
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if active, let notice = model.notice {
                    HStack(spacing: 14) {
                        Text(notice).font(.subheadline)
                        if model.undoToken != nil { Button("Undo") { model.perform { try model.undoLastChange() }; model.notice = nil }.fontWeight(.semibold).accessibilityIdentifier("undoChange") }
                        Button { model.notice = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss message")
                    }
                    .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal).padding(.bottom, 12).shadow(radius: 8, y: 4)
                }
            }
            .alert("Couldn’t finish", isPresented: Binding(get: { active && model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }
}
private extension View {
    func feedback(active: Bool) -> some View { modifier(Feedback(active: active)) }
}

private struct SettingsButton: ViewModifier {
    @Environment(OnlineRuntime.self) private var runtime
    @Environment(AppNavigation.self) private var navigation
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { navigation.openSettings() } label: {
                        Image(systemName: "gearshape")
                            .overlay(alignment: .topTrailing) {
                                if runtime.recentNeedsAttention { Circle().fill(.orange).frame(width: 9, height: 9).offset(x: 3, y: -3) }
                            }
                    }
                    .accessibilityLabel(runtime.recentNeedsAttention ? "Settings, tracker needs attention" : "Settings")
                    .accessibilityIdentifier("openSettings")
                }
            }
    }
}
extension View {
    /// Adds the gear that opens Settings. Use on the root screen of each tab.
    func settingsButton() -> some View { modifier(SettingsButton()) }
}

/// What an empty archive offers instead of an instruction to go and find the right screen.
struct EmptyArchiveView: View {
    @Environment(AppNavigation.self) private var navigation
    let title: LocalizedStringKey
    let systemImage: String
    /// Opens the score editor of the screen that shows this.
    let addScore: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text("Bring in the scores you already have, or add one by hand.")
        } actions: {
            Button("Import from Arcaea Online") { navigation.openSettings(.mainAccount) }.buttonStyle(.borderedProminent)
                .accessibilityIdentifier("empty.importOnline")
            Button("Import from the Arcaea game folder") { navigation.openSettings(.gameFolder) }.accessibilityIdentifier("empty.importFolder")
            Button("Add a score by hand", action: addScore).accessibilityIdentifier("empty.addScore")
        }
    }
}

struct ChartBadge: View {
    @Environment(ArchiveModel.self) private var model
    let chart: ChartID
    var level: String? = nil
    var body: some View {
        let difficulty = model.catalog[chart]?.displayDifficulty ?? chart.difficulty.label
        // INS shares BYD's stored difficulty; match its exported diamond's #283D8C blue.
        // On a dark background that navy is unreadable, so dark mode uses a lighter tint of the same hue.
        let color = difficulty.uppercased() == "INS"
            ? Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
                ? UIColor(red: 138.0 / 255, green: 160.0 / 255, blue: 245.0 / 255, alpha: 1)
                : UIColor(red: 40.0 / 255, green: 61.0 / 255, blue: 140.0 / 255, alpha: 1) })
            : chart.difficulty.color
        Text(difficulty + (level.map { "  \($0)" } ?? ""))
            .font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(color).background(color.opacity(0.12), in: Capsule())
    }
}

struct CoverArtwork: View {
    @Environment(ArchiveModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    let chart: ChartID
    private struct Request: Equatable {
        let identifiers: [String]
        let pixels: Int
        let revision: Int
    }
    var body: some View {
        GeometryReader { proxy in
            let identifiers = LibraryResources.coverIdentifiers(chart: chart, official: model.catalog[chart]?.artworkIdentifier)
            let pixels = Int(ceil(max(proxy.size.width, proxy.size.height) * displayScale / 128)) * 128
            let request = Request(identifiers: identifiers, pixels: min(1536, max(128, pixels)), revision: LibraryResources.shared.revision)
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [chart.difficulty.color.opacity(0.7), .indigo.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "waveform").font(.system(size: min(proxy.size.width, proxy.size.height) * 0.35, weight: .light)).foregroundStyle(.white.opacity(0.85))
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
                .task(id: request) {
                    let loaded = await CoverImageLoader.shared.image(identifiers: request.identifiers, pixels: request.pixels, revision: request.revision)
                    guard !Task.isCancelled else { return }
                    image = loaded
                }
                .onDisappear { image = nil }
        }.accessibilityHidden(true)
    }
}
struct CoverPlaceholder: View {
    let chart: ChartID
    var size: CGFloat = 64
    var body: some View {
        CoverArtwork(chart: chart).frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ScoreRow: View {
    @Environment(ArchiveModel.self) private var model
    let chart: ChartID
    let values: ScoreValues
    var rank: Int? = nil
    var override: Bool = false
    var showsPlayRating = false
    /// The lamp to show: a chart's best clear in a list of bests, the play's own clear in a list of plays.
    var clear: ClearType? = nil
    /// A list that already worked out its ratings passes the text, so each row does not search the ranking.
    var rating: String? = nil
    /// Replaces the date line, for a list that words it differently (Recent shows only the time inside a day).
    var detail: String? = nil
    /// How the play compares with the chart's earlier best, in a list of plays.
    var change: PlayChange? = nil
    var body: some View {
        HStack(spacing: 12) {
            CoverPlaceholder(chart: chart, size: 56)
            VStack(alignment: .leading, spacing: 5) {
                HStack { if let rank { Text(verbatim: "#\(rank)").foregroundStyle(.secondary) }; Text(model.title(chart)).font(.headline).lineLimit(1) }
                HStack(spacing: 10) { ChartBadge(chart: chart, level: model.catalog[chart]?.level); ClearLamp(clear: clear); if override { Label("Edited", systemImage: "pencil").font(.caption).foregroundStyle(.orange) } }
                // An unknown date is left out: on imported scores it would repeat on every row.
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                else if values.playedAt?.date != nil { Text(DisplayFormat.date(values.playedAt)).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text(DisplayFormat.score(values.score)).font(.headline.monospacedDigit())
                HStack(spacing: 8) { Text(DisplayFormat.grade(values.score)).fontWeight(.semibold); Text(rating ?? (showsPlayRating ? model.playRating(chart, values: values) : model.rating(chart))) }.font(.caption).foregroundStyle(.secondary)
                if let change { PlayChangeLabel(change: change) }
            }
        }.padding(.vertical, 2)
    }
}
