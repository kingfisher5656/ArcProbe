import Foundation

public enum ManualChange: Codable, Sendable {
    case add(ScoreObservation)
    case override(accountID: AccountID, observationID: ObservationID, values: ScoreValues)
    case suppress(accountID: AccountID, observationID: ObservationID)
    case restore(accountID: AccountID, observationID: ObservationID)
    case resetOverride(accountID: AccountID, observationID: ObservationID)
    case correctBest(accountID: AccountID, chartID: ChartID, values: ScoreValues)
    case resetBestCorrection(accountID: AccountID, chartID: ChartID)
}

public struct UndoToken: Hashable, Codable, Sendable {
    public let id: UUID
    public init(id: UUID) { self.id = id }
}
