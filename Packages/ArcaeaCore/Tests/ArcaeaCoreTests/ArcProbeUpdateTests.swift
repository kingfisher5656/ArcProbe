import XCTest
@testable import ArcaeaCore

final class ArcProbeUpdateTests: XCTestCase {
    func testConstantsRefreshReplacesRemovedEntriesAndSurvivesReopen() throws {
        let url = temporaryArchiveURL()
        let id = ChartID(songID: "example", difficulty: .future)
        let removed = ChartID(songID: "removed", difficulty: .future)
        let bundled = ChartCatalog(charts: [ChartMetadata(id: id, constant: .init(tenths: 100), title: "Kept title", provenance: "bundled"), ChartMetadata(id: removed, constant: .init(tenths: 90), provenance: "bundled")])
        let store = try ArchiveStore(url: url, catalog: bundled)
        let data = Data(#"{"example":[null,null,{"constant":10.7,"old":false}]}"#.utf8)
        let snapshot = try ConstantSnapshot.parse(data)
        try store.replaceConstants(snapshot)
        let reopened = try ArchiveStore(url: url, catalog: bundled).chartCatalog()
        XCTAssertEqual(reopened[id]?.constant?.tenths, 107)
        XCTAssertEqual(reopened[id]?.title, "Kept title")
        XCTAssertNil(reopened[removed]?.usableConstant)
        XCTAssertThrowsError(try ConstantSnapshot.parse(Data(#"{"bad":[{"constant":10.75,"old":false}]}"#.utf8)))
        XCTAssertThrowsError(try ConstantSnapshot.parse(Data("{}".utf8)))
    }

    func testSongListSetsLevelsAddsNewChartsAndKeepsOfficialNames() throws {
        let url = temporaryArchiveURL()
        let known = ChartID(songID: "testsong", difficulty: .future)
        let renamed = ChartID(songID: "testsong", difficulty: .beyond)
        let bundled = ChartCatalog(charts: [
            ChartMetadata(id: known, constant: .init(tenths: 90), level: "8", title: "Official title", artist: "Official artist", artworkIdentifier: "cover", provenance: "bundled"),
            ChartMetadata(id: renamed, constant: .init(tenths: 96), provenance: "bundled")])
        let store = try ArchiveStore(url: url, catalog: bundled)
        let data = Data(#"""
        {"songs":[
          {"id":"testsong","title_localized":{"en":"Last"},"artist":"onoken","difficulties":[
            {"ratingClass":2,"rating":9},
            {"ratingClass":3,"rating":9,"title_localized":{"en":"Last | Moment"}}]},
          {"id":"lasteternity","title_localized":{"en":"Last | Eternity"},"artist":"onoken","difficulties":[
            {"ratingClass":0,"rating":0},
            {"ratingClass":3,"rating":9,"ratingPlus":true}]},
          {"id":"dreadarea","title_localized":{"en":"DREAD AREA"},"artist":"x","difficulties":[
            {"ratingClass":3,"ratingClassAlias":1,"rating":11},
            {"ratingClass":9,"rating":5},
            {"ratingClass":1,"rating":"odd"}]},
          {"id":"particlearts","deleted":true},
          {"unexpected":true}
        ]}
        """#.utf8)
        let snapshot = try SongListSnapshot.parse(data)
        XCTAssertEqual(snapshot.charts.count, 4)
        XCTAssertEqual(try store.applySongList(snapshot), 4)
        let catalog = try ArchiveStore(url: url, catalog: bundled).chartCatalog()
        XCTAssertEqual(catalog[known]?.level, "9")
        XCTAssertEqual(catalog[known]?.title, "Official title")
        XCTAssertEqual(catalog[known]?.artist, "Official artist")
        XCTAssertEqual(catalog[known]?.constant?.tenths, 90)
        XCTAssertEqual(catalog[known]?.artworkIdentifier, "cover")
        XCTAssertEqual(catalog[renamed]?.title, "Last | Moment")
        let added = ChartID(songID: "lasteternity", difficulty: .beyond)
        XCTAssertEqual(catalog[added]?.level, "9+")
        XCTAssertEqual(catalog[added]?.title, "Last | Eternity")
        XCTAssertNil(catalog[added]?.constant)
        XCTAssertNil(catalog[ChartID(songID: "lasteternity", difficulty: .past)])
        XCTAssertEqual(catalog[ChartID(songID: "dreadarea", difficulty: .beyond)]?.displayDifficulty, "INS")
        XCTAssertNil(catalog[ChartID(songID: "dreadarea", difficulty: .present)])
        // A second pass with the same list changes nothing, also after a constants refresh.
        XCTAssertEqual(try store.applySongList(snapshot), 0)
        try store.replaceConstants(ConstantSnapshot.parse(Data(#"{"testsong":[null,null,{"constant":9.1,"old":false}]}"#.utf8)))
        XCTAssertEqual(try store.chartCatalog()[known]?.level, "9")
        XCTAssertEqual(try store.applySongList(snapshot), 0)
        XCTAssertThrowsError(try SongListSnapshot.parse(Data(#"{"songs":[]}"#.utf8)))
        XCTAssertThrowsError(try SongListSnapshot.parse(Data(#"{"other":1}"#.utf8)))
    }
}
