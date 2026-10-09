import Foundation

internal struct ObservationOverrideRecord: Codable {
    let observationID: ObservationID
    let values: ScoreValues
}
internal struct ArchivePayload: Codable {
    var schemaVersion: Int
    var createdAt: Date
    var profiles: [AccountProfile]
    var charts: [ChartMetadata]
    var observations: [ScoreObservation]
    var captures: [ScoreObservation]
    var aliases: [ObservationAlias]
    var overrides: [ObservationOverrideRecord]
    var suppressions: [SuppressionMarker]
    var bestCorrections: [BestCorrection]
    var potentialPoints: [PotentialPoint]
    var receipts: [ImportReceipt]
    var undoRecords: [ManualUndoRecord]
    var potentialBaselines: [PotentialBaseline]? = nil
}

public struct ArchiveBackup: Sendable {
    public static let schemaVersion = 1
    public let store: ArchiveStore
    public init(store: ArchiveStore) { self.store = store }
    public func export() throws -> Data {
        try store.locked {
            try store.database.transaction(write: false) {
                let observations: [ScoreObservation] = try store.records("SELECT payload FROM observations ORDER BY observation_id")
                let overrides = try observations.compactMap { observation -> ObservationOverrideRecord? in
                    let values: ScoreValues? = try store.record("SELECT payload FROM overrides WHERE observation_id=?", [.text(observation.id.rawValue)])
                    return values.map { ObservationOverrideRecord(observationID: observation.id, values: $0) }
                }
                let payload = ArchivePayload(schemaVersion: Self.schemaVersion, createdAt: Date(),
                    profiles: try store.records("SELECT payload FROM profiles ORDER BY account_id"),
                    charts: try store.records("SELECT payload FROM charts ORDER BY song_id, difficulty"),
                    observations: observations,
                    captures: try store.records("SELECT payload FROM observation_captures ORDER BY observation_id, capture_id"),
                    aliases: try store.records("SELECT payload FROM observation_aliases ORDER BY external_id"),
                    overrides: overrides,
                    suppressions: try store.records("SELECT payload FROM suppressions ORDER BY observation_id"),
                    bestCorrections: try store.records("SELECT payload FROM best_corrections ORDER BY account_id, song_id, difficulty"),
                    potentialPoints: try store.records("SELECT payload FROM potential_points ORDER BY account_id, series, source_id"),
                    receipts: try store.records("SELECT payload FROM receipts ORDER BY id"),
                    undoRecords: try store.records("SELECT payload FROM manual_undo ORDER BY sequence"),
                    potentialBaselines: try store.records("SELECT payload FROM potential_baselines ORDER BY account_id"))
                let data = try store.encoder.encode(payload)
                guard data.count <= Self.maximumBytes else { throw ArchiveError.oversizedBackup }
                return data
            }
        }
    }

    /// Replaces the score archive only after full validation. Session stores are never read or written.
    public func validateAndRestore(data: Data, cancellationCheck: () throws -> Void = {
        if Task<Never, Never>.isCancelled { throw CancellationError() }
    }) throws -> ImportReceipt {
        guard data.count <= Self.maximumBytes else { throw ArchiveError.oversizedBackup }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let version = object["schemaVersion"] as? Int else {
            throw ArchiveError.invalidRecord("Backup has no schema version")
        }
        guard version == Self.schemaVersion else { throw ArchiveError.unsupportedVersion(version) }
        let payload = try JSONDecoder().decode(ArchivePayload.self, from: data)
        try validate(payload)
        try cancellationCheck()
        return try store.locked {
            try store.database.transaction {
                try cancellationCheck()
                for table in ["potential_baselines", "manual_undo", "overrides", "suppressions", "best_corrections", "observation_aliases", "observation_captures", "observations", "potential_points", "receipts", "charts", "profiles"] {
                    try store.database.execute("DELETE FROM \(table)")
                }
                try cancellationCheck()
                for profile in payload.profiles {
                    try cancellationCheck()
                    try store.database.execute("INSERT INTO profiles(account_id, payload) VALUES(?, ?)",
                        [.text(profile.id.rawValue), .blob(try store.encoder.encode(profile))])
                }
                for chart in payload.charts { try cancellationCheck(); try store.putChart(chart) }
                for observation in payload.observations { try cancellationCheck(); try store.putObservation(observation) }
                for alias in payload.aliases { try cancellationCheck(); try store.putAlias(alias) }
                // Canonical insertion creates a first capture; replace with the exact backed-up evidence.
                try store.database.execute("DELETE FROM observation_captures")
                for capture in payload.captures { try cancellationCheck(); try store.putCapture(capture) }
                for baseline in payload.potentialBaselines ?? [] {
                    try store.putPotentialBaseline(baseline)
                }
                for value in payload.overrides { try cancellationCheck(); try store.setOverride(value.observationID, value.values) }
                for marker in payload.suppressions { try cancellationCheck(); try store.setSuppression(marker.observationID, marker) }
                for correction in payload.bestCorrections {
                    try cancellationCheck(); try store.setCorrection(correction.accountID, correction.chartID, correction)
                }
                for point in payload.potentialPoints {
                    try cancellationCheck()
                    try store.database.execute("INSERT INTO potential_points(account_id, series, source_id, payload) VALUES(?, ?, ?, ?)",
                        [.text(point.accountID.rawValue), .text(point.series.rawValue), .text(point.sourceID), .blob(try store.encoder.encode(point))])
                }
                for receipt in payload.receipts { try cancellationCheck(); try store.putReceipt(receipt) }
                for undo in payload.undoRecords {
                    try cancellationCheck()
                    try store.database.execute("INSERT INTO manual_undo(id, payload) VALUES(?, ?)",
                        [.text(undo.token.id.uuidString), .blob(try store.encoder.encode(undo))])
                }
                try cancellationCheck()
                return ImportReceipt(accountID: nil, kind: .restore, importedAt: Date(), addedCount: payload.observations.count,
                                     duplicateCount: 0, addedPotentialCount: payload.potentialPoints.count)
            }
        }
    }

    private static let maximumBytes = 64 * 1_024 * 1_024

    private func validate(_ payload: ArchivePayload) throws {
        guard payload.schemaVersion == Self.schemaVersion else { throw ArchiveError.unsupportedVersion(payload.schemaVersion) }
        try ArchiveValidation.date(payload.createdAt)
        let counts = [payload.profiles.count, payload.charts.count, payload.observations.count,
                      payload.captures.count, payload.aliases.count, payload.overrides.count, payload.suppressions.count,
                      payload.bestCorrections.count, payload.potentialPoints.count, payload.receipts.count, payload.undoRecords.count]
        guard counts.allSatisfy({ $0 <= 500_000 }) else { throw ArchiveError.oversizedBackup }
        try unique(payload.profiles.map(\.id)); try unique(payload.charts.map(\.id)); try unique(payload.observations.map(\.id))
        try unique(payload.overrides.map(\.observationID)); try unique(payload.suppressions.map(\.observationID))
        try unique(payload.receipts.map(\.id)); try unique(payload.undoRecords.map(\.token))
        let profiles = Set(payload.profiles.map(\.id)), catalog = ChartCatalog(charts: payload.charts)
        for profile in payload.profiles { try ArchiveValidation.profile(profile) }
        for chart in payload.charts { try ArchiveValidation.metadata(chart) }
        let observations = Dictionary(uniqueKeysWithValues: payload.observations.map { ($0.id, $0) })
        for observation in payload.observations {
            guard profiles.contains(observation.accountID) else { throw ArchiveError.accountMismatch }
            try ArchiveValidation.observation(observation, metadata: catalog[observation.chartID])
        }
        try unique(payload.aliases.map(\.externalID))
        for alias in payload.aliases {
            try ArchiveValidation.identifier(alias.externalID.rawValue, label: "external observation ID", limit: 4_000)
            _ = try referenced(alias.observationID, observations)
            guard observations[alias.externalID] == nil else { throw ArchiveError.identityCollision(alias.externalID.rawValue) }
        }
        let captures = Dictionary(grouping: payload.captures, by: \.id)
        guard Set(captures.keys) == Set(observations.keys) else { throw ArchiveError.invalidRecord("Backup capture references are incomplete") }
        for (id, group) in captures {
            guard let original = observations[id], group.count <= 256 else { throw ArchiveError.invalidRecord("Invalid capture collection") }
            var identities: Set<Data> = []
            struct Identity: Encodable { let source: ObservationSource; let values: ScoreValues; let confidence: IdentityConfidence }
            for (index, capture) in group.enumerated() {
                try ArchiveValidation.observation(capture, metadata: catalog[capture.chartID])
                guard store.compatible(original, capture), group.prefix(index).allSatisfy({ store.compatible($0, capture) }) else {
                    throw ArchiveError.identityCollision(id.rawValue)
                }
                let data = try store.encoder.encode(Identity(source: capture.source, values: capture.values, confidence: capture.identityConfidence))
                guard identities.insert(data).inserted else { throw ArchiveError.identityCollision(id.rawValue) }
            }
        }
        for value in payload.overrides {
            let observation = try referenced(value.observationID, observations)
            try ArchiveValidation.values(value.values, metadata: catalog[observation.chartID])
        }
        for marker in payload.suppressions {
            _ = try referenced(marker.observationID, observations); try ArchiveValidation.date(marker.suppressedAt)
        }
        try unique(payload.bestCorrections.map { CorrectionIdentity(accountID: $0.accountID, chartID: $0.chartID) })
        for correction in payload.bestCorrections { try validateCorrection(correction, profiles: profiles, observations: observations, catalog: catalog) }
        try unique(payload.potentialPoints.map { PotentialIdentity(accountID: $0.accountID, sourceID: $0.sourceID, series: $0.series) })
        for point in payload.potentialPoints {
            guard profiles.contains(point.accountID) else { throw ArchiveError.accountMismatch }
            try ArchiveValidation.potential(point)
        }
        let baselines = payload.potentialBaselines ?? []
        guard baselines.count <= payload.profiles.count else { throw ArchiveError.oversizedBackup }
        try unique(baselines.map(\.accountID))
        for baseline in baselines {
            guard profiles.contains(baseline.accountID), payload.potentialPoints.contains(baseline.anchor) else {
                throw ArchiveError.invalidRecord("Potential baseline has no official anchor")
            }
            try baseline.validate()
        }
        for receipt in payload.receipts {
            if let account = receipt.accountID, !profiles.contains(account) { throw ArchiveError.accountMismatch }
            try ArchiveValidation.date(receipt.importedAt)
            guard [receipt.addedCount, receipt.duplicateCount, receipt.addedPotentialCount].allSatisfy({ (0...500_000).contains($0) }) else {
                throw ArchiveError.invalidRecord("Invalid receipt counts")
            }
        }
        for undo in payload.undoRecords {
            switch undo.state {
            case .added(let id, let createdProfile):
                let observation = try referenced(id, observations)
                guard observation.source == .manual, createdProfile == nil || createdProfile == observation.accountID else {
                    throw ArchiveError.invalidRecord("Invalid manual undo reference")
                }
            case .override(let id, let values):
                let observation = try referenced(id, observations)
                if let values { try ArchiveValidation.values(values, metadata: catalog[observation.chartID]) }
            case .suppression(let id, let marker):
                _ = try referenced(id, observations)
                if let marker {
                    guard marker.observationID == id else { throw ArchiveError.invalidRecord("Invalid suppression undo reference") }
                    try ArchiveValidation.date(marker.suppressedAt)
                }
            case .correction(let account, let chart, let correction):
                guard profiles.contains(account) else { throw ArchiveError.accountMismatch }
                try ArchiveValidation.chartID(chart)
                if let correction {
                    guard correction.accountID == account, correction.chartID == chart else { throw ArchiveError.accountMismatch }
                    try validateCorrection(correction, profiles: profiles, observations: observations, catalog: catalog)
                }
            }
        }
    }

    private func validateCorrection(_ correction: BestCorrection, profiles: Set<AccountID>,
                                    observations: [ObservationID: ScoreObservation], catalog: ChartCatalog) throws {
        guard profiles.contains(correction.accountID) else { throw ArchiveError.accountMismatch }
        if let date = correction.recordedAt {
            guard date.timeIntervalSince1970.isFinite, (0...253_402_300_799).contains(date.timeIntervalSince1970) else {
                throw ArchiveError.invalidRecord("Invalid correction date")
            }
        }
        try ArchiveValidation.chartID(correction.chartID)
        try ArchiveValidation.values(correction.values, metadata: catalog[correction.chartID])
        for id in correction.baselineIDs {
            let observation = try referenced(id, observations)
            guard observation.accountID == correction.accountID, observation.chartID == correction.chartID else { throw ArchiveError.accountMismatch }
        }
    }
    private func referenced(_ id: ObservationID, _ observations: [ObservationID: ScoreObservation]) throws -> ScoreObservation {
        guard let observation = observations[id] else { throw ArchiveError.notFound("Backup observation reference") }
        return observation
    }
    private func unique<T: Hashable>(_ values: [T]) throws {
        guard Set(values).count == values.count else { throw ArchiveError.invalidRecord("Duplicate backup identity") }
    }
}

private struct CorrectionIdentity: Hashable { let accountID: AccountID; let chartID: ChartID }
private struct PotentialIdentity: Hashable { let accountID: AccountID; let sourceID: String; let series: PotentialSeries }
