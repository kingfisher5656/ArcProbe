import Foundation

/// Session roles are separate even when temporarily bound to the same account.
public enum AccountRole: String, Codable, Sendable { case main, burner }
public enum PotentialSeries: String, Codable, Sendable { case official, localEstimate }

/// Exact source decimal: 12.345 is rawValue 12345, decimalPlaces 3.
public struct PotentialValue: Hashable, Codable, Sendable {
    public let rawValue: Int64
    public let decimalPlaces: Int
    public init(rawValue: Int64, decimalPlaces: Int) {
        self.rawValue = rawValue; self.decimalPlaces = decimalPlaces
    }
    public var doubleValue: Double { Double(rawValue) / pow(10, Double(decimalPlaces)) }
}

public struct PotentialPoint: Hashable, Codable, Sendable {
    public let accountID: AccountID
    public let sourceID: String
    public let timestamp: SourceTimestamp
    public let value: PotentialValue
    public let series: PotentialSeries
    public let firstSeenAt: Date
    public init(accountID: AccountID, sourceID: String, timestamp: SourceTimestamp,
                value: PotentialValue, series: PotentialSeries = .official, firstSeenAt: Date) {
        self.accountID = accountID; self.sourceID = sourceID; self.timestamp = timestamp
        self.value = value; self.series = series; self.firstSeenAt = firstSeenAt
    }
}

public enum ImportKind: String, Codable, Sendable { case full, recent, manual, restore }

public struct ImportBatch: Codable, Sendable {
    public let profile: AccountProfile
    public let observations: [ScoreObservation]
    public let potentialPoints: [PotentialPoint]
    public let charts: [ChartMetadata]
    public let importedAt: Date
    public let kind: ImportKind
    public init(profile: AccountProfile, observations: [ScoreObservation] = [],
                potentialPoints: [PotentialPoint] = [], charts: [ChartMetadata] = [],
                importedAt: Date = Date(), kind: ImportKind = .full) {
        self.profile = profile; self.observations = observations; self.potentialPoints = potentialPoints
        self.charts = charts; self.importedAt = importedAt; self.kind = kind
    }
}

public struct ImportReceipt: Hashable, Codable, Sendable {
    public let id: UUID
    public let accountID: AccountID?
    public let kind: ImportKind
    public let importedAt: Date
    public let addedCount: Int
    public let duplicateCount: Int
    public let addedPotentialCount: Int
    public init(id: UUID = UUID(), accountID: AccountID?, kind: ImportKind, importedAt: Date,
                addedCount: Int, duplicateCount: Int, addedPotentialCount: Int) {
        self.id = id; self.accountID = accountID; self.kind = kind; self.importedAt = importedAt
        self.addedCount = addedCount; self.duplicateCount = duplicateCount
        self.addedPotentialCount = addedPotentialCount
    }
}

public enum FetchStatus: String, Codable, Sendable {
    case success, unchanged, cooldown, alreadyFetching, trackingStopped, staleGeneration
    case offline, deadlineExceeded, cancelled, locked, authenticationRequired, attentionRequired
    case wrongAccount, unsupportedSchema, rateLimited, failed
}

public struct FetchResult: Codable, Sendable {
    public let status: FetchStatus
    public let addedCount: Int
    public let lastPlayAt: Date?
    public let lastSuccessAt: Date?
    public let nextEligibleAt: Date?
    public init(status: FetchStatus, addedCount: Int = 0, lastPlayAt: Date? = nil,
                lastSuccessAt: Date? = nil, nextEligibleAt: Date? = nil) {
        self.status = status; self.addedCount = addedCount; self.lastPlayAt = lastPlayAt
        self.lastSuccessAt = lastSuccessAt; self.nextEligibleAt = nextEligibleAt
    }
}
