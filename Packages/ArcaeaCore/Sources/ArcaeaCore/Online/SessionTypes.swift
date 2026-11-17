import Foundation

public enum OnlineError: Error, Equatable, Sendable {
    case expiredSession, credentialsRejected, interactionRequired, subscriptionRequired
    case wrongAccount, targetNotFound, unsupportedResponse, oversizedResponse, forbiddenURL
    case rateLimited(until: Date), network, locked, cancelled, deadlineExceeded
}

extension OnlineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .expiredSession: localized("Sign in to this account again.")
        case .credentialsRejected: localized("The recent account credentials were rejected. Reconfigure the account.")
        case .interactionRequired: localized("Open the official login in the app to finish account verification.")
        case .subscriptionRequired: localized("The main account needs an active Arcaea Online subscription for full import.")
        case .wrongAccount: localized("The signed-in account differs from the connected account.")
        case .targetNotFound: localized("The selected account was not found in this account's friends list.")
        case .unsupportedResponse: localized("The website returned an unsupported response. Saved data is unchanged.")
        case .oversizedResponse: localized("The website response exceeded the safe collection limit.")
        case .forbiddenURL: localized("The request left the allowed official route.")
        case .rateLimited: localized("The server asked us to wait before another request.")
        case .network: localized("The website could not be reached. Saved data is unchanged.")
        case .locked: localized("Unlock the device once to make this account available.")
        case .cancelled: localized("The request was cancelled.")
        case .deadlineExceeded: localized("The recent request reached its time limit. Try again later.")
        }
    }
}

public struct LoginCredentials: Codable, Sendable {
    public let email: String
    public let password: String
    public init(email: String, password: String) { self.email = email; self.password = password }
}

public enum RecentSourceMode: String, CaseIterable, Codable, Sendable {
    case ownAccountTesting, friendAccount
}

public struct RecentConfiguration: Codable, Sendable {
    public let observer: AccountID
    public let target: AccountID
    public let mode: RecentSourceMode
    public init(observer: AccountID, target: AccountID, mode: RecentSourceMode) {
        self.observer = observer; self.target = target; self.mode = mode
    }
}

/// Contains secrets. It belongs only in an isolated secure SessionStore, never the archive or exports.
public struct AccountSession: Codable, Sendable {
    public let revision: UUID
    public var cookies: CookieJar
    public var boundAccount: AccountID?
    public var credentials: LoginCredentials?
    public var recentConfiguration: RecentConfiguration?
    public var requiresAttention: Bool
    public var browserUserAgent: String?
    public var serverCooldownUntil: Date?
    public var nextImportEligibleAt: Date?
    public init(revision: UUID = UUID(), cookies: CookieJar = CookieJar(), boundAccount: AccountID? = nil,
                credentials: LoginCredentials? = nil, recentConfiguration: RecentConfiguration? = nil,
                requiresAttention: Bool = false, browserUserAgent: String? = nil, serverCooldownUntil: Date? = nil, nextImportEligibleAt: Date? = nil) {
        self.revision = revision; self.cookies = cookies; self.boundAccount = boundAccount; self.credentials = credentials
        self.recentConfiguration = recentConfiguration; self.requiresAttention = requiresAttention; self.browserUserAgent = browserUserAgent; self.serverCooldownUntil = serverCooldownUntil; self.nextImportEligibleAt = nextImportEligibleAt
    }
}

public protocol SessionStore: Sendable {
    func load(role: AccountRole) async throws -> AccountSession?
    func save(_ session: AccountSession, role: AccountRole) async throws
    func clear(role: AccountRole) async throws
    /// Atomically rejects an in-flight operation after disconnect or role replacement.
    func withValidSession<T: Sendable>(role: AccountRole, expectedRevision: UUID, operation: @Sendable () throws -> T) async throws -> T
    func compareAndSave(_ session: AccountSession, role: AccountRole, expectedRevision: UUID?) async throws -> Bool
}

public struct RemoteAccount: Sendable {
    public let profile: AccountProfile
    public let subscriptionRemainingMilliseconds: Int64?
    public let recentScores: [ScoreObservation]
    public let recentCharts: [ChartMetadata]
    public var subscriptionActive: Bool { (subscriptionRemainingMilliseconds ?? 0) > 0 }
}

public struct ScorePage: Sendable {
    public let count: Int
    public let observations: [ScoreObservation]
    public let charts: [ChartMetadata]
}

public struct RecentPayload: Sendable {
    public let profile: AccountProfile
    public let observations: [ScoreObservation]
    public let charts: [ChartMetadata]
    public init(profile: AccountProfile, observations: [ScoreObservation], charts: [ChartMetadata] = []) {
        self.profile = profile; self.observations = observations; self.charts = charts
    }
}

public enum SessionExpectation: Sendable { case any, revision(UUID?) }
