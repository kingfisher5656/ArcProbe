import ArcaeaCore
import UIKit

/// Fixed print layout, measured against the supplied 1800 × 3208 reference.
/// Decorations are drawn locally; the reference image and its player data are never bundled.
@MainActor enum B50PosterRenderer {
    struct Card {
        let row: RankedScore
        let title: String
        let metadata: ChartMetadata?
        var cover: UIImage?
    }
    static let size = CGSize(width: 1800, height: 3208)
    private static let ink = color(0x302838)
    private static let lavender = color(0xbca3d4)

    static func render(cards: [Card], player: String, potential: String, generatedAt: Date, partner: UIImage? = nil) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.95) { renderer in
            let cg = renderer.cgContext
            background(cg)
            header(player: player, potential: potential, date: generatedAt, partner: partner, cg: cg)
            for index in 0..<50 {
                cg.saveGState()
                cg.translateBy(x: 85 + CGFloat(index % 5) * 334, y: 355 + CGFloat(index / 5) * 272)
                card(index < cards.count ? cards[index] : nil, cg: cg)
                cg.restoreGState()
            }
            label("ArcProbe · Best 50 from saved scores", CGRect(x: 65, y: 3139, width: 900, height: 30), 22, ink)
            label("Potential is a local estimate · Artwork belongs to its respective owners", CGRect(x: 65, y: 3174, width: 1550, height: 24), 17, ink.withAlphaComponent(0.75))
            label("ARCPROBE", CGRect(x: 1490, y: 3139, width: 240, height: 36), 27, ink, weight: .light, align: .right)
        }
    }

    static func score(_ value: Int) -> String {
        let padded = String(format: "%08d", value)
        return String(padded.prefix(2)) + "’" + String(padded.dropFirst(2).prefix(3)) + "’" + String(padded.suffix(3))
    }
    static func clearSymbol(_ clear: ClearType?) -> String {
        switch clear {
        case .normal, .easy, .hard: "C"
        case .fullRecall: "F"
        case .pureMemory: "P"
        case .trackLost: "L"
        case nil: "?"
        }
    }
    private static func background(_ cg: CGContext) {
        gradient(CGRect(origin: .zero, size: size), [color(0xfaf9fc), color(0xdedbe7), color(0xf4f1f8)], cg)
        // Pale shards and outlines echo the reference's translucent geometric surround.
        for i in 0..<13 {
            let y = CGFloat(i) * 274 - 140
            let left = polygon([CGPoint(x: 0, y: y), CGPoint(x: 300, y: y + 240), CGPoint(x: 0, y: y + 600)])
            color(i % 2 == 0 ? 0xffffff : 0xd3ccd9, alpha: 0.6).setFill(); left.fill()
            let right = polygon([CGPoint(x: 1800, y: y), CGPoint(x: 1510, y: y + 330), CGPoint(x: 1800, y: y + 590)])
            UIColor.white.withAlphaComponent(0.7).setStroke(); right.lineWidth = 9; right.stroke()
        }
        gradient(CGRect(x: 46, y: 230, width: 1708, height: 2978), [color(0xd9dbe3), color(0xd1cbdc), color(0xb7b0be)], cg)
        cg.setStrokeColor(lavender.withAlphaComponent(0.5).cgColor); cg.setLineWidth(6)
        cg.move(to: CGPoint(x: 0, y: 166)); cg.addLine(to: CGPoint(x: 48, y: 232))
        cg.addLine(to: CGPoint(x: 1753, y: 232)); cg.addLine(to: CGPoint(x: 1800, y: 166)); cg.strokePath()
    }
    private static func header(player: String, potential: String, date: Date, partner: UIImage?, cg: CGContext) {
        label("ARCPROBE", CGRect(x: 119, y: 67, width: 570, height: 96), 76, ink, weight: .ultraLight, family: .exo2)
        rule(CGPoint(x: 118, y: 167), CGPoint(x: 524, y: 167), lavender, cg)
        label("B E S T   5 0   /   S C O R E   A R C H I V E", CGRect(x: 126, y: 178, width: 550, height: 28), 16, ink)
        label("Generated on:", CGRect(x: 1330, y: 142, width: 420, height: 40), 27, .black, weight: .semibold, family: .openSans)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy/MM/dd"
        label(formatter.string(from: date), CGRect(x: 1330, y: 175, width: 420, height: 54), 38, .black, weight: .semibold, family: .openSans)
        let banner = polygon([CGPoint(x: 638, y: 246), CGPoint(x: 690, y: 196), CGPoint(x: 1120, y: 196), CGPoint(x: 1164, y: 270), CGPoint(x: 666, y: 270)])
        cg.saveGState(); banner.addClip()
        gradient(banner.bounds, [color(0xb9ac9d), color(0xfffaf0), color(0xc8b9b3)], cg)
        for i in 0..<10 { rule(CGPoint(x: 630 + i * 16, y: 270), CGPoint(x: 700 + i * 16, y: 196), UIColor.white.withAlphaComponent(0.7), cg) }
        cg.restoreGState()
        label(player, CGRect(x: 752, y: 212, width: 300, height: 47), 33, ink, weight: .regular, align: .center, minimum: 20)
        let center = CGPoint(x: 1125, y: 237)
        diamond(center: center, radius: 68, colors: [color(0x725f86), color(0x302844)], cg: cg)
        let portrait = polygon([CGPoint(x: 1125, y: 173), CGPoint(x: 1189, y: 237), CGPoint(x: 1125, y: 301), CGPoint(x: 1061, y: 237)])
        if let partner {
            cg.saveGState(); portrait.addClip()
            partner.draw(in: CGRect(x: 1061, y: 173, width: 128, height: 128))
            cg.restoreGState()
        } else {
            label("?", CGRect(x: 1095, y: 199, width: 60, height: 77), 58, .white.withAlphaComponent(0.55), weight: .light, align: .center)
        }
        // The badge's transparent PNG includes the appropriate ring and star count.
        let rank = potentialRank(potential).map(String.init) ?? "off"
        UIImage(named: "PotentialRank" + rank)?.draw(in: CGRect(x: 1120, y: 249, width: 90, height: 90))
        let potentialText = PosterTypography.potential(potential)
        let textSize = potentialText.size()
        let origin = CGPoint(x: 1165 - textSize.width / 2, y: 292 - textSize.height / 2)
        let stroke = NSMutableAttributedString(attributedString: potentialText)
        stroke.addAttributes([.strokeColor: ink, .strokeWidth: 7], range: NSRange(location: 0, length: stroke.length))
        stroke.draw(at: origin); potentialText.draw(at: origin)

    }
    /// Matches the official frontend's getRatingDiamondAsset thresholds.
    static func potentialRank(_ potential: String) -> Int? {
        guard let value = Double(potential), value.isFinite, value >= 0 else { return nil }
        switch value {
        case ..<3.5: return 0
        case ..<7: return 1
        case ..<10: return 2
        case ..<11: return 3
        case ..<12: return 4
        case ..<12.5: return 5
        case ..<13: return 6
        default: return 7
        }
    }
    private static func card(_ card: Card?, cg: CGContext) {
        let body = CGRect(x: 0, y: 0, width: 284, height: 226)
        let difficulty = card?.row.best.chartID.difficulty ?? .future
        let accent = difficultyColor(difficulty)
        cg.saveGState(); cg.setShadow(offset: .zero, blur: 20, color: accent.withAlphaComponent(0.3).cgColor)
        lavender.setFill(); cg.fill(body.insetBy(dx: -2, dy: -2)); cg.restoreGState()
        gradient(body, [color(0x314358), color(0x29283e), color(0x70557e)], cg)
        cg.saveGState(); cg.clip(to: body)
        for i in -2..<9 {
            let x = CGFloat(i) * 49
            rule(CGPoint(x: x, y: 0), CGPoint(x: x + 230, y: 226), UIColor.white.withAlphaComponent(0.07), cg)
            rule(CGPoint(x: x, y: 226), CGPoint(x: x + 230, y: 0), lavender.withAlphaComponent(0.1), cg)
        }
        cg.restoreGState()
        gradient(CGRect(x: 0, y: 0, width: 284, height: 6), [accent.withAlphaComponent(0.8), color(0x2c2c43)], cg)
        guard let card else {
            label("—", CGRect(x: 0, y: 70, width: 284, height: 70), 44, .white.withAlphaComponent(0.4), align: .center)
            label("No saved score", CGRect(x: 10, y: 194, width: 264, height: 26), 20, .white.withAlphaComponent(0.6), align: .center)
            return
        }
        let cover = CGRect(x: 98, y: 9, width: 180, height: 180)
        ink.setFill(); cg.fill(cover.insetBy(dx: -3, dy: -3))
        if let image = card.cover {
            cg.saveGState(); cg.clip(to: cover)
            let scale = max(cover.width / image.size.width, cover.height / image.size.height)
            let rect = CGRect(x: cover.midX - image.size.width * scale / 2, y: cover.midY - image.size.height * scale / 2, width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: rect); cg.restoreGState()
        } else {
            gradient(cover, [accent.withAlphaComponent(0.5), color(0x252535)], cg)
            label("♪", CGRect(x: 110, y: 40, width: 156, height: 75), 60, .white.withAlphaComponent(0.5), align: .center)
            label("COVER UNAVAILABLE", CGRect(x: 102, y: 130, width: 172, height: 20), 11, .white.withAlphaComponent(0.8), align: .center)
        }
        UIColor.black.withAlphaComponent(0.66).setFill(); cg.fill(CGRect(x: 98, y: 161, width: 180, height: 29))
        label(score(card.row.best.values.score), CGRect(x: 102, y: 159, width: 151, height: 34), 26, .white, weight: .semibold, align: .center, outline: true, minimum: 20)
        let ribbon = polygon([CGPoint(x: -8, y: 11), CGPoint(x: 53, y: 11), CGPoint(x: 75, y: 32), CGPoint(x: 53, y: 53), CGPoint(x: -8, y: 53)])
        cg.saveGState(); ribbon.addClip(); gradient(ribbon.bounds, [lavender.withAlphaComponent(0.9), color(0x536179)], cg); cg.restoreGState()
        UIColor.white.withAlphaComponent(0.35).setStroke(); ribbon.lineWidth = 1; ribbon.stroke()
        label(card.row.rank.map { "#\($0)" } ?? "—", CGRect(x: 3, y: 15, width: 60, height: 37), 27, .white, weight: .semibold, align: .center, outline: true)
        label("POTENTIAL", CGRect(x: 4, y: 67, width: 84, height: 19), 12, .white, align: .center, family: .titillium)
        let ratingColor = (card.row.rank ?? 51) <= 10 ? color(0xffd548) : .white
        label(card.row.ratingUnits.map { RatingCalculator.display($0) } ?? "—", CGRect(x: 4, y: 85, width: 84, height: 33), 22, ratingColor, weight: .medium, align: .center, minimum: 18)
        rule(CGPoint(x: 20, y: 121), CGPoint(x: 72, y: 121), lavender.withAlphaComponent(0.5), cg)
        diamond(center: CGPoint(x: 46, y: 151), radius: 26, colors: [color(0xf0e2ee), color(0x9ebfdf), color(0xa98ab9)], cg: cg)
        label(DisplayFormat.grade(card.row.best.values.score), CGRect(x: 13, y: 133, width: 66, height: 43), 29, color(0x614870), weight: .light, align: .center, minimum: 24)
        gradient(CGRect(x: 0, y: 194, width: 284, height: 32), [lavender.withAlphaComponent(0.9), color(0x8a779d)], cg)
        label(card.title, CGRect(x: 12, y: 194, width: 260, height: 31), 24, .white, weight: .semibold, outline: true, minimum: 18, family: .titillium)
        diamond(center: CGPoint(x: 276, y: 8), radius: 33, colors: [accent, accent.withAlphaComponent(0.8), ink], cg: cg)
        label(card.metadata?.level ?? "?", CGRect(x: 246, y: -9, width: 60, height: 36), 25, .white, weight: .medium, align: .center, minimum: 20)
        let clear = card.row.best.bestClear
        let clearColor: UIColor = switch clear {
        case .hard: color(0x9a1548)
        case .easy: color(0x407860)
        case .normal: color(0x304c86)
        case .fullRecall: color(0xb356a5)
        case .pureMemory: color(0x80cce0)
        case .trackLost: color(0x626271)
        case nil: color(0x706579)
        }
        diamond(center: CGPoint(x: 274, y: 187), radius: 31, colors: [clearColor, color(0x17182c)], cg: cg)
        label(clearSymbol(clear), CGRect(x: 248, y: 161, width: 52, height: 57), 44, .white, weight: .ultraLight, align: .center, outline: true)
    }
    private static func difficultyColor(_ difficulty: Difficulty) -> UIColor {
        switch difficulty {
        case .past: color(0x328cae)
        case .present: color(0x57955a)
        case .future: color(0x79436f)
        case .beyond: color(0xa6193c)
        case .eternal: color(0x33397d)
        }
    }
    private static func color(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
    private static func polygon(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath(); guard let first = points.first else { return path }
        path.move(to: first); for point in points.dropFirst() { path.addLine(to: point) }; path.close(); return path
    }
    private static func diamond(center: CGPoint, radius: CGFloat, colors: [UIColor], cg: CGContext) {
        let path = polygon([CGPoint(x: center.x, y: center.y - radius), CGPoint(x: center.x + radius, y: center.y), CGPoint(x: center.x, y: center.y + radius), CGPoint(x: center.x - radius, y: center.y)])
        cg.saveGState(); cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: ink.cgColor)
        ink.setFill(); path.fill(); cg.restoreGState()
        cg.saveGState(); path.addClip(); gradient(path.bounds, colors, cg); cg.restoreGState()
        ink.withAlphaComponent(0.8).setStroke(); path.lineWidth = 3; path.stroke()
        cg.saveGState(); cg.translateBy(x: center.x, y: center.y); cg.scaleBy(x: 0.87, y: 0.87); cg.translateBy(x: -center.x, y: -center.y)
        UIColor.white.withAlphaComponent(0.23).setStroke(); path.lineWidth = 1; path.stroke(); cg.restoreGState()
    }
    private static func gradient(_ rect: CGRect, _ colors: [UIColor], _ cg: CGContext) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        cg.saveGState(); cg.clip(to: rect)
        cg.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        cg.restoreGState()
    }
    private static func rule(_ start: CGPoint, _ end: CGPoint, _ color: UIColor, _ cg: CGContext) {
        cg.setStrokeColor(color.cgColor); cg.setLineWidth(1); cg.move(to: start); cg.addLine(to: end); cg.strokePath()
    }
    private static func label(_ text: String, _ rect: CGRect, _ size: CGFloat, _ color: UIColor, weight: UIFont.Weight = .regular, align: NSTextAlignment = .left, outline: Bool = false, minimum: CGFloat? = nil, family: PosterTypography.Family = .exo2) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = align; paragraph.lineBreakMode = .byTruncatingTail
        var font = PosterTypography.font(family, size: size, weight: weight)
        if let minimum {
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            if width > rect.width { font = PosterTypography.font(family, size: max(minimum, size * rect.width / width), weight: weight) }
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        let baseline = rect.midY + font.capHeight / 2
        let drawingRect = CGRect(x: rect.minX, y: baseline - font.ascender, width: rect.width, height: font.lineHeight + 2)
        if outline {
            var stroke = attributes
            stroke[.strokeColor] = ink; stroke[.strokeWidth] = 7
            (text as NSString).draw(in: drawingRect, withAttributes: stroke)
        }
        (text as NSString).draw(in: drawingRect, withAttributes: attributes)
    }
}
