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
    static func jpg(model: ArchiveModel) throws -> ShareFile {
        let size = CGSize(width: 1800, height: 3100)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rows = Array(model.ranking?.rows.prefix(50) ?? [])
        let data = renderer.jpegData(withCompressionQuality: 0.92) { context in
            let cg = context.cgContext
            UIColor(red: 0.95, green: 0.94, blue: 0.98, alpha: 1).setFill(); cg.fill(CGRect(origin: .zero, size: size))
            let purple = UIColor(red: 0.33, green: 0.22, blue: 0.48, alpha: 1)
            purple.setFill(); cg.fill(CGRect(x: 0, y: 0, width: 1800, height: 350))
            text("ARCPROBE", at: CGRect(x: 70, y: 52, width: 1600, height: 72), size: 50, color: .white, weight: .bold)
            text("BEST 50  /  \(model.selectedProfile?.displayName ?? model.selectedProfile?.id.rawValue ?? "Local archive")", at: CGRect(x: 74, y: 143, width: 1100, height: 62), size: 31, color: UIColor.white.withAlphaComponent(0.85), weight: .medium)
            text(model.ranking.map { RatingCalculator.display($0.potentialUnits) } ?? "—", at: CGRect(x: 1390, y: 115, width: 330, height: 88), size: 60, color: .white, weight: .semibold, align: .right)
            text("Saved-score potential · local estimate", at: CGRect(x: 1050, y: 220, width: 670, height: 55), size: 23, color: UIColor.white.withAlphaComponent(0.85), align: .right)
            text("Generated \(Date().formatted(date: .abbreviated, time: .shortened))", at: CGRect(x: 74, y: 236, width: 1100, height: 50), size: 23, color: UIColor.white.withAlphaComponent(0.75))
            let gap: CGFloat = 20, width: CGFloat = 316, height: CGFloat = 246
            for index in 0..<50 {
                let x = 70 + CGFloat(index % 5) * (width + gap), y = 390 + CGFloat(index / 5) * (height + gap)
                let card = CGRect(x: x, y: y, width: width, height: height)
                UIColor.white.setFill(); UIBezierPath(roundedRect: card, cornerRadius: 16).fill()
                guard index < rows.count else { text("—", at: card.insetBy(dx: 25, dy: 80), size: 28, color: .lightGray); continue }
                let row = rows[index], best = row.best, metadata = model.catalog[best.chartID]
                let accent = UIColor(best.chartID.difficulty.color)
                accent.withAlphaComponent(0.12).setFill(); UIBezierPath(roundedRect: CGRect(x: x + 14, y: y + 14, width: 288, height: 38), cornerRadius: 9).fill()
                text(row.rank.map { "#\($0)" } ?? "Unrated", at: CGRect(x: x + 26, y: y + 20, width: 110, height: 26), size: 20, color: purple, weight: .bold)
                text("\((metadata?.displayDifficulty ?? best.chartID.difficulty.label)) \(metadata?.level ?? "?")", at: CGRect(x: x + 155, y: y + 20, width: 134, height: 26), size: 20, color: accent, weight: .bold, align: .right)
                text(model.title(best.chartID), at: CGRect(x: x + 24, y: y + 68, width: 268, height: 49), size: 23, color: .darkGray, weight: .semibold)
                text(DisplayFormat.score(best.values.score), at: CGRect(x: x + 24, y: y + 125, width: 220, height: 32), size: 27, color: purple, weight: .semibold)
                text(DisplayFormat.grade(best.values.score), at: CGRect(x: x + 230, y: y + 127, width: 60, height: 28), size: 22, color: accent, weight: .bold, align: .right)
                text(DisplayFormat.clear(best.bestClear), at: CGRect(x: x + 24, y: y + 174, width: 185, height: 23), size: 17, color: .gray)
                let source = model.observations.first { $0.original.id == best.observationID }?.original.source
                let sourceLabel = best.isOverridden || best.isBestCorrection ? "Corrected" : source == .manual ? "Manual" : source == .officialRecent ? "Recent" : "Imported"
                let dateLabel = best.values.playedAt?.date?.formatted(date: .abbreviated, time: .omitted) ?? "Date unknown"
                text(sourceLabel + " · " + dateLabel, at: CGRect(x: x + 24, y: y + 212, width: 268, height: 21), size: 15, color: .gray)
                text(row.ratingUnits.map { RatingCalculator.display($0) } ?? "—", at: CGRect(x: x + 210, y: y + 171, width: 82, height: 27), size: 21, color: purple, weight: .semibold, align: .right)
            }
            text("Dated chart constants · unknown data stays unknown · manual corrections are local", at: CGRect(x: 70, y: 3070, width: 1660, height: 32), size: 20, color: .gray)
        }
        return try write(data, ext: "jpg")
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
    private static func text(_ value: String, at rect: CGRect, size: CGFloat, color: UIColor, weight: UIFont.Weight = .regular, align: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = align; paragraph.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in: rect, withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
    }
}
