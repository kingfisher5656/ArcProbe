import XCTest
import ArcaeaCore
import UIKit
@testable import ArcaeaOffline

@MainActor final class ExportTests: XCTestCase {
    func testCSVExportsFiftyChartsAndQuotesTitlesWithoutInventingUnknownDates() throws {
        let model = try makeModel(count: 55)
        let file = try ScoreExportService.csv(model: model)
        let csv = try String(contentsOf: file.url, encoding: .utf8)
        XCTAssertEqual(csv.split(separator: "\n").count, 51)
        XCTAssertTrue(csv.contains("\"Title, \"\"quoted\"\"\""))
        XCTAssertTrue(csv.contains("unknown"))
        XCTAssertFalse(csv.contains("1970"))
    }
    func testJPGProducesDecodableFullB50Portrait() async throws {
        let model = try makeModel(count: 55)
        let file = try await ScoreExportService.jpg(model: model)
        let image = try XCTUnwrap(UIImage(data: Data(contentsOf: file.url)))
        XCTAssertEqual(image.size, CGSize(width: 1800, height: 3208))
        XCTAssertGreaterThanOrEqual(image.size.width, 1800)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        XCTAssertGreaterThan(attributes[.size] as? Int ?? 0, 20_000)
    }
    func testExportUsesDifficultySpecificCoverThenOfficialFallback() async throws {
        let model = try makeModel(count: 55)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func save(_ key: String, color: UIColor) throws {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { context in
                color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            }
            try XCTUnwrap(image.jpegData(compressionQuality: 1)).write(to: folder.appendingPathComponent(LibraryResources.coverKey(key) + ".jpg"))
        }
        try save("official-test", color: .blue)
        try save("wiki:chart00:3", color: .red)
        let file = try await ScoreExportService.jpg(model: model, coverLoader: CoverImageLoader(folder: folder))
        let image = try XCTUnwrap(UIImage(data: Data(contentsOf: file.url)))
        func pixel(_ x: Int, _ y: Int) throws -> [UInt8] {
            let crop = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)))
            var bytes = [UInt8](repeating: 0, count: 4)
            bytes.withUnsafeMutableBytes { data in
                let context = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return bytes
        }
        let beyond = try pixel(250, 430), fallback = try pixel(584, 430)
        XCTAssertGreaterThan(beyond[0], 230); XCTAssertLessThan(beyond[2], 20)
        XCTAssertGreaterThan(fallback[2], 230); XCTAssertLessThan(fallback[0], 20)
    }
    func testReferenceScoreFormattingAndUnknownClear() {
        XCTAssertEqual(B50PosterRenderer.score(9_904_038), "09’904’038")
        XCTAssertEqual(B50PosterRenderer.score(10_001_234), "10’001’234")
        XCTAssertEqual(B50PosterRenderer.clearSymbol(nil), "?")
        XCTAssertEqual(B50PosterRenderer.clearSymbol(.fullRecall), "F")
        XCTAssertEqual(B50PosterRenderer.clearSymbol(.pureMemory), "P")
    }
    func testPosterVisualFixtureWithFiftyCards() throws {
        let model = try makeModel(count: 55)
        let rows = try XCTUnwrap(model.ranking?.rows)
        let titles = ["Tempestissimo", "Arcana Eden", "DREAD AREA", "Pentiment", "Cataclysm Cry", "An unusually long song title that must not overflow", "ω4", "#1f1e33", "光と闇の物語", "GLORY：ROAD"]
        let cards = rows.prefix(50).enumerated().map { index, row in
            let cover = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 360)).image { context in
                UIColor(hue: CGFloat(index % 10) / 10, saturation: 0.5, brightness: 0.65, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 360, height: 360))
                for offset in stride(from: 0, to: 360, by: 35) {
                    UIColor.white.withAlphaComponent(0.2).setFill()
                    UIBezierPath(ovalIn: CGRect(x: offset - 100, y: offset - 100, width: 260, height: 260)).fill()
                }
                ("♫" as NSString).draw(at: CGPoint(x: 110, y: 85), withAttributes: [.font: UIFont.systemFont(ofSize: 145), .foregroundColor: UIColor.white])
            }
            return B50PosterRenderer.Card(row: row, title: titles[index % titles.count], metadata: model.catalog[row.best.chartID], cover: cover)
        }
        let partner = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 160)).image { context in
            UIColor(red: 0.9, green: 0.75, blue: 0.65, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 160))
            UIImage(systemName: "person.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: CGRect(x: 35, y: 20, width: 90, height: 120))
        }
        let data = B50PosterRenderer.render(cards: cards, player: "Synthetic player", potential: "12.926", generatedAt: Date(timeIntervalSince1970: 1_791_633_600), partner: partner)
        for potential in ["12.499", "12.500", "13.000"] {
            let badgeData = B50PosterRenderer.render(cards: [], player: "Synthetic player", potential: potential, generatedAt: Date(timeIntervalSince1970: 1_791_633_600), partner: partner)
            let full = try XCTUnwrap(UIImage(data: badgeData)?.cgImage)
            let header = try XCTUnwrap(full.cropping(to: CGRect(x: 630, y: 155, width: 630, height: 195)))
            let sample = XCTAttachment(image: UIImage(cgImage: header)); sample.name = "Partner-header-" + potential; sample.lifetime = .keepAlways; add(sample)
        }
        let image = try XCTUnwrap(UIImage(data: data))
        let attachment = XCTAttachment(image: image); attachment.name = "B50-reference-layout"; attachment.lifetime = .keepAlways; add(attachment)
        let crop = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: 0, y: 0, width: 1800, height: 940)))
        let detail = XCTAttachment(image: UIImage(cgImage: crop)); detail.name = "B50-header-and-cards"; detail.lifetime = .keepAlways; add(detail)
    }
    func testExportLoadsSelectedProfilesPartnerIntoDiamond() async throws {
        let model = try makeModel(count: 1, partnerIcon: "equipped_icon")
        let portrait = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        }.pngData())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let loader = PartnerArtworkLoader(folder: folder) { url in
            XCTAssertEqual(url.lastPathComponent, "equipped_icon.png"); return portrait
        }
        let file = try await ScoreExportService.jpg(model: model, partnerLoader: loader)
        let image = try XCTUnwrap(UIImage(data: Data(contentsOf: file.url))?.cgImage)
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: 1125, y: 225, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { data in
            let ctx = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        XCTAssertGreaterThan(bytes[0], 230); XCTAssertLessThan(bytes[1], 20)
    }
    private func makeModel(count: Int, partnerIcon: String? = nil) throws -> ArchiveModel {
        let profile = AccountProfile(id: AccountID("export-test"), displayName: "Synthetic player", partnerIcon: partnerIcon)
        let charts = (0..<count).map { ChartMetadata(id: ChartID(songID: String(format: "chart%02d", $0), difficulty: Difficulty(rawValue: $0 == 0 ? 3 : $0 % 5)!), constant: ChartConstant(tenths: 100), level: $0 % 3 == 0 ? "11+" : "11", difficultyLabel: $0 % 10 == 3 ? "INS" : nil, title: $0 == 0 ? "Title, \"quoted\"" : "Chart \($0)", artworkIdentifier: "official-test", provenance: "synthetic") }
        let store = try ArchiveStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("archive.sqlite"), catalog: ChartCatalog(charts: charts))
        let scores = charts.enumerated().map { ScoreObservation(id: ObservationID("export:\($0.offset)"), accountID: profile.id, chartID: $0.element.id, source: .manual, values: ScoreValues(score: 9_950_000 - $0.offset * 10_000, bestClear: [ClearType.hard, .normal, .easy, .fullRecall, .pureMemory, .trackLost][$0.offset % 6]), firstSeenAt: Date(), identityConfidence: .manual) }
        _ = try store.apply(batch: ImportBatch(profile: profile, observations: scores, charts: charts))
        return try ArchiveModel(store: store, catalog: ChartCatalog(charts: charts))
    }
}
