import ArcaeaCore
import ConsultantProbeCore

@MainActor final class GoogleConsultantExportRemote: ConsultantExportRemote {
    let api: GoogleSheetAPI
    init(api: GoogleSheetAPI) { self.api = api }
    func exportSnapshot(fileID: String, inputTab: String) async throws -> ConsultantExportSnapshot {
        let data = try await api.scoreExportData(fileID: fileID, inputTab: inputTab)
        return try ConsultantExportSnapshot.decode(evaluated: data.evaluated, raw: data.raw)
    }
    func writeScores(fileID: String, inputTab: String, changes: [ConsultantScoreWrite]) async throws {
        guard Set(changes.map(\.row)).count == changes.count else { throw ConsultantExportError.layout }
        do {
            try await api.writeMobileScores(fileID: fileID, inputTab: inputTab, scores: Dictionary(uniqueKeysWithValues: changes.map { ($0.row, $0.score) }))
        } catch let error as SheetWriteNotSent {
            throw ConsultantWriteNotSent(underlying: error.underlying)
        }
    }
}
