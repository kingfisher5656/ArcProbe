import ArcaeaCore
import SwiftUI
import UIKit

struct ShareFile: Identifiable { let url: URL; var id: URL { url } }
struct ShareSheet: UIViewControllerRepresentable {
    let file: ShareFile
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [file.url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

@MainActor enum ScoreExportService {
    static func csv(model: ArchiveModel) throws -> ShareFile {
        let rows = Array(model.ranking?.rows.prefix(50) ?? [])
        let header = ["rank", "song_id", "title", "artist", "difficulty", "level", "constant", "score", "grade", "play_rating_estimate", "play_clear", "best_clear", "played_at", "date_origin", "source", "manual_correction", "pure", "shiny_pure", "far", "lost", "early", "late"]
        var lines = [header.joined(separator: ",")]
        for row in rows {
            let best = row.best, values = best.values, metadata = model.catalog[best.chartID]
            let sourceLabel = model.observations.first { $0.original.id == best.observationID }.map { model.sourceLabel($0) } ?? "manual best correction"
            let fields = [row.rank.map(String.init) ?? "unrated", best.chartID.songID, model.title(best.chartID), metadata?.artist ?? "unknown", (metadata?.displayDifficulty ?? best.chartID.difficulty.label), metadata?.level ?? "unknown", metadata?.usableConstant.map { String(format: "%.1f", $0.value) } ?? "unknown", String(values.score), DisplayFormat.grade(values.score), row.ratingUnits.map { RatingCalculator.display($0) } ?? "unknown", DisplayFormat.clear(values.playClear), DisplayFormat.clear(best.bestClear), values.playedAt?.date?.ISO8601Format() ?? "unknown", values.playedAt?.origin.rawValue ?? "unknown", sourceLabel, best.isOverridden || best.isBestCorrection ? "true" : "false", count(values.judgments?.pure), count(values.judgments?.shinyPure), count(values.judgments?.far), count(values.judgments?.lost), count(values.judgments?.early), count(values.judgments?.late)]
            lines.append(fields.map(csvCell).joined(separator: ","))
        }
        return try write(Data((lines.joined(separator: "\n") + "\n").utf8), ext: "csv")
    }
    static func jpg(model: ArchiveModel, coverLoader: CoverImageLoader = .shared, partnerLoader: PartnerArtworkLoader = .shared) async throws -> ShareFile {
        // Freeze the data before awaiting artwork so a background import cannot mix snapshots.
        let rows = Array(model.ranking?.rows.prefix(50) ?? [])
        let profile = model.selectedProfile?.displayName ?? model.selectedProfile?.id.rawValue ?? "Local archive"
        let potential = model.ranking.map { RatingCalculator.display($0.potentialUnits) } ?? "—"
        let partnerIcon = model.selectedProfile?.partnerIcon
        let generatedAt = Date()
        let revision = LibraryResources.shared.revision
        var cards = rows.map { row in
            B50PosterRenderer.Card(row: row, title: model.title(row.best.chartID), metadata: model.catalog[row.best.chartID])
        }
        for index in cards.indices {
            try Task.checkCancellation()
            let chart = cards[index].row.best.chartID
            let identifiers = ["wiki:\(chart.songID):\(chart.difficulty.rawValue)"]
                + (cards[index].metadata?.artworkIdentifier.map { [$0] } ?? [])
            cards[index].cover = await coverLoader.image(identifiers: identifiers, pixels: 360, revision: revision)
        }
        try Task.checkCancellation()
        let partner = await partnerLoader.image(identifier: partnerIcon)
        try Task.checkCancellation()
        return try write(B50PosterRenderer.render(cards: cards, player: profile, potential: potential, generatedAt: generatedAt, partner: partner), ext: "jpg")
    }
    private static func count(_ value: Int?) -> String { value.map(String.init) ?? "unknown" }
    private static func csvCell(_ input: String) -> String {
        let value = ["=", "+", "-", "@"].contains(where: { input.hasPrefix($0) }) ? "'" + input : input
        return value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
    }
    private static func write(_ data: Data, ext: String) throws -> ShareFile {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaeaOfflineExports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("ArcProbe-B50-\(UUID().uuidString.prefix(8)).\(ext)")
        try data.write(to: url, options: .atomic)
        return ShareFile(url: url)
    }
}
