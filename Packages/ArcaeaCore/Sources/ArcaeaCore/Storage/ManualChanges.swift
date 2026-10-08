import Foundation

internal struct SuppressionMarker: Hashable, Codable {
    let observationID: ObservationID
    let suppressedAt: Date
}
internal enum ManualUndoState: Codable {
    case added(ObservationID, createdProfile: AccountID?)
    case override(ObservationID, ScoreValues?)
    case suppression(ObservationID, SuppressionMarker?)
    case correction(AccountID, ChartID, BestCorrection?)
}
internal struct ManualUndoRecord: Codable {
    let token: UndoToken
    let state: ManualUndoState
}

extension ArchiveStore {
    /// Undo is durable and chronological; stale tokens cannot overwrite a newer edit.
    @discardableResult public func applyManual(change: ManualChange) throws -> UndoToken {
        try locked {
            try database.transaction {
                let catalog = try catalogUnlocked()
                let state: ManualUndoState
                switch change {
                case .add(let observation):
                    guard observation.source == .manual else { throw ArchiveError.invalidRecord("Manual add requires a manual source") }
                    try ArchiveValidation.observation(observation, metadata: catalog[observation.chartID])
                    guard try database.integer("SELECT 1 FROM observations WHERE observation_id=?", [.text(observation.id.rawValue)]) == nil else {
                        throw ArchiveError.identityCollision(observation.id.rawValue)
                    }
                    let isNewAccount = try database.integer("SELECT 1 FROM profiles WHERE account_id=?", [.text(observation.accountID.rawValue)]) == nil
                    if isNewAccount {
                        let profile = AccountProfile(id: observation.accountID)
                        try database.execute("INSERT INTO profiles(account_id, payload) VALUES(?, ?)",
                            [.text(profile.id.rawValue), .blob(try encoder.encode(profile))])
                    }
                    try putObservation(observation)
                    state = .added(observation.id, createdProfile: isNewAccount ? observation.accountID : nil)
                case .override(let account, let id, let values):
                    let observation = try requireObservation(id, owner: account)
                    let id = observation.id
                    try ArchiveValidation.values(values, metadata: catalog[observation.chartID])
                    let previous: ScoreValues? = try record("SELECT payload FROM overrides WHERE observation_id=?", [.text(id.rawValue)])
                    try setOverride(id, values)
                    state = .override(id, previous)
                case .resetOverride(let account, let id):
                    let id = try requireObservation(id, owner: account).id
                    let previous: ScoreValues? = try record("SELECT payload FROM overrides WHERE observation_id=?", [.text(id.rawValue)])
                    try setOverride(id, nil)
                    state = .override(id, previous)
                case .suppress(let account, let id), .restore(let account, let id):
                    let id = try requireObservation(id, owner: account).id
                    let previous: SuppressionMarker? = try record("SELECT payload FROM suppressions WHERE observation_id=?", [.text(id.rawValue)])
                    if case .suppress = change { try setSuppression(id, SuppressionMarker(observationID: id, suppressedAt: Date())) }
                    else { try setSuppression(id, nil) }
                    state = .suppression(id, previous)
                case .correctBest(let account, let chart, let values):
                    try requireProfile(account); try ArchiveValidation.chartID(chart)
                    try ArchiveValidation.values(values, metadata: catalog[chart])
                    let previous = try correction(account, chart)
                    let source: [ScoreObservation] = try records("SELECT payload FROM observations WHERE account_id=? AND song_id=? AND difficulty=?", correctionKey(account, chart))
                    try setCorrection(account, chart, BestCorrection(accountID: account, chartID: chart, values: values, baselineIDs: Set(source.map(\.id))))
                    state = .correction(account, chart, previous)
                case .resetBestCorrection(let account, let chart):
                    try requireProfile(account); try ArchiveValidation.chartID(chart)
                    let previous = try correction(account, chart)
                    try setCorrection(account, chart, nil)
                    state = .correction(account, chart, previous)
                }
                let token = UndoToken(id: UUID())
                try database.execute("INSERT INTO manual_undo(id, payload) VALUES(?, ?)",
                    [.text(token.id.uuidString), .blob(try encoder.encode(ManualUndoRecord(token: token, state: state)))])
                return token
            }
        }
    }

    public func undo(_ token: UndoToken) throws {
        try locked {
            try database.transaction {
                guard let last: ManualUndoRecord = try record("SELECT payload FROM manual_undo ORDER BY sequence DESC LIMIT 1"), last.token == token else {
                    throw ArchiveError.staleUndo
                }
                switch last.state {
                case .added(let id, let profile):
                    try database.execute("DELETE FROM observations WHERE observation_id=?", [.text(id.rawValue)])
                    if let profile {
                        try database.execute("DELETE FROM profiles WHERE account_id=? AND NOT EXISTS(SELECT 1 FROM observations WHERE account_id=profiles.account_id) AND NOT EXISTS(SELECT 1 FROM potential_points WHERE account_id=profiles.account_id) AND NOT EXISTS(SELECT 1 FROM receipts WHERE account_id=profiles.account_id) AND NOT EXISTS(SELECT 1 FROM best_corrections WHERE account_id=profiles.account_id)", [.text(profile.rawValue)])
                    }
                case .override(let id, let values): try setOverride(id, values)
                case .suppression(let id, let marker): try setSuppression(id, marker)
                case .correction(let account, let chart, let previous): try setCorrection(account, chart, previous)
                }
                try database.execute("DELETE FROM manual_undo WHERE id=?", [.text(token.id.uuidString)])
            }
        }
    }

    public func latestUndoToken() throws -> UndoToken? {
        try locked {
            let record: ManualUndoRecord? = try record("SELECT payload FROM manual_undo ORDER BY sequence DESC LIMIT 1")
            return record?.token
        }
    }

    internal func requireProfile(_ account: AccountID) throws {
        try ArchiveValidation.account(account)
        guard try database.integer("SELECT 1 FROM profiles WHERE account_id=?", [.text(account.rawValue)]) != nil else {
            throw ArchiveError.notFound("Account profile")
        }
    }
    internal func requireObservation(_ id: ObservationID, owner: AccountID) throws -> ScoreObservation {
        let id = try canonicalID(id)
        guard let observation: ScoreObservation = try record("SELECT payload FROM observations WHERE observation_id=?", [.text(id.rawValue)]) else {
            throw ArchiveError.notFound("Observation")
        }
        guard observation.accountID == owner else { throw ArchiveError.accountMismatch }
        return observation
    }
    internal func setOverride(_ id: ObservationID, _ values: ScoreValues?) throws {
        if let values {
            try database.execute("INSERT INTO overrides(observation_id, payload) VALUES(?, ?) ON CONFLICT(observation_id) DO UPDATE SET payload=excluded.payload",
                [.text(id.rawValue), .blob(try encoder.encode(values))])
        } else { try database.execute("DELETE FROM overrides WHERE observation_id=?", [.text(id.rawValue)]) }
    }
    internal func setSuppression(_ id: ObservationID, _ marker: SuppressionMarker?) throws {
        if let marker {
            try database.execute("INSERT INTO suppressions(observation_id, payload) VALUES(?, ?) ON CONFLICT(observation_id) DO UPDATE SET payload=excluded.payload",
                [.text(id.rawValue), .blob(try encoder.encode(marker))])
        } else { try database.execute("DELETE FROM suppressions WHERE observation_id=?", [.text(id.rawValue)]) }
    }
    internal func correctionKey(_ account: AccountID, _ chart: ChartID) -> [SQLValue] {
        [.text(account.rawValue), .text(chart.songID), .integer(Int64(chart.difficulty.rawValue))]
    }
    internal func correction(_ account: AccountID, _ chart: ChartID) throws -> BestCorrection? {
        try record("SELECT payload FROM best_corrections WHERE account_id=? AND song_id=? AND difficulty=?", correctionKey(account, chart))
    }
    internal func setCorrection(_ account: AccountID, _ chart: ChartID, _ value: BestCorrection?) throws {
        if let value {
            try database.execute("INSERT INTO best_corrections(account_id, song_id, difficulty, payload) VALUES(?, ?, ?, ?) ON CONFLICT(account_id, song_id, difficulty) DO UPDATE SET payload=excluded.payload",
                correctionKey(account, chart) + [.blob(try encoder.encode(value))])
        } else { try database.execute("DELETE FROM best_corrections WHERE account_id=? AND song_id=? AND difficulty=?", correctionKey(account, chart)) }
    }
}
