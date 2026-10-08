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
    func testJPGProducesDecodableFullB50Portrait() throws {
        let model = try makeModel(count: 55)
        let file = try ScoreExportService.jpg(model: model)
        let image = try XCTUnwrap(UIImage(data: Data(contentsOf: file.url)))
        XCTAssertGreaterThan(image.size.height, image.size.width)
        XCTAssertGreaterThanOrEqual(image.size.width, 1800)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        XCTAssertGreaterThan(attributes[.size] as? Int ?? 0, 20_000)
    }
    private func makeModel(count: Int) throws -> ArchiveModel {
        let profile = AccountProfile(id: AccountID("export-test"), displayName: "Synthetic player")
        let charts = (0..<count).map { ChartMetadata(id: ChartID(songID: String(format: "chart%02d", $0), difficulty: .future), constant: ChartConstant(tenths: 100), title: $0 == 0 ? "Title, \"quoted\"" : "Chart \($0)", provenance: "synthetic") }
        let store = try ArchiveStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("archive.sqlite"), catalog: ChartCatalog(charts: charts))
        let scores = charts.enumerated().map { ScoreObservation(id: ObservationID("export:\($0.offset)"), accountID: profile.id, chartID: $0.element.id, source: .manual, values: ScoreValues(score: 9_900_000 - $0.offset), firstSeenAt: Date(), identityConfidence: .manual) }
        _ = try store.apply(batch: ImportBatch(profile: profile, observations: scores, charts: charts))
        return try ArchiveModel(store: store, catalog: ChartCatalog(charts: charts))
    }
}
