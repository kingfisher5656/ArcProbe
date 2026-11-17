import ArcaeaCore
import Foundation
import SwiftUI

enum DisplayFormat {
    static func score(_ value: Int) -> String { value.formatted(.number.grouping(.automatic)) }
    static func grade(_ value: Int) -> String {
        switch value { case 9_900_000...: "EX+"; case 9_800_000...: "EX"; case 9_500_000...: "AA"; case 9_200_000...: "A"; case 8_900_000...: "B"; case 8_600_000...: "C"; default: "D" }
    }
    static func date(_ timestamp: SourceTimestamp?) -> String {
        guard let date = timestamp?.date else { return String(localized: "Date unknown") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    static func clear(_ clear: ClearType?) -> String {
        guard let clear else { return "Unknown" }
        return switch clear { case .trackLost: "Track Lost"; case .normal: "Normal Clear"; case .fullRecall: "Full Recall"; case .pureMemory: "Pure Memory"; case .easy: "Easy Clear"; case .hard: "Hard Clear" }
    }
    /// Where a play came from, in English: what exported files hold, so they read the same on every device.
    static func sourceName(_ source: ObservationSource) -> String {
        switch source { case .officialImport: "Official import"; case .officialRecent: "Official recent"; case .manual: "Manual entry"; case .consultantSheet: "Consultant sheet"; case .gameData: "Game folder" }
    }
    /// Where a play came from, in the user's language.
    static func source(_ source: ObservationSource) -> String {
        switch source { case .officialImport: String(localized: "Official import"); case .officialRecent: String(localized: "Official recent"); case .manual: String(localized: "Manual entry"); case .consultantSheet: String(localized: "Consultant sheet"); case .gameData: String(localized: "Game folder") }
    }
}

extension Difficulty {
    var color: Color {
        switch self { case .past: .cyan; case .present: .green; case .future: .purple; case .beyond: .red; case .eternal: .indigo }
    }
}

extension ArchiveModel {
    var selectedProfile: AccountProfile? { profiles.first { $0.id == selectedAccountID } }
    func title(_ chart: ChartID) -> String { catalog[chart]?.title ?? chart.songID }
    func artist(_ chart: ChartID) -> String? { catalog[chart]?.artist }
    /// Every way the play reached the archive. `forFile` gives the English names that exported files use.
    func sourceLabel(_ play: EffectiveObservation, forFile: Bool = false) -> String {
        let sources = captureSources[play.original.id] ?? [play.original.source]
        return sources.map(forFile ? DisplayFormat.sourceName : DisplayFormat.source).sorted().joined(separator: " · ")
    }
    func playRatingUnits(_ chart: ChartID, values: ScoreValues) -> Int64? {
        guard let constant = catalog[chart]?.usableConstant else { return nil }
        return try? RatingCalculator.play(constant: constant, score: values.score, clear: values.playClear)
    }
    func playRating(_ chart: ChartID, values: ScoreValues) -> String {
        playRatingUnits(chart, values: values).map { RatingCalculator.display($0) } ?? String(localized: "Unrated")
    }
    func rating(_ chart: ChartID) -> String {
        guard let units = ranking?.rows.first(where: { $0.best.chartID == chart })?.ratingUnits else { return String(localized: "Unrated") }
        return RatingCalculator.display(units)
    }
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}
