import ArcaeaCore
import Foundation
import Observation
import WebKit

@MainActor @Observable final class OnlineRuntime {
    private(set) var mainProfile: AccountProfile?
    private(set) var recentProfile: AccountProfile?
    private(set) var recentConfiguration: RecentConfiguration?
    private(set) var trackingStatus: TrackingStatus?
    private(set) var progress = ""
    private(set) var isImporting = false
    var lastError: String?
    private let archive: ArchiveStore
    private let sessions: any SessionStore
    private let client: ArcaeaWebClient
    private let tracking: TrackingStore
    private let importer: MainImportService
    private let recent: RecentSyncService
    private let browser = OfficialLoginBridge()
    private var importTask: Task<ImportReceipt, Error>?
    private static var cached: OnlineRuntime?

    init(store: ArchiveStore, directory: URL, sessions: (any SessionStore)? = nil, transport: any HTTPTransport = URLSessionTransport()) throws {
        archive = store
        let secure: any SessionStore
        if let sessions { secure = sessions } else { secure = try KeychainSessionStore(directory: directory) }
        self.sessions = secure
        client = ArcaeaWebClient(transport: transport, sessions: secure)
        tracking = try TrackingStore(url: directory.appendingPathComponent("tracking.sqlite"))
        importer = MainImportService(client: client, archive: store)
        recent = RecentSyncService(client: client, archive: store, tracking: tracking)
        trackingStatus = try tracking.status()
    }

    static func shared() throws -> OnlineRuntime {
        if let cached { return cached }
        let directory = try ArchiveLocation.directory()
        let runtime = try OnlineRuntime(store: ArchiveStore(url: ArchiveLocation.url(), catalog: ChartCatalog.bundled()), directory: directory)
        cached = runtime
        return runtime
    }

    func refreshStatus() async {
        do {
            let profiles = try archive.profiles()
            let main = try await sessions.load(role: .main)
            let burner = try await sessions.load(role: .burner)
            if let id = main?.boundAccount {
                mainProfile = profiles.first { $0.id == id } ?? (mainProfile?.id == id ? mainProfile : AccountProfile(id: id))
            } else { mainProfile = nil }
            if let id = burner?.boundAccount {
                recentProfile = profiles.first { $0.id == id } ?? (recentProfile?.id == id ? recentProfile : AccountProfile(id: id))
            } else { recentProfile = nil }
            recentConfiguration = burner?.recentConfiguration
            trackingStatus = try tracking.status()
        } catch { lastError = safeMessage(error) }
    }

    func loginWebView(role: AccountRole) -> WKWebView { browser.webView(role: role) }

    @discardableResult func captureLogin(role: AccountRole) async throws -> AccountProfile {
        if role == .main { cancelImport() }
        else { try tracking.bind(configuration: nil); recentConfiguration = nil; trackingStatus = try tracking.status() }
        let previous = try await sessions.load(role: role)
        var replacement = try await browser.capture(role: role)
        replacement.serverCooldownUntil = previous?.serverCooldownUntil
        replacement.nextImportEligibleAt = previous?.nextImportEligibleAt
        guard try await sessions.compareAndSave(replacement, role: role, expectedRevision: previous?.revision) else { throw OnlineError.cancelled }
        do {
            let account = try await client.readAccount(role: role, expectedRevision: replacement.revision)
            try await client.bind(role: role, account: account.profile.id, expectedRevision: replacement.revision)
            if role == .main { mainProfile = account.profile }
            else { recentProfile = account.profile; recentConfiguration = nil; try tracking.bind(configuration: nil) }
            lastError = nil
            return account.profile
        } catch { lastError = safeMessage(error); throw error }
    }

    func disconnect(role: AccountRole) async throws {
        if role == .main { cancelImport() }
        try await sessions.clear(role: role)
        await browser.clear(role: role)
        if role == .main { mainProfile = nil }
        else { recentProfile = nil; recentConfiguration = nil; try tracking.bind(configuration: nil) }
        trackingStatus = try tracking.status()
        lastError = nil
    }

    @discardableResult func fullImport() async throws -> ImportReceipt {
        guard !isImporting else { throw TrackingError.alreadyFetching }
        await refreshStatus()
        guard let account = mainProfile?.id else { throw OnlineError.expiredSession }
        isImporting = true; progress = "Checking account"; lastError = nil
        let task = Task { [importer] in
            try await importer.sync(expectedAccount: account) { update in
                await self.showProgress(update)
            }
        }
        importTask = task
        defer { importTask = nil; isImporting = false }
        do {
            let receipt = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            progress = "Imported \(receipt.addedCount) new plays and \(receipt.addedPotentialCount) potential observations"
            await refreshStatus()
            return receipt
        } catch { lastError = safeMessage(error); progress = "Import stopped; saved data retained"; throw error }
    }

    func cancelImport() { importTask?.cancel() }

    func configureRecent(email: String, password: String, target: AccountID? = nil, mode: RecentSourceMode) async throws {
        lastError = nil
        var attemptedRevision: UUID?
        do {
            try tracking.bind(configuration: nil)
            recentConfiguration = nil; trackingStatus = try tracking.status()
            let before = try await sessions.load(role: .burner)
            let revision = UUID()
            attemptedRevision = revision
            let account = try await client.login(role: .burner, credentials: LoginCredentials(email: email, password: password), replacementRevision: revision, expectation: .revision(before?.revision))
            try await finishConfiguration(account: account, target: target, mode: mode, expectedRevision: revision)
        } catch {
            if let revision = attemptedRevision, let failure = error as? OnlineError, [.credentialsRejected, .interactionRequired, .wrongAccount, .unsupportedResponse].contains(failure),
               var current = try? await sessions.load(role: .burner), current.revision == revision {
                current.requiresAttention = true
                _ = try? await sessions.compareAndSave(current, role: .burner, expectedRevision: revision)
            }
            await refreshStatus(); lastError = safeMessage(error); throw error
        }
    }

    func configureRecentFromBrowser(mode: RecentSourceMode, target: AccountID? = nil) async throws {
        do {
            guard let session = try await sessions.load(role: .burner), let observer = session.boundAccount else { throw OnlineError.expiredSession }
            let account = try await client.readAccount(role: .burner, expected: observer, expectedRevision: session.revision)
            try await finishConfiguration(account: account, target: target, mode: mode, expectedRevision: session.revision)
        } catch { lastError = safeMessage(error); throw error }
    }

    private func finishConfiguration(account: RemoteAccount, target: AccountID?, mode: RecentSourceMode, expectedRevision: UUID) async throws {
        let targetID: AccountID
        if mode == .ownAccountTesting { targetID = account.profile.id }
        else {
            if let explicit = target { targetID = explicit }
            else if let main = try await sessions.load(role: .main)?.boundAccount { targetID = main }
            else { throw OnlineError.targetNotFound }
        }
        let configuration = RecentConfiguration(observer: account.profile.id, target: targetID, mode: mode)
        if mode == .friendAccount { _ = try await client.recent(configuration: configuration, expectedRevision: expectedRevision) }
        guard let existing = try await sessions.load(role: .burner), existing.boundAccount == account.profile.id, existing.revision == expectedRevision else { throw OnlineError.cancelled }
        let configured = AccountSession(cookies: existing.cookies, boundAccount: account.profile.id, credentials: existing.credentials,
            recentConfiguration: configuration, browserUserAgent: existing.browserUserAgent, serverCooldownUntil: existing.serverCooldownUntil,
            nextImportEligibleAt: existing.nextImportEligibleAt)
        guard try await sessions.compareAndSave(configured, role: .burner, expectedRevision: existing.revision) else { throw OnlineError.cancelled }
        try tracking.bind(configuration: configuration)
        recentProfile = account.profile; recentConfiguration = configuration; trackingStatus = try tracking.status(); lastError = nil
    }

    func fetchRecent(generation: UUID? = nil, finalFetch: Bool = false) async -> FetchResult {
        let result = await recent.fetch(generation: generation, finalFetch: finalFetch)
        await refreshStatus()
        return result
    }
    @discardableResult func startTracking() throws -> UUID {
        let generation = try tracking.start(); trackingStatus = try tracking.status(); return generation
    }
    func setMinimumIntervalEnabled(_ enabled: Bool) throws {
        try tracking.setMinimumIntervalEnabled(enabled)
        trackingStatus = try tracking.status()
    }

    func stopTracking() throws { try tracking.stop(); trackingStatus = try tracking.status() }
    func status() throws -> TrackingStatus { try tracking.status() }

    private func showProgress(_ update: ImportProgress) {
        switch update.stage {
        case .checkingAccount: progress = "Checking account"
        case .readingScores: progress = "Reading \(update.difficulty?.label ?? "scores") · page \(update.page ?? 1)"
        case .readingHistory: progress = "Reading five-year potential observations"
        case .verifyingAccount: progress = "Verifying account and subscription"
        case .saving: progress = "Saving complete import"
        }
    }
    private func safeMessage(_ error: Error) -> String {
        if let error = error as? OnlineError { return error.localizedDescription }
        if error is CancellationError { return "The operation was cancelled." }
        if error is TrackingError { return "Tracking is busy, stopped, or waiting until the next permitted request." }
        if error is ArchiveError { return "The received data could not be saved. Your previous archive is retained." }
        return "The operation could not finish. Your saved archive is retained."
    }
}
