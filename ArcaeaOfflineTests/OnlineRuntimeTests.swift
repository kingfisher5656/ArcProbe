import ArcaeaCore
import Foundation
import XCTest
@testable import ArcaeaOffline

actor RuntimeTestSessions: SessionStore {
    var records: [AccountRole: AccountSession] = [:]
    func load(role: AccountRole) -> AccountSession? { records[role] }
    func save(_ session: AccountSession, role: AccountRole) { records[role] = session }
    func clear(role: AccountRole) { records[role] = nil }
    func compareAndSave(_ session: AccountSession, role: AccountRole, expectedRevision: UUID?) -> Bool {
        guard records[role]?.revision == expectedRevision else { return false }
        records[role] = session; return true
    }
    func withValidSession<T: Sendable>(role: AccountRole, expectedRevision: UUID, operation: @Sendable () throws -> T) throws -> T {
        guard records[role]?.revision == expectedRevision else { throw OnlineError.cancelled }
        return try operation()
    }
}
actor RuntimeTestTransport: HTTPTransport {
    private(set) var requestedHosts: [String] = []
    var responses: [HTTPResponse]
    init(_ responses: [HTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) throws -> HTTPResponse {
        requestedHosts.append(request.url?.host ?? "")
        guard !responses.isEmpty else { throw OnlineError.network }
        return responses.removeFirst()
    }
}
@MainActor final class OnlineRuntimeTests: XCTestCase {
    func testOwnAccountConfigurationAndDisconnectKeepArchivedData() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = try ArchiveStore(url: folder.appendingPathComponent("archive.sqlite"))
        let sessions = RuntimeTestSessions()
        let response = HTTPResponse(status: 200, headers: ["Content-Type": "application/json", "Set-Cookie": "session=test-only; Path=/; Secure"], body: Data(#"{"value":{"user_id":7,"recent_score":[]}}"#.utf8))
        let runtime = try OnlineRuntime(store: archive, directory: folder, sessions: sessions, transport: RuntimeTestTransport([response, response]))
        try await runtime.configureRecent(email: "test@example.invalid", password: "synthetic", mode: .ownAccountTesting)
        XCTAssertEqual(runtime.recentConfiguration?.target, AccountID("online:7"))
        let values = ScoreValues(score: 9800000)
        let play = ScoreObservation(id: ObservationID("manual-example"), accountID: AccountID("online:7"), chartID: ChartID(songID: "test", difficulty: .future), source: .manual, values: values, firstSeenAt: Date(), identityConfidence: .manual)
        _ = try archive.apply(batch: ImportBatch(profile: AccountProfile(id: play.accountID), observations: [play], kind: .manual))
        try await runtime.disconnect(role: .burner)
        XCTAssertNil(runtime.recentConfiguration)
        XCTAssertEqual(try archive.sourceObservations(accountID: play.accountID).count, 1)
        let persisted = await sessions.load(role: .burner)
        XCTAssertNil(persisted)
    }
    func testRecentFetchUsesOnlyArcaeaRequests() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = try ArchiveStore(url: folder.appendingPathComponent("archive.sqlite"))
        let sessions = RuntimeTestSessions()
        let response = HTTPResponse(status: 200, headers: ["Content-Type": "application/json", "Set-Cookie": "session=test-only; Path=/; Secure"], body: Data(#"{"value":{"user_id":7,"recent_score":[]}}"#.utf8))
        let transport = RuntimeTestTransport([response, response, response, response])
        let runtime = try OnlineRuntime(store: archive, directory: folder, sessions: sessions, transport: transport)
        try await runtime.configureRecent(email: "test@example.invalid", password: "synthetic", mode: .ownAccountTesting)
        let first = await runtime.fetchRecent()
        XCTAssertEqual(first.status, .unchanged)
        // A manual check is not held to the polling interval.
        let second = await runtime.fetchRecent()
        XCTAssertEqual(second.status, .unchanged)
        let hosts = await transport.requestedHosts
        XCTAssertFalse(hosts.isEmpty)
        XCTAssertTrue(hosts.allSatisfy { $0 == "webapi.lowiro.com" })
    }
    func testTemporaryGoogleRefreshFailuresDoNotBecomeAuthorizationFailures() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let wrapped = NSError(domain: "wrapper", code: 0, userInfo: [NSUnderlyingErrorKey: offline])
        XCTAssertEqual(GoogleProbeAuth.refreshError(wrapped), .temporaryRefresh)
        XCTAssertEqual(GoogleProbeAuth.refreshError(NSError(domain: "org.openid.appauth.remote-http", code: 503)), .temporaryRefresh)
        XCTAssertEqual(GoogleProbeAuth.refreshError(NSError(domain: "org.openid.appauth.oauth_token", code: -1)), .authorization)
    }
    func testKeychainRolesRoundTripAndClearOneRole() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = try KeychainSessionStore(directory: folder, service: "ArcaeaOffline.tests." + UUID().uuidString)
        let main = AccountSession(boundAccount: AccountID("online:1"))
        let recent = AccountSession(boundAccount: AccountID("online:2"))
        try await sessions.save(main, role: .main)
        try await sessions.save(recent, role: .burner)
        try await sessions.clear(role: .main)
        let mainLoaded = try await sessions.load(role: .main)
        let recentLoaded = try await sessions.load(role: .burner)
        XCTAssertNil(mainLoaded)
        XCTAssertEqual(recentLoaded?.boundAccount, AccountID("online:2"))
        try await sessions.clear(role: .burner)
    }
}

@MainActor final class RecentConfigurationFailureTests: XCTestCase {
    func testRejectedReplacementStopsOldConfigurationWithoutErasingArchive() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = try ArchiveStore(url: folder.appendingPathComponent("archive.sqlite"))
        let sessions = RuntimeTestSessions()
        let old = RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting)
        await sessions.save(AccountSession(boundAccount: old.observer, recentConfiguration: old), role: .burner)
        let rejected = HTTPResponse(status: 403, headers: ["Content-Type": "application/json"], body: Data(#"{"error_code":1010}"#.utf8))
        let runtime = try OnlineRuntime(store: archive, directory: folder, sessions: sessions, transport: RuntimeTestTransport([rejected]))
        _ = try await runtime.startTracking()
        do { try await runtime.configureRecent(email: "synthetic@example.invalid", password: "synthetic", mode: .ownAccountTesting); XCTFail("Challenge must stop") }
        catch { XCTAssertEqual(error as? OnlineError, .interactionRequired) }
        let session = await sessions.load(role: .burner)
        XCTAssertTrue(session?.requiresAttention ?? false)
        XCTAssertNil(session?.recentConfiguration)
        XCTAssertFalse(try runtime.status().isActive)
        XCTAssertNil(runtime.recentConfiguration)
    }
}
