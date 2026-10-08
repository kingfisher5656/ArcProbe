import XCTest
import ArcaeaCore
@testable import ArcaeaOffline

@MainActor final class BackupReviewTests: XCTestCase {
    func testReviewValidatesBackupWithoutReplacingLiveArchiveUntilConfirmed() throws {
        let live = try makeModel()
        try live.save(ScoreDraft(chartID: ChartID(songID: "live", difficulty: .future), score: 9_900_000))
        let backup = try makeModel()
        try backup.save(ScoreDraft(chartID: ChartID(songID: "backup", difficulty: .past), score: 9_500_000))
        let data = try ArchiveBackup(store: backup.store).export()
        let preview = try BackupRestorePreview.validate(data)
        XCTAssertEqual(preview.accountCount, 1)
        XCTAssertEqual(preview.playCount, 1)
        XCTAssertEqual(live.observations.first?.original.chartID.songID, "live")
        try live.restoreBackup(preview.data)
        XCTAssertEqual(live.observations.count, 1)
        XCTAssertEqual(live.observations.first?.original.chartID.songID, "backup")
    }
    func testCorruptBackupReviewLeavesLiveScoresUnchanged() throws {
        let live = try makeModel()
        try live.save(ScoreDraft(chartID: ChartID(songID: "live", difficulty: .future), score: 9_900_000))
        XCTAssertThrowsError(try BackupRestorePreview.validate(Data("invalid".utf8)))
        XCTAssertEqual(live.observations.first?.values.score, 9_900_000)
    }
    private func makeModel() throws -> ArchiveModel {
        let store = try ArchiveStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("archive.sqlite"))
        return try ArchiveModel(store: store, catalog: ChartCatalog(charts: []))
    }
}
