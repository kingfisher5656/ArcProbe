import ArcaeaCore
import Foundation
import SwiftUI

enum DisplayFormat {
    static func score(_ value: Int) -> String { value.formatted(.number.grouping(.automatic)) }
    static func grade(_ value: Int) -> String {
        switch value { case 9_900_000...: "EX+"; case 9_800_000...: "EX"; case 9_500_000...: "AA"; case 9_200_000...: "A"; case 8_900_000...: "B"; case 8_600_000...: "C"; default: "D" }
    }
    static func date(_ timestamp: SourceTimestamp?) -> String {
        guard let date = timestamp?.date else { return "Date unknown" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    static func clear(_ clear: ClearType?) -> String {
        guard let clear else { return "Unknown" }
        return switch clear { case .trackLost: "Track Lost"; case .normal: "Normal Clear"; case .fullRecall: "Full Recall"; case .pureMemory: "Pure Memory"; case .easy: "Easy Clear"; case .hard: "Hard Clear" }
    }
    static func source(_ source: ObservationSource) -> String {
        switch source { case .officialImport: "Official import"; case .officialRecent: "Official recent"; case .manual: "Manual entry" }
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
    func sourceLabel(_ play: EffectiveObservation) -> String {
        let sources = captureSources[play.original.id] ?? [play.original.source]
        return sources.map(DisplayFormat.source).sorted().joined(separator: " · ")
    }
    func playRatingUnits(_ chart: ChartID, values: ScoreValues) -> Int64? {
        guard let constant = catalog[chart]?.usableConstant else { return nil }
        return try? RatingCalculator.play(constant: constant, score: values.score, clear: values.playClear)
    }
    func playRating(_ chart: ChartID, values: ScoreValues) -> String {
        playRatingUnits(chart, values: values).map { RatingCalculator.display($0) } ?? "Unrated"
    }
    func rating(_ chart: ChartID) -> String {
        guard let units = ranking?.rows.first(where: { $0.best.chartID == chart })?.ratingUnits else { return "Unrated" }
        return RatingCalculator.display(units)
    }
    func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}
