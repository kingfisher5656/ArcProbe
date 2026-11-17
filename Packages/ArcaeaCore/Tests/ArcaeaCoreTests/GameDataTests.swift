import XCTest
@testable import ArcaeaCore

final class GameDataTests: XCTestCase {
    private struct Row {
        var song = "synthetic", difficulty = 2, score = 9_900_000
        var shiny = 900, pure = 990, far = 10, lost = 0, modifier = 0, health = 100
        var clear: Int? = 1
    }
    private let catalog = ChartCatalog(charts: [ChartMetadata(id: testChart, constant: ChartConstant(tenths: 100), noteCount: 1000, title: "Synthetic Song", provenance: "test")])
    private let songListJSON: [String: Any] = ["songs": [
        ["id": "synthetic", "title_localized": ["en": "Synthetic Song"], "artist": "Someone",
         "difficulties": [["ratingClass": 2, "rating": 9, "ratingPlus": true]]],
        ["id": "newsong", "title_localized": ["en": "New Song"], "artist": "Other",
         "difficulties": [["ratingClass": 2, "rating": 10], ["ratingClass": 3, "rating": 11, "jacketOverride": true]]]
    ]]

    /// Builds `…/<levels>/<container>` laid out like Arcaea's data folder and returns (top folder, container).
    private func makeFolder(_ rows: [Row], levels: [String] = [], content: Bool = true) throws -> (top: URL, root: URL, database: ArchiveDatabase) {
        let top = temporaryArchiveURL().deletingLastPathComponent()
        let root = (levels + ["F2799B9C-TEST"]).reduce(top) { $0.appendingPathComponent($1, isDirectory: true) }
        let manager = FileManager.default
        try manager.createDirectory(at: root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        let database = try ArchiveDatabase(url: root.appendingPathComponent("Documents/st3"))
        try database.execute("CREATE TABLE scores(id integer primary key autoincrement not null, version int, score int, shinyPerfectCount int, perfectCount int, nearCount int, missCount int, date int, songId text, songDifficulty int, modifier int, health int, ct int default 0)")
        try database.execute("CREATE TABLE cleartypes(id integer primary key autoincrement not null, songId text, songDifficulty int, clearType int, ct int default 0)")
        for row in rows {
            try database.execute("INSERT INTO scores(version,score,shinyPerfectCount,perfectCount,nearCount,missCount,date,songId,songDifficulty,modifier,health) VALUES(1,?,?,?,?,?,1793241,?,?,?,?)",
                [.integer(Int64(row.score)), .integer(Int64(row.shiny)), .integer(Int64(row.pure)), .integer(Int64(row.far)), .integer(Int64(row.lost)),
                 .text(row.song), .integer(Int64(row.difficulty)), .integer(Int64(row.modifier)), .integer(Int64(row.health))])
            if let clear = row.clear {
                try database.execute("INSERT INTO cleartypes(songId,songDifficulty,clearType) VALUES(?,?,?)", [.text(row.song), .integer(Int64(row.difficulty)), .integer(Int64(clear))])
            }
        }
        if content {
            let songs = root.appendingPathComponent("Library/Application Support/cb/active/songs")
            for (folder, file) in [("dl_synthetic", "1080_base.jpg"), ("newsong", "base.jpg"), ("newsong", "3.jpg")] {
                try manager.createDirectory(at: songs.appendingPathComponent(folder), withIntermediateDirectories: true)
                try Data(file.utf8).write(to: songs.appendingPathComponent(folder).appendingPathComponent(file))
            }
            try JSONSerialization.data(withJSONObject: songListJSON).write(to: songs.appendingPathComponent("songlist"))
            try JSONSerialization.data(withJSONObject: ["versionNumber": "7.1.0"]).write(to: root.appendingPathComponent("Library/Application Support/cb/meta.cb"))
            try manager.createDirectory(at: root.appendingPathComponent("Library/Preferences"), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["lastLoggedInUsername": "Player", "a_t": "secret"], format: .binary, options: 0)
                .write(to: root.appendingPathComponent("Library/Preferences/moe.low.arc.plist"))
        }
        return (top, root, database)
    }

    func testFolderIsFoundFromTheContainerItsDocumentsOrFoldersAbove() throws {
        let made = try makeFolder([Row()], levels: ["Data", "Application"])
        for picked in [made.root, made.root.appendingPathComponent("Documents"), made.top.appendingPathComponent("Data/Application"), made.top.appendingPathComponent("Data"), made.top] {
            XCTAssertEqual(try GameDataFolder.locate(in: picked).root.standardizedFileURL.path, made.root.standardizedFileURL.path, picked.path)
        }
        XCTAssertThrowsError(try GameDataFolder.locate(in: made.root.appendingPathComponent("Library"))) { XCTAssertEqual($0 as? GameDataError, .notFound) }
        let folder = try GameDataFolder.locate(in: made.top)
        XCTAssertEqual(folder.playerName(), "Player")
        XCTAssertEqual(folder.gameVersion(), "7.1.0")
        XCTAssertEqual(folder.songJacket(songID: "synthetic")?.lastPathComponent, "1080_base.jpg")
        XCTAssertEqual(folder.songJacket(songID: "newsong")?.lastPathComponent, "base.jpg")
        XCTAssertEqual(folder.chartJacket(for: ChartID(songID: "newsong", difficulty: .beyond))?.lastPathComponent, "3.jpg")
        XCTAssertNil(folder.chartJacket(for: ChartID(songID: "newsong", difficulty: .future)))
        XCTAssertNil(folder.songJacket(songID: "../synthetic"))
        XCTAssertEqual(folder.songList()?.charts.count, 3)
        XCTAssertEqual(folder.songList()?.charts[testChart]?.level, "9+")
    }

    func testScoresAreReadWhileTheGameStillHasItsFileOpenAndBadRowsAreSkipped() throws {
        let made = try makeFolder([
            Row(),
            Row(song: "zero", score: 0),
            Row(song: "odd", difficulty: 7),
            Row(song: "bad id!"),
            Row(song: "lost", score: 1_498_132, shiny: 5, pure: 150, far: 3, lost: 800, modifier: 2, health: -1, clear: 0),
            Row(song: "nolamp", shiny: 2000, pure: 990, clear: nil)
        ])
        // `made.database` is still open here, as the game's would be.
        let scores = try withExtendedLifetime(made.database) { try GameDataFolder.locate(in: made.root).scores() }
        XCTAssertEqual(scores.map(\.chartID.songID), ["lost", "nolamp", "synthetic"])
        let lost = scores[0], noLamp = scores[1], normal = scores[2]
        XCTAssertEqual(normal, GameScore(chartID: testChart, score: 9_900_000, judgments: Judgments(pure: 990, shinyPure: 900, far: 10, lost: 0), bestClear: .normal, modifier: 0, health: 100))
        XCTAssertEqual(lost.bestClear, .trackLost); XCTAssertEqual(lost.modifier, 2); XCTAssertNil(lost.health)
        XCTAssertNil(noLamp.bestClear); XCTAssertNil(noLamp.judgments)
        XCTAssertThrowsError(try GameDataFolder.locate(in: made.root.appendingPathComponent("Library")))
    }

    func testOnlyHigherScoresAreAddedAndTheImportCanBeRepeated() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [
            observation("official", score: 9_850_000, source: .officialImport)
        ], importedAt: testDate))
        let newChart = ChartID(songID: "newsong", difficulty: .beyond)
        let made = try makeFolder([
            Row(score: 9_900_000),
            Row(song: "newsong", difficulty: 3, score: 9_700_000, shiny: 500, pure: 800, far: 20, lost: 10, clear: 5),
            Row(song: "arcpxcustom")
        ])
        let folder = try GameDataFolder.locate(in: made.root)
        let plan = try store.previewGameDataImport(folder.scores(), songList: folder.songList(), accountID: testAccount)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: plan.entries.map { ($0.chartID.songID, $0.disposition) }),
                       ["synthetic": .add, "newsong": .add, "arcpxcustom": .unknownChart])
        XCTAssertEqual(plan.entries.first { $0.chartID == testChart }?.previousScore, 9_850_000)
        XCTAssertEqual(plan.chartChangeCount, 3)
        XCTAssertNil(try store.chartCatalog()[newChart], "A preview changes nothing")

        let receipt = try store.importGameData(plan, importedAt: testDate)
        XCTAssertEqual(receipt.addedCount, 2); XCTAssertEqual(receipt.kind, .gameData)
        XCTAssertEqual(try store.chartCatalog()[newChart]?.level, "11")
        let best = Dictionary(uniqueKeysWithValues: try store.bestScores(accountID: testAccount).map { ($0.chartID, $0) })
        XCTAssertEqual(best[testChart]?.values.score, 9_900_000)
        XCTAssertNil(best[testChart]?.values.playedAt, "The game's dates are not trusted")
        XCTAssertEqual(best[testChart]?.values.judgments?.pure, 990)
        XCTAssertEqual(best[newChart]?.bestClear, .hard)
        XCTAssertEqual(try store.sourceObservations(accountID: testAccount).filter { $0.source == .gameData }.count, 2)

        let again = try store.previewGameDataImport(folder.scores(), songList: folder.songList(), accountID: testAccount)
        XCTAssertEqual(again.addCount, 0); XCTAssertEqual(again.chartChangeCount, 0)
        XCTAssertEqual(try store.importGameData(again, importedAt: testDate).addedCount, 0)
        XCTAssertThrowsError(try store.importGameData(plan, importedAt: testDate)) { XCTAssertEqual($0 as? GameDataError, .stalePreview) }

        // Scores survive a backup and restore with their source.
        let restored = try ArchiveStore(url: temporaryArchiveURL())
        _ = try ArchiveBackup(store: restored).validateAndRestore(data: ArchiveBackup(store: store).export())
        XCTAssertEqual(try restored.gameDataScoreCount(accountID: testAccount), 2)
    }

    func testEqualOrLowerScoresAndCountsThatDoNotFitTheChartAreHandled() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [
            observation("official", score: 9_900_000, source: .officialImport)
        ], importedAt: testDate))
        let equal = try store.previewGameDataImport([GameScore(chartID: testChart, score: 9_900_000)], accountID: testAccount)
        XCTAssertEqual(equal.entries.map(\.disposition), [.keepExisting])
        // 900 + 10 + 0 notes do not total the chart's 1000: the score is kept, the counts are not.
        let mismatch = GameScore(chartID: testChart, score: 9_950_000, judgments: Judgments(pure: 900, shinyPure: 800, far: 10, lost: 0))
        let plan = try store.previewGameDataImport([mismatch, GameScore(chartID: testChart, score: 9_940_000)], accountID: testAccount)
        XCTAssertEqual(plan.entries.map(\.score), [9_950_000], "One entry per chart, the highest")
        XCTAssertEqual(try store.importGameData(plan, importedAt: testDate).addedCount, 1)
        let added = try XCTUnwrap(store.sourceObservations(accountID: testAccount).first { $0.source == .gameData })
        XCTAssertNil(added.values.judgments)
        let tooHigh = try store.previewGameDataImport([GameScore(chartID: testChart, score: 10_050_000)], accountID: testAccount)
        XCTAssertEqual(tooHigh.entries.map(\.disposition), [.invalid])
    }

    func testGameScoresOutliveAnOfficialImportAndCanBeTakenBack() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL(), catalog: catalog)
        let plan = try store.previewGameDataImport([GameScore(chartID: testChart, score: 9_950_000, bestClear: .fullRecall)], accountID: testAccount)
        XCTAssertEqual(try store.importGameData(plan, importedAt: testDate).addedCount, 1)
        // The play was never uploaded, so the official list still shows the older, lower score.
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [
            observation("official", score: 9_800_000, source: .officialImport)
        ], importedAt: testDate.addingTimeInterval(60)))
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_950_000)
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.bestClear, .fullRecall)

        // Deleting the play in ArcProbe is respected by the next folder import.
        let play = try XCTUnwrap(store.observations(accountID: testAccount).first { $0.original.source == .gameData })
        let undo = try store.applyManual(change: .suppress(accountID: testAccount, observationID: play.original.id))
        let after = try store.previewGameDataImport(plan.scores, accountID: testAccount)
        XCTAssertEqual(after.entries.map(\.disposition), [.removedEarlier])
        XCTAssertEqual(try store.importGameData(after, importedAt: testDate).addedCount, 0)

        XCTAssertEqual(try store.removeGameDataScores(accountID: testAccount), 1)
        XCTAssertEqual(try store.gameDataScoreCount(accountID: testAccount), 0)
        XCTAssertEqual(try store.bestScores(accountID: testAccount).first?.values.score, 9_800_000)
        XCTAssertThrowsError(try store.undo(undo), "Undo of an edit to a removed score is gone")
        XCTAssertNil(try store.latestUndoToken())
    }
}
