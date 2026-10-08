import Foundation

internal struct ObservationAlias: Hashable, Codable {
    let externalID: ObservationID
    let observationID: ObservationID
}

extension ArchiveStore {
    internal func canonicalID(_ id: ObservationID) throws -> ObservationID {
        let alias: ObservationAlias? = try record("SELECT payload FROM observation_aliases WHERE external_id=?", [.text(id.rawValue)])
        return alias?.observationID ?? id
    }

    internal func resolveObservation(_ incoming: ScoreObservation) throws -> ScoreObservation {
        let resolved = try canonicalID(incoming.id)
        if resolved != incoming.id { return replacingID(incoming, resolved) }
        if try database.integer("SELECT 1 FROM observations WHERE observation_id=?", [.text(incoming.id.rawValue)]) != nil { return incoming }
        guard incoming.source != .manual, let timestamp = incoming.values.playedAt?.milliseconds else { return incoming }
        let candidates: [ScoreObservation] = try records("SELECT payload FROM observations WHERE account_id=? AND song_id=? AND difficulty=?",
            [.text(incoming.accountID.rawValue), .text(incoming.chartID.songID), .integer(Int64(incoming.chartID.difficulty.rawValue))])
        var matching: [ScoreObservation] = []
        for candidate in candidates where candidate.source != .manual && candidate.score == incoming.score {
            let captures = try capturesUnlocked(observationID: candidate.id)
            guard captures.contains(where: { $0.values.playedAt?.milliseconds == timestamp }) else { continue }
            // Distinct verified source events remain distinct even if timestamps have coarse precision.
            if incoming.identityConfidence == .sourceEvent,
               captures.contains(where: { $0.identityConfidence == .sourceEvent }) { continue }
            guard compatible(candidate, incoming), captures.allSatisfy({ compatible($0, incoming) }) else {
                throw ArchiveError.identityCollision(incoming.id.rawValue)
            }
            matching.append(candidate)
        }
        guard matching.count <= 1 else { throw ArchiveError.invalidRecord("Ambiguous remote attempt identity") }
        guard let candidate = matching.first else { return incoming }
        try putAlias(ObservationAlias(externalID: incoming.id, observationID: candidate.id))
        return replacingID(incoming, candidate.id)
    }

    internal func putAlias(_ alias: ObservationAlias) throws {
        try database.execute("INSERT INTO observation_aliases(external_id, observation_id, payload) VALUES(?, ?, ?)",
            [.text(alias.externalID.rawValue), .text(alias.observationID.rawValue), .blob(try encoder.encode(alias))])
    }

    private func replacingID(_ observation: ScoreObservation, _ id: ObservationID) -> ScoreObservation {
        ScoreObservation(id: id, accountID: observation.accountID, chartID: observation.chartID,
            source: observation.source, values: observation.values, firstSeenAt: observation.firstSeenAt,
            identityConfidence: observation.identityConfidence)
    }
}

extension PotentialValue {
    internal func equivalent(to other: PotentialValue) -> Bool {
        func normalized(_ value: PotentialValue) -> (Int64, Int) {
            var raw = value.rawValue, places = value.decimalPlaces
            while places > 0, raw % 10 == 0 { raw /= 10; places -= 1 }
            return (raw, places)
        }
        let a = normalized(self), b = normalized(other)
        return a.0 == b.0 && a.1 == b.1
    }
}
