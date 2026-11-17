import Foundation

public struct Pack: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// The game's own grouping of packs ("mainstory", "collab", …).
    public let section: String?
    /// Set on an append pack ("Collaboration Chapter 2"): the pack it is listed inside.
    public let parentID: String?
    public init(id: String, name: String, section: String? = nil, parentID: String? = nil) {
        self.id = id; self.name = name; self.section = section; self.parentID = parentID
    }
}

/// Which pack each song belongs to. A copy ships with the app; the wiki or a game folder can replace it.
public struct PackCatalog: Codable, Sendable, Equatable {
    public struct Group: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let packs: [Pack]
    }
    public let packs: [Pack]
    /// Song ID to the ID of the pack (or append pack) the song is sold in.
    public let songPacks: [String: String]
    /// Worked out once: the top-level pack of every song.
    private let resolved: [String: Pack]
    private enum CodingKeys: String, CodingKey { case packs, songPacks }

    public init(packs: [Pack] = [], songPacks: [String: String] = [:]) {
        self.packs = packs; self.songPacks = songPacks
        let known = Dictionary(packs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        resolved = songPacks.mapValues { set in
            var id = set
            for _ in 0..<4 { guard let parent = known[id]?.parentID, known[parent] != nil else { break }; id = parent }
            return known[id] ?? Self.unlisted(id)
        }
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(packs: try values.decode([Pack].self, forKey: .packs), songPacks: try values.decode([String: String].self, forKey: .songPacks))
    }
    public static func bundled() -> PackCatalog {
        guard let url = Bundle.module.url(forResource: "pack-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(PackCatalog.self, from: data) else { return PackCatalog() }
        return catalog
    }
    /// Reads the game's pack list (the wiki's `Data:Packlist.json` has the same format). Unreadable entries are skipped.
    public static func parsePackList(_ data: Data) throws -> [Pack] {
        struct Lossy<T: Decodable>: Decodable {
            let value: T?
            init(from decoder: Decoder) throws { value = try? T(from: decoder) }
        }
        struct Entry: Decodable { let id: String; let name_localized: [String: String]; let section: String?; let pack_parent: String? }
        struct Root: Decodable { let packs: [Lossy<Entry>] }
        guard data.count <= 2 * 1_024 * 1_024 else { throw ArchiveError.invalidRecord("Pack list is too large") }
        var seen = Set<String>()
        let packs = try JSONDecoder().decode(Root.self, from: data).packs.prefix(2_000).compactMap(\.value).compactMap { entry -> Pack? in
            guard validID(entry.id), let name = entry.name_localized["en"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, name.utf8.count <= 200, seen.insert(entry.id).inserted else { return nil }
            return Pack(id: entry.id, name: name, section: entry.section.flatMap { validID($0) ? $0 : nil },
                        parentID: entry.pack_parent.flatMap { validID($0) && $0 != entry.id ? $0 : nil })
        }
        guard !packs.isEmpty else { throw ArchiveError.invalidRecord("No packs returned") }
        return packs
    }
    public static func validID(_ id: String) -> Bool { id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil }

    /// A new pack list replaces the old one; song assignments are added to the ones already known.
    public func merging(packs newPacks: [Pack]?, songPacks newSongs: [String: String]) -> PackCatalog {
        PackCatalog(packs: newPacks ?? packs, songPacks: songPacks.merging(newSongs) { _, new in new })
    }

    /// The pack a song is filed under in the game's pack list: a song from an append pack counts as its parent pack.
    public func pack(forSong songID: String) -> Pack? { resolved[songID] }
    /// Top-level packs that hold at least one of `songIDs`, in the game's order and grouped the way the game groups them.
    public func groups(forSongs songIDs: some Sequence<String>) -> [Group] {
        let used = Set(songIDs.compactMap { pack(forSong: $0) })
        let listed = packs.filter { used.contains($0) }
        let ordered = listed + used.subtracting(listed).sorted { $0.name < $1.name }
        var groups: [Group] = []
        for section in Self.sections.map(\.id) + Set(ordered.map { $0.section ?? "" }).subtracting(Self.sections.map(\.id)).sorted() {
            let members = ordered.filter { ($0.section ?? "") == section }
            if !members.isEmpty { groups.append(Group(id: section, title: Self.sections.first { $0.id == section }?.title ?? "Other", packs: members)) }
        }
        return groups
    }

    private static let sections: [(id: String, title: String)] = [
        ("arcaea", "Arcaea"), ("mainstory", "Main Story"), ("mainstory2", "Main Story Act II"),
        ("sidestory", "Side Story"), ("collab", "Collaboration"), ("variety", "Variety")
    ]
    /// Songs sold one by one have the set "single", which the pack list does not describe.
    private static func unlisted(_ id: String) -> Pack {
        id == "single" ? Pack(id: id, name: "Memory Archive", section: "arcaea") : Pack(id: id, name: id)
    }
}
