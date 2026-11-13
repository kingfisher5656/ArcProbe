import Foundation

extension ArchiveStore {
    /// Runs inside the import transaction, so failed validation restores scores and undo together.
    internal func prepareOfficialImport(_ batch: ImportBatch) throws -> Bool {
        guard batch.kind == .full, batch.observations.allSatisfy({ $0.source == .officialImport }) else { return false }
        let receipts: [ImportReceipt] = try records("SELECT payload FROM receipts WHERE account_id=?", [.text(batch.profile.id.rawValue)])
        guard !receipts.contains(where: { $0.kind == .full && $0.importedAt > batch.importedAt }) else {
            throw ArchiveError.invalidRecord("This official import is older than the last completed sync")
        }
        let official = Dictionary(grouping: batch.observations, by: \.chartID).mapValues { $0.map(\.score).max()! }
        var affected: Set<ObservationID> = [], removed: Set<ObservationID> = []
        for (chart, score) in official {
            let observations: [ScoreObservation] = try records("SELECT payload FROM observations WHERE account_id=? AND song_id=? AND difficulty=?", correctionKey(batch.profile.id, chart))
            for observation in observations {
                affected.insert(observation.id)
                // Retain lower historical attempts. A contradictory local high must not win again.
                if (observation.source == .manual || observation.source == .consultantSheet), observation.score > score {
                    try database.execute("DELETE FROM observations WHERE observation_id=?", [.text(observation.id.rawValue)])
                    removed.insert(observation.id)
                } else {
                    try setOverride(observation.id, nil)
                    try setSuppression(observation.id, nil)
                }
            }
            try setCorrection(batch.profile.id, chart, nil)
        }
        // Missing-chart cleanup is limited to this account's manual/sheet records.
        let accountRows: [ScoreObservation] = try records("SELECT payload FROM observations WHERE account_id=?", [.text(batch.profile.id.rawValue)])
        var clearedCharts = Set(official.keys)
        for row in accountRows where official[row.chartID] == nil && (row.source == .manual || row.source == .consultantSheet) {
            try database.execute("DELETE FROM observations WHERE observation_id=?", [.text(row.id.rawValue)])
            affected.insert(row.id); removed.insert(row.id); clearedCharts.insert(row.chartID)
        }
        // A manually entered chart best can also exist without any saved observation.
        let observedCharts = Set(accountRows.map(\.chartID))
        let corrections: [BestCorrection] = try records("SELECT payload FROM best_corrections WHERE account_id=?", [.text(batch.profile.id.rawValue)])
        for correction in corrections where !observedCharts.contains(correction.chartID) {
            clearedCharts.insert(correction.chartID)
        }
        let undo: [ManualUndoRecord] = try records("SELECT payload FROM manual_undo")
        for record in undo {
            if case .correction(let account, let chart, let previous) = record.state,
               account == batch.profile.id, previous != nil, !observedCharts.contains(chart) {
                clearedCharts.insert(chart)
            }
        }
        for chart in clearedCharts { try setCorrection(batch.profile.id, chart, nil) }
        // Older Undo actions must not revive adjustments superseded by this official snapshot.
        for record in undo {
            let invalid: Bool
            switch record.state {
            case .added(let id, _): invalid = removed.contains(id)
            case .override(let id, _), .suppression(let id, _): invalid = affected.contains(id)
            case .correction(let account, let chart, _): invalid = account == batch.profile.id && clearedCharts.contains(chart)
            }
            if invalid { try database.execute("DELETE FROM manual_undo WHERE id=?", [.text(record.token.id.uuidString)]) }
        }
        return true
    }
}
