import XCTest
@testable import ArcaeaCore

final class PackCatalogTests: XCTestCase {
    private func packList(_ packs: [Any]) throws -> [Pack] {
        try PackCatalog.parsePackList(JSONSerialization.data(withJSONObject: ["packs": packs]))
    }
    func testPackListKeepsGameOrderAndSkipsEntriesItCannotRead() throws {
        let packs = try packList([
            ["id": "collabpack", "section": "collab", "name_localized": ["en": "Collab Pack"], "description_localized": ["en": "…"]],
            ["id": "collabpack_append_1", "section": "collab", "pack_parent": "collabpack", "name_localized": ["en": "Collaboration Chapter 2"]],
            ["id": "story", "section": "mainstory", "name_localized": ["en": " Story Pack "]],
            ["id": "noname", "section": "collab", "name_localized": ["ja": "名前"]],
            ["id": "bad id", "name_localized": ["en": "Bad"]],
            ["id": "story", "name_localized": ["en": "Duplicate"]],
            ["name_localized": ["en": "No ID"]], "not a pack"
        ] as [Any])
        XCTAssertEqual(packs, [Pack(id: "collabpack", name: "Collab Pack", section: "collab"),
                               Pack(id: "collabpack_append_1", name: "Collaboration Chapter 2", section: "collab", parentID: "collabpack"),
                               Pack(id: "story", name: "Story Pack", section: "mainstory")])
        XCTAssertThrowsError(try packList([["id": "bad id", "name_localized": ["en": "Bad"]]]))
        XCTAssertThrowsError(try PackCatalog.parsePackList(Data("[]".utf8)))
    }
    func testSongsFromAnAppendCountAsTheParentPackAndGroupsFollowTheGame() throws {
        let packs = try packList([
            ["id": "collabpack", "section": "collab", "name_localized": ["en": "Collab Pack"]],
            ["id": "collabpack_append_1", "section": "collab", "pack_parent": "collabpack", "name_localized": ["en": "Collaboration Chapter 2"]],
            ["id": "story", "section": "mainstory", "name_localized": ["en": "Story Pack"]],
            ["id": "base", "section": "arcaea", "name_localized": ["en": "Arcaea"]],
            ["id": "unused", "section": "sidestory", "name_localized": ["en": "Unused"]]
        ])
        let catalog = PackCatalog(packs: packs, songPacks: ["a": "collabpack", "b": "collabpack_append_1", "c": "story", "d": "base", "e": "single", "f": "brandnew"])
        XCTAssertEqual(catalog.pack(forSong: "b")?.id, "collabpack")
        XCTAssertEqual(catalog.pack(forSong: "e")?.name, "Memory Archive")
        XCTAssertEqual(catalog.pack(forSong: "f"), Pack(id: "brandnew", name: "brandnew"), "A pack newer than the pack list still filters by its ID")
        XCTAssertNil(catalog.pack(forSong: "unknown"))
        let groups = catalog.groups(forSongs: ["a", "b", "c", "d", "e", "f", "unknown"])
        XCTAssertEqual(groups.map(\.title), ["Arcaea", "Main Story", "Collaboration", "Other"])
        XCTAssertEqual(groups.map { $0.packs.map(\.id) }, [["base", "single"], ["story"], ["collabpack"], ["brandnew"]])
        XCTAssertEqual(catalog.groups(forSongs: ["c"]).map(\.title), ["Main Story"])

        let merged = catalog.merging(packs: nil, songPacks: ["f": "story", "g": "base"])
        XCTAssertEqual(merged.pack(forSong: "f")?.id, "story"); XCTAssertEqual(merged.pack(forSong: "a")?.id, "collabpack")
        XCTAssertEqual(try JSONDecoder().decode(PackCatalog.self, from: JSONEncoder().encode(merged)), merged)
    }
    func testBundledCatalogAndSongListAgree() throws {
        let bundled = PackCatalog.bundled()
        XCTAssertGreaterThan(bundled.packs.count, 50)
        XCTAssertEqual(bundled.pack(forSong: "tempestissimo")?.name, "Black Fate")
        XCTAssertEqual(bundled.pack(forSong: "last")?.name, "Final Verdict", "Silent Answer is an append of Final Verdict")
        XCTAssertEqual(bundled.groups(forSongs: bundled.songPacks.keys).first?.title, "Arcaea")
        let list = try SongListSnapshot.parse(JSONSerialization.data(withJSONObject: ["songs": [
            ["id": "one", "set": "story", "difficulties": [["ratingClass": 2, "rating": 9]]],
            ["id": "gone", "set": "story", "deleted": true, "difficulties": [["ratingClass": 2, "rating": 9]]],
            ["id": "odd", "set": "bad set!", "difficulties": [["ratingClass": 2, "rating": 9]]],
            ["id": "noset", "difficulties": [["ratingClass": 2, "rating": 9]]]
        ]]))
        XCTAssertEqual(list.songPacks, ["one": "story"])
    }
}
