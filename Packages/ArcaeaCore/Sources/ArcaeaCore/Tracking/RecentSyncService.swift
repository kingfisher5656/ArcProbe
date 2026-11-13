import Foundation

/// Reads the tracked account's most recent play and saves it, one bounded request at a time.
public actor RecentSyncService {
    private let client: ArcaeaWebClient
    private let archive: ArchiveStore
    private let tracking: TrackingStore
    private let deadline: TimeInterval
    public init(client: ArcaeaWebClient, archive: ArchiveStore, tracking: TrackingStore, deadline: TimeInterval = 20) {
        self.client = client; self.archive = archive; self.tracking = tracking; self.deadline = min(20, max(0.01, deadline))
    }

    /// One step of the Shortcut loop: fetch when due, then say how long to wait or that the loop is over.
    /// Whatever was fetched is saved even if this loop has meanwhile been superseded.
    public func poll(session: UUID, now: Date = Date()) async -> PollDecision {
        do {
            let decision = try tracking.beginPoll(session: session, now: now)
            guard decision == .fetch else { return decision }
            let started = Date()
            let result = await fetch(now: now)
            return try tracking.completePoll(session: session, status: result.status, now: now.addingTimeInterval(Date().timeIntervalSince(started)))
        } catch {
            // The state database is briefly unavailable; keep the loop alive and try again shortly.
            return .wait(seconds: 30)
        }
    }

    public func fetch(now: Date = Date()) async -> FetchResult {
        var lease: FetchLease?
        do {
            try Task.checkCancellation()
            guard let session = try await client.sessions.load(role: .burner), let configuration = session.recentConfiguration else {
                return result(.authenticationRequired)
            }
            if session.requiresAttention { return result(.attentionRequired) }
            let acquired = try tracking.acquire(now: now, deadline: deadline)
            lease = acquired
            let start = Date()
            let collected = try await withDeadline { try await self.collect(session: session, configuration: configuration, now: now) }
            try Task.checkCancellation()
            let completedAt = now.addingTimeInterval(Date().timeIntervalSince(start))
            let payload = collected.payload
            let batch = ImportBatch(profile: payload.profile, observations: payload.observations,
                charts: ChartMetadataMerge.merge(payload.charts, catalog: try archive.chartCatalog()), importedAt: completedAt, kind: .recent)
            let latest = payload.observations.compactMap { $0.values.playedAt?.date }.max()
            let archive = self.archive, tracking = self.tracking
            let added = try await client.sessions.withValidSession(role: .burner, expectedRevision: collected.revision) {
                try tracking.commit(lease: acquired, now: completedAt, latestPlay: latest) { try archive.apply(batch: batch).addedCount }
            }
            return result(added > 0 ? .success : .unchanged, added: added)
        } catch {
            let failure = error as? OperationFailure
            let underlying = failure?.error ?? error
            var status = classify(underlying)
            var cooldown: Date?
            if case let OnlineError.rateLimited(until) = underlying { cooldown = until }
            if status.needsAttention {
                // A rejected sign-in or an expired session is definite. A single odd answer to a
                // normal read (gateway error page, brief challenge) is not: retry it a few times first.
                let definite = failure?.duringLogin == true || status == .authenticationRequired
                let earlier = (try? tracking.status().consecutiveFailures) ?? 0
                if definite || earlier + 1 >= TrackingPolicy.failuresBeforeAttention {
                    if let lease { try? tracking.finish(lease: lease, status: status, now: now) }
                    if let revision = failure?.revision { await latchAttention(expectedRevision: revision) }
                } else {
                    status = .failed
                    if let lease { try? tracking.finish(lease: lease, status: status, now: now) }
                }
            } else if let lease {
                try? tracking.finish(lease: lease, status: status, now: now, cooldownUntil: cooldown)
            }
            return result(status)
        }
    }

    private struct Collected: Sendable { let payload: RecentPayload; let revision: UUID }
    private struct OperationFailure: Error { let error: Error; let revision: UUID; let duringLogin: Bool }
    private func collect(session: AccountSession, configuration: RecentConfiguration, now: Date) async throws -> Collected {
        var revision = session.revision
        var loggingIn = false
        do {
            var refreshed = false
            if !session.cookies.hasUsableCookies(now: now) {
                guard let credentials = session.credentials else { throw OnlineError.expiredSession }
                revision = UUID(); loggingIn = true
                try await renew(credentials, session: session, configuration: configuration, now: now, revision: revision)
                loggingIn = false; refreshed = true
            }
            do {
                return Collected(payload: try await client.recent(configuration: configuration, now: now, expectedRevision: revision), revision: revision)
            } catch OnlineError.expiredSession where !refreshed {
                // Without a saved password the session keeps its revision, so the caller can mark it.
                guard let credentials = session.credentials else { throw OnlineError.expiredSession }
                revision = UUID(); loggingIn = true
                try await renew(credentials, session: session, configuration: configuration, now: now, revision: revision)
                loggingIn = false
                return Collected(payload: try await client.recent(configuration: configuration, now: now, expectedRevision: revision), revision: revision)
            }
        } catch { throw OperationFailure(error: error, revision: revision, duringLogin: loggingIn) }
    }

    /// One sign-in with the saved password. Never repeated within a request.
    private func renew(_ credentials: LoginCredentials, session: AccountSession, configuration: RecentConfiguration, now: Date, revision: UUID) async throws {
        _ = try await client.login(role: .burner, credentials: credentials, expected: configuration.observer, now: now, replacementRevision: revision, expectation: .revision(session.revision), reuseRoleCookies: true)
    }

    private func withDeadline<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask { [deadline] in
                try await Task.sleep(for: .seconds(deadline))
                throw OnlineError.deadlineExceeded
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw OnlineError.deadlineExceeded }
            return result
        }
    }

    private func latchAttention(expectedRevision: UUID) async {
        guard var session = try? await client.sessions.load(role: .burner), session.revision == expectedRevision else { return }
        session.requiresAttention = true
        _ = try? await client.sessions.compareAndSave(session, role: .burner, expectedRevision: session.revision)
    }

    private func result(_ status: FetchStatus, added: Int = 0) -> FetchResult {
        let state = try? tracking.status()
        return FetchResult(status: status, addedCount: added, lastPlayAt: state?.lastPlayAt,
                           lastSuccessAt: state?.lastSuccessAt, nextEligibleAt: state?.cooldownUntil)
    }

    private func classify(_ error: Error) -> FetchStatus {
        switch error {
        case TrackingError.alreadyFetching: .alreadyFetching
        case TrackingError.cooldown: .cooldown
        case TrackingError.expiredLease: .deadlineExceeded
        case OnlineError.expiredSession: .authenticationRequired
        case OnlineError.credentialsRejected, OnlineError.interactionRequired: .attentionRequired
        case OnlineError.wrongAccount, OnlineError.targetNotFound: .wrongAccount
        case OnlineError.unsupportedResponse, OnlineError.oversizedResponse, OnlineError.forbiddenURL: .unsupportedSchema
        case OnlineError.rateLimited: .rateLimited
        case OnlineError.network: .offline
        case OnlineError.locked: .locked
        case OnlineError.cancelled, is CancellationError: .cancelled
        case OnlineError.deadlineExceeded: .deadlineExceeded
        default: .failed
        }
    }
}
