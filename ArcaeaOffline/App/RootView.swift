import SwiftUI
import ArcaeaCore

struct RootView: View {
    @Environment(ArchiveModel.self) private var model
    var body: some View {
        TabView {
            Tab("Best 50", systemImage: "square.grid.2x2") { NavigationStack { OverviewView() } }
            Tab("Scores", systemImage: "music.note.list") { NavigationStack { ScoresView() } }
            Tab("Recent", systemImage: "clock.arrow.circlepath") { NavigationStack { RecentView() } }
            Tab("Potential", systemImage: "chart.xyaxis.line") { NavigationStack { PotentialView() } }
            Tab("Settings", systemImage: "gearshape") { NavigationStack { SettingsView() } }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tint(.purple)
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                HStack(spacing: 14) {
                    Text(notice).font(.subheadline)
                    if model.undoToken != nil { Button("Undo") { model.perform { try model.undoLastChange() }; model.notice = nil }.fontWeight(.semibold).accessibilityIdentifier("undoChange") }
                    Button { model.notice = nil } label: { Image(systemName: "xmark") }.accessibilityLabel("Dismiss message")
                }
                .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal).padding(.bottom, 12).shadow(radius: 8, y: 4)
            }
        }
        .alert("Couldn’t finish", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

struct ChartBadge: View {
    @Environment(ArchiveModel.self) private var model
    let chart: ChartID
    var level: String? = nil
    var body: some View {
        Text((model.catalog[chart]?.displayDifficulty ?? chart.difficulty.label) + (level.map { "  \($0)" } ?? ""))
            .font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(chart.difficulty.color).background(chart.difficulty.color.opacity(0.12), in: Capsule())
    }
}

struct CoverArtwork: View {
    @Environment(ArchiveModel.self) private var model
    let chart: ChartID
    var body: some View {
        let resources = LibraryResources.shared
        let _ = resources.revision
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [chart.difficulty.color.opacity(0.7), .indigo.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image = resources.image(for: model.catalog[chart]?.artworkIdentifier) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "waveform").font(.system(size: min(proxy.size.width, proxy.size.height) * 0.35, weight: .light)).foregroundStyle(.white.opacity(0.85))
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
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
    var body: some View {
        HStack(spacing: 12) {
            CoverPlaceholder(chart: chart)
            VStack(alignment: .leading, spacing: 5) {
                HStack { if let rank { Text("#\(rank)").foregroundStyle(.secondary) }; Text(model.title(chart)).font(.headline).lineLimit(1) }
                HStack { ChartBadge(chart: chart, level: model.catalog[chart]?.level); if override { Label("Edited", systemImage: "pencil").font(.caption).foregroundStyle(.orange) } }
                Text(DisplayFormat.date(values.playedAt)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text(DisplayFormat.score(values.score)).font(.headline.monospacedDigit())
                HStack(spacing: 8) { Text(DisplayFormat.grade(values.score)).fontWeight(.semibold); Text(showsPlayRating ? model.playRating(chart, values: values) : model.rating(chart)) }.font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
