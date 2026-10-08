import Foundation

public struct ImportProgress: Sendable {
    public enum Stage: String, Sendable { case checkingAccount, readingScores, readingHistory, verifyingAccount, saving }
    public let stage: Stage
    public let completedPages: Int
    public let difficulty: Difficulty?
    public let page: Int?
    public init(stage: Stage, completedPages: Int, difficulty: Difficulty? = nil, page: Int? = nil) {
        self.stage = stage; self.completedPages = completedPages; self.difficulty = difficulty; self.page = page
    }
}

public actor MainImportService {
    private let client: ArcaeaWebClient
    private let archive: ArchiveStore
    private let requestInterval: TimeInterval
    private var importing = false
    public init(client: ArcaeaWebClient, archive: ArchiveStore, requestInterval: TimeInterval = 1) {
        self.client = client; self.archive = archive; self.requestInterval = max(0, min(10, requestInterval))
    }

    public func sync(expectedAccount: AccountID, progress: @escaping @Sendable (ImportProgress) async -> Void = { _ in }) async throws -> ImportReceipt {
        guard !importing else { throw TrackingError.alreadyFetching }
        importing = true; defer { importing = false }
        try Task.checkCancellation()
        let now = Date()
        guard var gate = try await client.sessions.load(role: .main) else { throw OnlineError.expiredSession }
        if let next = gate.nextImportEligibleAt, next > now { throw OnlineError.rateLimited(until: next) }
        gate.nextImportEligibleAt = now.addingTimeInterval(60)
        guard try await client.sessions.compareAndSave(gate, role: .main, expectedRevision: gate.revision) else { throw OnlineError.cancelled }
        await progress(ImportProgress(stage: .checkingAccount, completedPages: 0))
        let before = try await client.readAccount(role: .main, expected: expectedAccount, expectedRevision: gate.revision)
        guard before.subscriptionActive else { throw OnlineError.subscriptionRequired }
        guard let initialSession = try await client.sessions.load(role: .main) else { throw OnlineError.expiredSession }
        guard initialSession.revision == gate.revision else { throw OnlineError.cancelled }
        let revision = gate.revision
        var observations: [ScoreObservation] = [], charts: [ChartMetadata] = []
        var completed = 0
        for difficulty in Difficulty.allCases {
            var count: Int?, read = 0
            var seen = Set<ChartID>()
            for page in 1...1_000 {
                guard completed < 1_000 else { throw OnlineError.unsupportedResponse }
                try await pause()
                await progress(ImportProgress(stage: .readingScores, completedPages: completed, difficulty: difficulty, page: page))
                let data = try await client.scorePage(difficulty: difficulty, page: page, account: expectedAccount, expectedRevision: revision)
                completed += 1
                guard count == nil || count == data.count else { throw OnlineError.unsupportedResponse }
                count = data.count
                if data.observations.isEmpty {
                    guard read == data.count else { throw OnlineError.unsupportedResponse }
                    break
                }
                for observation in data.observations {
                    guard seen.insert(observation.chartID).inserted else { throw OnlineError.unsupportedResponse }
                    observations.append(observation)
                }
                charts.append(contentsOf: data.charts)
                read += data.observations.count
                guard read <= data.count, observations.count <= 10_000 else { throw OnlineError.unsupportedResponse }
                if read == data.count { break }
                if page == 1_000 { throw OnlineError.unsupportedResponse }
            }
        }
        try await pause()
        await progress(ImportProgress(stage: .readingHistory, completedPages: completed))
        let history = try await client.history(account: expectedAccount, expectedRevision: revision)
        guard history.count <= 100_000 else { throw OnlineError.oversizedResponse }
        try await pause()
        await progress(ImportProgress(stage: .verifyingAccount, completedPages: completed))
        let after = try await client.readAccount(role: .main, expected: expectedAccount, expectedRevision: gate.revision)
        guard after.profile.id == before.profile.id else { throw OnlineError.wrongAccount }
        guard after.subscriptionActive else { throw OnlineError.subscriptionRequired }
        try Task.checkCancellation()
        let batch = ImportBatch(profile: after.profile, observations: observations, potentialPoints: history,
            charts: ChartMetadataMerge.merge(charts, catalog: try archive.chartCatalog()), importedAt: Date(), kind: .full)
        guard try JSONEncoder().encode(batch).count <= 64 * 1024 * 1024 else { throw OnlineError.oversizedResponse }
        await progress(ImportProgress(stage: .saving, completedPages: completed))
        let archive = self.archive
        return try await client.sessions.withValidSession(role: .main, expectedRevision: revision) {
            try Task.checkCancellation()
            return try archive.apply(batch: batch)
        }
    }

    private func pause() async throws {
        try Task.checkCancellation()
        if requestInterval > 0 { try await Task.sleep(for: .seconds(requestInterval)) }
        try Task.checkCancellation()
    }
}
