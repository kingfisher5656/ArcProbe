import Foundation

internal enum ArchiveValidation {
    static func identifier(_ text: String, label: String, limit: Int = 512) throws {
        guard !text.isEmpty, text.utf8.count <= limit, !text.contains("\0"), text == text.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ArchiveError.invalidRecord("Invalid \(label)")
        }
    }
    static func account(_ id: AccountID) throws { try identifier(id.rawValue, label: "account ID", limit: 200) }
    static func chartID(_ id: ChartID) throws {
        guard id.songID.range(of: "^[A-Za-z0-9_-]{1,160}$", options: .regularExpression) != nil else {
            throw ArchiveError.invalidRecord("Invalid song ID")
        }
    }
    static func timestamp(_ timestamp: SourceTimestamp) throws {
        guard let millis = timestamp.milliseconds, millis <= 253_402_300_799_999 else {
            throw ArchiveError.invalidRecord("Timestamp is outside the supported range")
        }
    }
    static func date(_ date: Date) throws {
        guard date.timeIntervalSince1970.isFinite, (0...253_402_300_799).contains(date.timeIntervalSince1970) else {
            throw ArchiveError.invalidRecord("Invalid archive timestamp")
        }
    }
    static func profile(_ profile: AccountProfile) throws {
        try account(profile.id)
        if let name = profile.displayName, name.utf8.count > 1_000 || name.contains("\0") {
            throw ArchiveError.invalidRecord("Invalid display name")
        }
    }
    static func metadata(_ metadata: ChartMetadata) throws {
        try chartID(metadata.id)
        if let c = metadata.constant, !(1...200).contains(c.tenths) { throw ArchiveError.invalidRecord("Invalid chart constant") }
        if let n = metadata.noteCount, !(1...100_000).contains(n) { throw ArchiveError.invalidRecord("Invalid chart note count") }
        for text in [metadata.level, metadata.difficultyLabel, metadata.title, metadata.artist, metadata.artworkIdentifier, metadata.provenance] {
            if let text, text.utf8.count > 4_000 || text.contains("\0") { throw ArchiveError.invalidRecord("Invalid chart metadata") }
        }
    }
    static func values(_ values: ScoreValues, metadata: ChartMetadata? = nil) throws {
        let upper = metadata?.noteCount.map { 10_000_000 + $0 } ?? 10_100_000
        guard (0...upper).contains(values.score) else { throw ArchiveError.invalidRecord("Score is outside the chart bounds") }
        if let time = values.playedAt { try timestamp(time) }
        if let health = values.health, !(0...100).contains(health) { throw ArchiveError.invalidRecord("Invalid health") }
        if let modifier = values.modifier, !(0...65_535).contains(modifier) { throw ArchiveError.invalidRecord("Invalid modifier") }
        guard let j = values.judgments else { return }
        let counts = [j.pure, j.shinyPure, j.far, j.lost, j.early, j.late].compactMap { $0 }
        guard counts.allSatisfy({ (0...100_000).contains($0) }) else { throw ArchiveError.invalidRecord("Invalid judgment counts") }
        if let shiny = j.shinyPure, let pure = j.pure, shiny > pure { throw ArchiveError.invalidRecord("Shiny pure exceeds pure") }
        if let notes = metadata?.noteCount {
            guard counts.allSatisfy({ $0 <= notes }) else { throw ArchiveError.invalidRecord("Judgments exceed chart notes") }
            let total = [j.pure, j.far, j.lost].compactMap { $0 }.reduce(0, +)
            guard total <= notes else { throw ArchiveError.invalidRecord("Judgments exceed chart notes") }
            if j.pure != nil, j.far != nil, j.lost != nil, total != notes {
                throw ArchiveError.invalidRecord("Judgments do not total chart notes")
            }
        }
    }
    static func observation(_ observation: ScoreObservation, metadata: ChartMetadata? = nil) throws {
        try identifier(observation.id.rawValue, label: "observation ID", limit: 4_000)
        try account(observation.accountID); try chartID(observation.chartID)
        try date(observation.firstSeenAt); try values(observation.values, metadata: metadata)
        if observation.source == .manual, observation.identityConfidence != .manual {
            throw ArchiveError.invalidRecord("Manual observations require manual identity")
        }
    }
    static func potential(_ point: PotentialPoint) throws {
        try account(point.accountID); try identifier(point.sourceID, label: "potential source ID")
        try timestamp(point.timestamp); try date(point.firstSeenAt)
        guard (0...9).contains(point.value.decimalPlaces), point.value.rawValue >= 0,
              point.value.doubleValue <= 30 else { throw ArchiveError.invalidRecord("Invalid potential value") }
    }
}
