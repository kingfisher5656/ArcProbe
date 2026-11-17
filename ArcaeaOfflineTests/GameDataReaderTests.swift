import ArcaeaCore
import SQLite3
import UIKit
import XCTest
@testable import ArcaeaOffline

final class GameDataReaderTests: XCTestCase {
    private let chart = ChartID(songID: "gamefolder", difficulty: .future)
    private let beyond = ChartID(songID: "gamefolder", difficulty: .beyond)

    func testReadingFindsScoresSongDataAndOnlyTheCoversThatAreMissing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gamedata-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appendingPathComponent("Data/Application/CONTAINER", isDirectory: true)
        let songs = container.appendingPathComponent("Library/Application Support/cb/active/songs/dl_gamefolder", isDirectory: true)
        try FileManager.default.createDirectory(at: container.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: songs, withIntermediateDirectories: true)
        try writeScores(container.appendingPathComponent("Documents/st3"), rows: [("gamefolder", 2, 9_912_345, 3), ("gamefolder", 3, 9_700_000, 1)])
        let base = try image(128), special = try image(192)
        try base.write(to: songs.appendingPathComponent("1080_base.jpg"))
        try special.write(to: songs.appendingPathComponent("1080_3.jpg"))
        try Data("not an image".utf8).write(to: songs.appendingPathComponent("1080_0.jpg"))
        try JSONSerialization.data(withJSONObject: ["songs": [["id": "gamefolder", "title_localized": ["en": "Game Folder Song"], "artist": "Tester",
            "difficulties": [["ratingClass": 0, "rating": 3], ["ratingClass": 2, "rating": 9, "ratingPlus": true], ["ratingClass": 3, "rating": 10]]]]])
            .write(to: songs.deletingLastPathComponent().appendingPathComponent("songlist"))

        let store = try ArchiveStore(url: root.appendingPathComponent("archive.sqlite"))
        let covers = root.appendingPathComponent("covers", isDirectory: true)
        let account = AccountID("local")
        let reading = try GameDataReader.read(picked: root, store: store, accountID: account, coverFolder: covers)
        XCTAssertEqual(reading.scoreCount, 2); XCTAssertEqual(reading.plan.addCount, 2)
        XCTAssertEqual(reading.plan.chartChangeCount, 3); XCTAssertTrue(reading.hasSongList)
        XCTAssertEqual(reading.titles[chart], "Game Folder Song")
        XCTAssertEqual(reading.coverTotal, 3)
        XCTAssertEqual(Set(reading.covers.map(\.key)), ["game:gamefolder", "game:gamefolder:3", "game:gamefolder:0"])

        // The unreadable file is left out; the others keep the game's exact bytes.
        XCTAssertEqual(try GameDataReader.copy(reading.covers, into: covers), 2)
        XCTAssertEqual(try Data(contentsOf: covers.appendingPathComponent(LibraryResources.coverKey("game:gamefolder") + ".jpg")), base)
        XCTAssertEqual(try Data(contentsOf: covers.appendingPathComponent(LibraryResources.coverKey("game:gamefolder:3") + ".jpg")), special)
        XCTAssertEqual(try store.importGameData(reading.plan).addedCount, 2)

        let again = try GameDataReader.read(picked: root, store: store, accountID: account, coverFolder: covers)
        XCTAssertEqual(again.plan.addCount, 0); XCTAssertEqual(again.plan.chartChangeCount, 0)
        XCTAssertEqual(again.covers.map(\.key), ["game:gamefolder:0"])
        XCTAssertEqual(try store.bestScores(accountID: account).first { $0.chartID == chart }?.bestClear, .pureMemory)
    }

    func testCoverLookupPrefersTheGameJacketForTheChartThenTheSongThenWiki() {
        XCTAssertEqual(LibraryResources.coverIdentifiers(chart: beyond, official: "official-art"),
                       ["game:gamefolder:3", "game:gamefolder", "wiki:gamefolder:3", "official-art"])
        XCTAssertEqual(LibraryResources.coverIdentifiers(chart: chart, official: nil), ["game:gamefolder:2", "game:gamefolder", "wiki:gamefolder:2"])
    }

    private func image(_ size: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
    }
    /// A score file with the columns Arcaea uses.
    private func writeScores(_ url: URL, rows: [(song: String, difficulty: Int, score: Int, clear: Int)]) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        var sql = """
        CREATE TABLE scores(id integer primary key autoincrement not null, version int, score int, shinyPerfectCount int, perfectCount int, nearCount int, missCount int, date int, songId text, songDifficulty int, modifier int, health int, ct int default 0);
        CREATE TABLE cleartypes(id integer primary key autoincrement not null, songId text, songDifficulty int, clearType int, ct int default 0);
        """
        for row in rows {
            sql += "INSERT INTO scores(version,score,shinyPerfectCount,perfectCount,nearCount,missCount,date,songId,songDifficulty,modifier,health) VALUES(1,\(row.score),900,990,10,0,0,'\(row.song)',\(row.difficulty),0,100);"
            sql += "INSERT INTO cleartypes(songId,songDifficulty,clearType) VALUES('\(row.song)',\(row.difficulty),\(row.clear));"
        }
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
    }
}

@MainActor final class PackResourceTests: XCTestCase {
    func testBundledPacksAreAvailableAndUpdatesAreKept() {
        let resources = LibraryResources.shared
        XCTAssertEqual(resources.packs.pack(forSong: "tempestissimo")?.name, "Black Fate")
        let song = "pack-test-" + UUID().uuidString
        resources.updatePacks(packs: nil, songPacks: [song: "vs"])
        XCTAssertEqual(resources.packs.pack(forSong: song)?.name, "Black Fate")
        XCTAssertGreaterThan(resources.packs.packs.count, 50, "Song updates keep the pack names")
    }
}
