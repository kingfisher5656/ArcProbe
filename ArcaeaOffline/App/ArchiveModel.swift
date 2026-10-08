import ArcaeaCore
import Foundation
import Observation

@MainActor @Observable
final class ArchiveModel {
    let store: ArchiveStore
    private(set) var catalog: ChartCatalog
    var profiles: [AccountProfile] = []
    var selectedAccountID: AccountID?
    var observations: [EffectiveObservation] = []
    private(set) var captureSources: [ObservationID: Set<ObservationSource>] = [:]
    var recentObservations: [EffectiveObservation] { observations.filter { captureSources[$0.original.id]?.contains(.officialRecent) == true || $0.original.source == .officialRecent } }
    var bestScores: [BestScore] = []
    var officialHistory: [PotentialPoint] = []
    private(set) var revision = 0
    var ranking: RankingSnapshot?
    var errorMessage: String?
    var notice: String?
    var undoToken: UndoToken?

    init(store: ArchiveStore, catalog: ChartCatalog) throws {
        self.store = store
        self.catalog = catalog
        try reload()
    }
    func reload() throws {
        defer { revision += 1 }
        profiles = try store.profiles()
        catalog = try store.chartCatalog()
        if selectedAccountID == nil || !profiles.contains(where: { $0.id == selectedAccountID }) { selectedAccountID = profiles.first?.id }
        undoToken = try store.latestUndoToken()
        guard let account = selectedAccountID else { observations = []; bestScores = []; officialHistory = []; captureSources = [:]; ranking = nil; return }
        observations = try store.observations(accountID: account)
        captureSources = try store.captureSources(accountID: account)
        bestScores = try store.bestScores(accountID: account)
        officialHistory = try store.potentialHistory(accountID: account).sorted { ($0.timestamp.date ?? .distantPast) < ($1.timestamp.date ?? .distantPast) }
        ranking = try RatingCalculator(catalog: catalog).rank(bestScores: bestScores)
    }
    func save(_ draft: ScoreDraft, editing observationID: ObservationID? = nil, correctingBest: Bool = false) throws {
        guard (0...10_100_000).contains(draft.score) else { throw ArchiveError.invalidRecord("Score must be between 0 and 10,100,000.") }
        let account = selectedAccountID ?? AccountID("local")
        let previous = observationID.flatMap { id in observations.first { $0.original.id == id }?.values }
        let timestamp = try draft.playedAt.map { date in
            if let original = previous?.playedAt, original.date == date { return original }
            let millis = (date.timeIntervalSince1970 * 1000).rounded(.towardZero)
            guard millis.isFinite, let value = Int64(exactly: millis) else { throw ArchiveError.invalidRecord("Date is outside the supported range.") }
            return SourceTimestamp(value: value, unit: .milliseconds, origin: .manual)
        }
        let values = ScoreValues(score: draft.score, playedAt: timestamp, judgments: draft.judgments, playClear: draft.playClear, bestClear: draft.bestClear, modifier: draft.clearModifier ? nil : draft.modifier ?? previous?.modifier, health: draft.clearHealth ? nil : draft.health ?? previous?.health)
        let change: ManualChange
        if correctingBest { change = .correctBest(accountID: account, chartID: draft.chartID, values: values) }
        else if let observationID { change = .override(accountID: account, observationID: observationID, values: values) }
        else { change = .add(ScoreObservation(id: ObservationID(UUID().uuidString), accountID: account, chartID: draft.chartID, source: .manual, values: values, firstSeenAt: Date(), identityConfidence: .manual)) }
        undoToken = try store.applyManual(change: change)
        selectedAccountID = account
        try reload()
        notice = correctingBest ? "Chart best corrected" : observationID == nil ? "Score saved" : "Play updated"
    }
    func delete(_ observation: EffectiveObservation) throws {
        undoToken = try store.applyManual(change: .suppress(accountID: observation.original.accountID, observationID: observation.original.id))
        try reload(); notice = "Play deleted"
    }
    func undoLastChange() throws {
        guard let undoToken else { return }
        try store.undo(undoToken)
        try reload(); notice = "Change undone"
    }
    func resetBest(_ chart: ChartID) throws {
        guard let account = selectedAccountID else { return }
        undoToken = try store.applyManual(change: .resetBestCorrection(accountID: account, chartID: chart))
        try reload(); notice = "Imported chart best restored"
    }
    func resetOverride(_ play: EffectiveObservation) throws {
        undoToken = try store.applyManual(change: .resetOverride(accountID: play.original.accountID, observationID: play.original.id))
        try reload(); notice = "Original play restored"
    }
    func backupFile() throws -> ShareFile {
        let data = try ArchiveBackup(store: store).export()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ArcaeaOfflineExports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Arcaea-Offline-backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))).json")
        try data.write(to: url, options: .atomic)
        return ShareFile(url: url)
    }
    func restoreBackup(_ data: Data) throws {
        let receipt = try ArchiveBackup(store: store).validateAndRestore(data: data)
        try reload(); notice = "Backup restored: \(receipt.addedCount) plays added"
    }
}

struct ScoreDraft {
    var chartID: ChartID
    var score: Int
    var playedAt: Date?
    var judgments: Judgments?
    var playClear: ClearType?
    var bestClear: ClearType?
    var modifier: Int?
    var health: Int?
    var clearModifier = false
    var clearHealth = false
}
