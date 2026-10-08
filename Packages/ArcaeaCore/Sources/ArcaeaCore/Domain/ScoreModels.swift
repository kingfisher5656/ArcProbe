import Foundation

public struct AccountID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public struct ObservationID: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public enum Difficulty: Int, CaseIterable, Codable, Sendable {
    case past = 0, present = 1, future = 2, beyond = 3, eternal = 4
    public var label: String { ["PST", "PRS", "FTR", "BYD", "ETR"][rawValue] }
}

public struct ChartID: Hashable, Codable, Sendable {
    public let songID: String
    public let difficulty: Difficulty
    public init(songID: String, difficulty: Difficulty) {
        self.songID = songID; self.difficulty = difficulty
    }
    public var key: String { "\(songID):\(difficulty.rawValue)" }
}

/// Raw integer timestamps retain the source's units and precision; no date is invented.
public struct SourceTimestamp: Hashable, Codable, Sendable {
    public enum Unit: String, Codable, Sendable { case seconds, milliseconds }
    public enum Origin: String, Codable, Sendable { case server, manual }
    public let value: Int64
    public let unit: Unit
    public let origin: Origin
    public init(value: Int64, unit: Unit, origin: Origin = .server) {
        self.value = value; self.unit = unit; self.origin = origin
    }
    public var milliseconds: Int64? {
        guard value >= 0 else { return nil }
        let result = value.multipliedReportingOverflow(by: unit == .seconds ? 1_000 : 1)
        guard !result.overflow, result.partialValue <= 253_402_300_799_999 else { return nil }
        return result.partialValue
    }
    public var date: Date? { milliseconds.map { Date(timeIntervalSince1970: Double($0) / 1_000) } }
}

public enum ClearType: Int, CaseIterable, Codable, Sendable {
    case trackLost = 0, normal = 1, fullRecall = 2, pureMemory = 3, easy = 4, hard = 5
    public var hasRatingBonus: Bool { [1, 2, 3, 5].contains(rawValue) }
    public var precedence: Int { [0, 2, 4, 5, 1, 3][rawValue] }
}

public struct Judgments: Hashable, Codable, Sendable {
    public let pure: Int?
    public let shinyPure: Int?
    public let far: Int?
    public let lost: Int?
    public let early: Int?
    public let late: Int?
    public init(pure: Int? = nil, shinyPure: Int? = nil, far: Int? = nil, lost: Int? = nil,
                early: Int? = nil, late: Int? = nil) {
        self.pure = pure; self.shinyPure = shinyPure; self.far = far; self.lost = lost
        self.early = early; self.late = late
    }
}

/// A coherent payload from one attempt. Best clear is an independent chart lamp.
public struct ScoreValues: Hashable, Codable, Sendable {
    public let score: Int
    public let playedAt: SourceTimestamp?
    public let judgments: Judgments?
    public let playClear: ClearType?
    public let bestClear: ClearType?
    public let modifier: Int?
    public let health: Int?
    public init(score: Int, playedAt: SourceTimestamp? = nil, judgments: Judgments? = nil,
                playClear: ClearType? = nil, bestClear: ClearType? = nil, modifier: Int? = nil, health: Int? = nil) {
        self.score = score; self.playedAt = playedAt; self.judgments = judgments
        self.playClear = playClear; self.bestClear = bestClear
        self.modifier = modifier; self.health = health
    }
}

public enum ObservationSource: String, Codable, Sendable {
    case officialImport, officialRecent, manual
}
public enum IdentityConfidence: String, Codable, Sendable {
    case sourceEvent, exactTimestampAndPayload, payloadOnly, manual
}

public struct ScoreObservation: Hashable, Codable, Sendable {
    public let id: ObservationID
    public let accountID: AccountID
    public let chartID: ChartID
    public let source: ObservationSource
    public let values: ScoreValues
    public let firstSeenAt: Date
    public let identityConfidence: IdentityConfidence
    public init(id: ObservationID, accountID: AccountID, chartID: ChartID, source: ObservationSource,
                values: ScoreValues, firstSeenAt: Date, identityConfidence: IdentityConfidence = .sourceEvent) {
        self.id = id; self.accountID = accountID; self.chartID = chartID; self.source = source
        self.values = values; self.firstSeenAt = firstSeenAt; self.identityConfidence = identityConfidence
    }
    public var score: Int { values.score }

    public static func remote(accountID: AccountID, chartID: ChartID, source: ObservationSource,
                              values: ScoreValues, firstSeenAt: Date, eventID: String? = nil) throws -> ScoreObservation {
        guard source != .manual else { throw ArchiveError.invalidRecord("Remote observation cannot have a manual source") }
        try ArchiveValidation.account(accountID); try ArchiveValidation.chartID(chartID)
        try ArchiveValidation.values(values); try ArchiveValidation.date(firstSeenAt)
        var components = ["official-v1", accountID.rawValue]
        let confidence: IdentityConfidence
        if let eventID {
            try ArchiveValidation.identifier(eventID, label: "source event ID")
            components += ["event", eventID]
            confidence = .sourceEvent
        } else if let time = values.playedAt?.milliseconds {
            // Optional judgments/gauge and chart-level lamps can be absent or enriched later.
            components += ["play", chartID.key, String(time), String(values.score)]
            confidence = .exactTimestampAndPayload
        } else {
            components += ["uncertain", chartID.key, String(values.score)]
            confidence = .payloadOnly
        }
        let key = components.map { "\($0.utf8.count):\($0)" }.joined()
        return ScoreObservation(id: ObservationID(key), accountID: accountID, chartID: chartID,
            source: source, values: values, firstSeenAt: firstSeenAt, identityConfidence: confidence)
    }
}

public struct AccountProfile: Hashable, Codable, Sendable {
    public let id: AccountID
    public let displayName: String?
    public init(id: AccountID, displayName: String? = nil) { self.id = id; self.displayName = displayName }
}

public struct EffectiveObservation: Hashable, Codable, Sendable {
    public let original: ScoreObservation
    public let values: ScoreValues
    public let isOverridden: Bool
}

public struct BestScore: Hashable, Codable, Sendable {
    public let accountID: AccountID
    public let chartID: ChartID
    public let observationID: ObservationID?
    public let values: ScoreValues
    public let bestClear: ClearType?
    public let isOverridden: Bool
    public let isBestCorrection: Bool
}
