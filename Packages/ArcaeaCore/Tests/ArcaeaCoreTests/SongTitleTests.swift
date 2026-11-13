import XCTest
@testable import ArcaeaCore

final class SongTitleTests: XCTestCase {
    private let mask = ChartID(songID: "mask", difficulty: .future)
    func testBundledAndIDOnlyChartsUseCanonicalSongTitle() throws {
        XCTAssertEqual(try ChartCatalog.bundled()[mask]?.title, "~_+")
        for title in [nil, "", "mask"] as [String?] {
            let catalog = ChartCatalog(charts: [ChartMetadata(id: mask, title: title, provenance: "test")])
            XCTAssertEqual(catalog[mask]?.title, "~_+")
            XCTAssertEqual(catalog.charts[mask]?.title, "~_+")
        }
        let genesis = ChartID(songID: "genesis", difficulty: .future)
        XCTAssertEqual(ChartCatalog(charts: [ChartMetadata(id: genesis, provenance: "test")])[genesis]?.title, "Genesis")
    }
    func testExistingArchivesAndRestoresGainNamesWithoutChangingScoresOrMetadata() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let metadata = ChartMetadata(id: mask, constant: ChartConstant(tenths: 97), isOutdated: true,
            level: "9+", noteCount: 1000, artist: "Known artist", artworkIdentifier: "known-cover", provenance: "test")
        let score = observation("existing-sheet", chart: mask, source: .consultantSheet)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [score], charts: [metadata], kind: .consultantSheet))
        let catalog = try store.chartCatalog()
        XCTAssertEqual(catalog[mask]?.title, "~_+")
        XCTAssertEqual(catalog[mask]?.constant, metadata.constant)
        XCTAssertEqual(catalog[mask]?.isOutdated, true)
        XCTAssertEqual(catalog[mask]?.noteCount, 1000)
        XCTAssertEqual(catalog[mask]?.artist, "Known artist")
        XCTAssertEqual(catalog[mask]?.artworkIdentifier, "known-cover")
        XCTAssertEqual(try store.sourceObservations(accountID: testAccount), [score])
        let restored = try ArchiveStore(url: temporaryArchiveURL())
        _ = try ArchiveBackup(store: restored).validateAndRestore(data: ArchiveBackup(store: store).export())
        XCTAssertEqual(try restored.chartCatalog()[mask]?.title, "~_+")
        XCTAssertEqual(try restored.sourceObservations(accountID: testAccount), [score])
    }
    func testExplicitOfficialTitleAndUnknownChartArePreserved() {
        let custom = ChartMetadata(id: mask, title: "Official localized title", provenance: "official")
        XCTAssertEqual(ChartCatalog(charts: [custom])[mask], custom)
        let unknown = ChartMetadata(id: testChart, provenance: "test")
        XCTAssertEqual(ChartCatalog(charts: [unknown])[testChart], unknown)
    }
}
