import Foundation
import XCTest
@testable import ArcaeaCore

@MainActor final class RecentSyncTests: XCTestCase {
    let accountJSON = #"{"value":{"user_id":7,"name":"Example","arcaea_online_expire_ts":0,"recent_score":[{"song_id":"test","difficulty":2,"score":9800000,"time_played":1700000000123,"title":{"en":"Test title"}}]}}"#
    func makeService(_ responses: [HTTPResponse], credentials: Bool = true, cookies: Bool = true) async throws -> (RecentSyncService, ScriptedTransport, ArchiveStore, TrackingStore, TestSessionStore) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = try ArchiveStore(url: folder.appendingPathComponent("archive.sqlite"))
        let tracking = try TrackingStore(url: folder.appendingPathComponent("tracking.sqlite"))
        let sessions = TestSessionStore()
        let config = RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting)
        await sessions.save(AccountSession(cookies: cookies ? testJar() : CookieJar(), boundAccount: config.observer, credentials: credentials ? LoginCredentials(email: "synthetic@example.invalid", password: "synthetic") : nil, recentConfiguration: config), role: .burner)
        let transport = ScriptedTransport(responses)
        let service = RecentSyncService(client: ArcaeaWebClient(transport: transport, sessions: sessions), archive: archive, tracking: tracking)
        return (service, transport, archive, tracking, sessions)
    }

    func testHealthyOwnRecentUsesOneReadNoLoginAndDuplicatePollsDeduplicate() async throws {
        let (service, transport, archive, _, _) = try await makeService([jsonResponse(accountJSON), jsonResponse(accountJSON)])
        let now = Date(timeIntervalSince1970: 1_700_000_010)
        let first = await service.fetch(generation: nil, now: now)
        let second = await service.fetch(generation: nil, now: now.addingTimeInterval(70))
        XCTAssertEqual(first.status, .success)
        XCTAssertEqual(second.status, .unchanged)
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 1)
        XCTAssertEqual(try archive.chartCatalog()[ChartID(songID: "test", difficulty: .future)]?.title, "Test title")
        let paths = await transport.paths()
        XCTAssertEqual(paths, ["/webapi/user/me", "/webapi/user/me"])
    }

    func testClosingCatchUpWaitsForCooldownThenImportsDelayedLastPlay() async throws {
        let delayed = accountJSON.replacingOccurrences(of: "9800000", with: "9900000")
            .replacingOccurrences(of: "1700000000123", with: "1700000040123")
        let (service, _, archive, tracking, _) = try await makeService([
            jsonResponse(accountJSON), jsonResponse(accountJSON), jsonResponse(delayed)
        ])
        let now = Date(timeIntervalSince1970: 1_700_000_010)
        let generation = try tracking.start()
        _ = await service.fetch(generation: generation, now: now)
        try tracking.stop()
        let early = await service.fetch(generation: generation, now: now.addingTimeInterval(10), finalFetch: true)
        XCTAssertEqual(early.status, .cooldown)
        let first = await service.fetch(generation: generation, now: now.addingTimeInterval(65), finalFetch: true)
        XCTAssertEqual(first.status, .unchanged)
        let last = await service.fetch(generation: generation, now: now.addingTimeInterval(130), finalFetch: true)
        XCTAssertEqual(last.status, .success)
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 2)
        XCTAssertFalse(try tracking.status().isActive)
    }

    func testFinalFetchPreservesServerBackoffAndRejectsActiveOrMissingGeneration() async throws {
        let (service, _, _, tracking, _) = try await makeService([jsonResponse("{}", status: 429, headers: ["Retry-After": "180"])])
        let now = Date(timeIntervalSince1970: 1_700_000_010)
        let generation = try tracking.start()
        let active = await service.fetch(generation: generation, now: now, finalFetch: true)
        XCTAssertEqual(active.status, .staleGeneration)
        try tracking.stop()
        let missing = await service.fetch(now: now, finalFetch: true)
        XCTAssertEqual(missing.status, .staleGeneration)
        let limited = await service.fetch(generation: generation, now: now, finalFetch: true)
        XCTAssertEqual(limited.status, .rateLimited)
        let retry = await service.fetch(generation: generation, now: now.addingTimeInterval(65), finalFetch: true)
        XCTAssertEqual(retry.status, .cooldown)
        XCTAssertEqual(retry.nextEligibleAt, now.addingTimeInterval(180))
        _ = try tracking.start()
        let stale = await service.fetch(generation: generation, now: now.addingTimeInterval(200), finalFetch: true)
        XCTAssertEqual(stale.status, .staleGeneration)
    }

    func testExpiredSessionRefreshesOnceAndRetryNeverRefreshesAgain() async throws {
        let (service, transport, archive, _, _) = try await makeService([
            jsonResponse("{}", status: 401), jsonResponse(#"{"value":{}}"#), jsonResponse(accountJSON), jsonResponse("{}", status: 401)
        ])
        let result = await service.fetch(generation: nil)
        XCTAssertEqual(result.status, .authenticationRequired)
        let paths = await transport.paths()
        XCTAssertEqual(paths.filter { $0 == "/auth/login" }.count, 1)
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 0)
    }

    func testJSONChallengeLatchesAttentionAnd429PersistsCooldown() async throws {
        let (challenge, transport, _, _, _) = try await makeService([jsonResponse(#"{"error_code":1010}"#, status: 403)])
        let firstChallenge = await challenge.fetch(generation: nil)
        XCTAssertEqual(firstChallenge.status, .attentionRequired)
        let secondChallenge = await challenge.fetch(generation: nil, now: Date().addingTimeInterval(70))
        XCTAssertEqual(secondChallenge.status, .attentionRequired)
        let paths = await transport.paths()
        XCTAssertEqual(paths, ["/webapi/user/me"])
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let (limited, _, _, tracking, _) = try await makeService([jsonResponse("{}", status: 429, headers: ["Retry-After": "180"])])
        let result = await limited.fetch(generation: nil, now: now)
        XCTAssertEqual(result.status, .rateLimited)
        XCTAssertEqual(try tracking.status().nextEligibleAt, now.addingTimeInterval(180))
    }
}

actor CancellableTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        try await Task.sleep(for: .seconds(60))
        throw OnlineError.network
    }
}

@MainActor final class RecentSyncLifecycleTests: XCTestCase {
    func session() -> AccountSession {
        AccountSession(cookies: testJar(), boundAccount: AccountID("online:7"), credentials: LoginCredentials(email: "synthetic@example.invalid", password: "synthetic"), recentConfiguration: RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting))
    }
    func make(transport: any HTTPTransport, deadline: TimeInterval = 20) async throws -> (RecentSyncService, TestSessionStore, ArchiveStore, TrackingStore) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = try ArchiveStore(url: folder.appendingPathComponent("archive.sqlite"))
        let tracking = try TrackingStore(url: folder.appendingPathComponent("tracking.sqlite"))
        let sessions = TestSessionStore()
        await sessions.save(session(), role: .burner)
        return (RecentSyncService(client: ArcaeaWebClient(transport: transport, sessions: sessions), archive: archive, tracking: tracking, deadline: deadline), sessions, archive, tracking)
    }
    func testStoppedGenerationDoesNotCommitFetchedPlay() async throws {
        let transport = SuspendedTransport()
        let (service, _, archive, tracking) = try await make(transport: transport)
        let generation = try tracking.start()
        let task = Task { await service.fetch(generation: generation) }
        await transport.waitForRequest()
        try tracking.stop()
        await transport.resume(jsonResponse(#"{"value":{"user_id":7,"recent_score":[{"song_id":"test","difficulty":2,"score":9800000}]}}"#))
        let result = await task.value
        XCTAssertEqual(result.status, .trackingStopped)
        XCTAssertTrue(try archive.sourceObservations(accountID: AccountID("online:7")).isEmpty)
    }
    func testReopenDuringFinalFetchRejectsOldCommit() async throws {
        let transport = SuspendedTransport()
        let (service, _, archive, tracking) = try await make(transport: transport)
        let generation = try tracking.start()
        try tracking.stop()
        let task = Task { await service.fetch(generation: generation, finalFetch: true) }
        await transport.waitForRequest()
        let replacement = try tracking.start()
        await transport.resume(jsonResponse(#"{"value":{"user_id":7,"recent_score":[{"song_id":"test","difficulty":2,"score":9900000}]}}"#))
        let result = await task.value
        XCTAssertEqual(result.status, .staleGeneration)
        XCTAssertTrue(try archive.sourceObservations(accountID: AccountID("online:7")).isEmpty)
        XCTAssertEqual(try tracking.status().generation, replacement)
        XCTAssertTrue(try tracking.status().isActive)
    }

    func testOldChallengeCannotLatchReplacementRole() async throws {
        let transport = SuspendedTransport()
        let (service, sessions, _, _) = try await make(transport: transport)
        let task = Task { await service.fetch() }
        await transport.waitForRequest()
        let replacement = AccountSession(cookies: testJar(), boundAccount: AccountID("online:8"))
        await sessions.save(replacement, role: .burner)
        await transport.resume(jsonResponse(#"{"error_code":1010}"#, status: 403))
        let result = await task.value
        XCTAssertEqual(result.status, .cancelled)
        let current = await sessions.load(role: .burner)
        XCTAssertEqual(current?.revision, replacement.revision)
        XCTAssertFalse(current?.requiresAttention ?? true)
    }
    func testDeadlineCancelsRequestAndPreservesArchive() async throws {
        let (service, _, archive, tracking) = try await make(transport: CancellableTransport(), deadline: 0.05)
        let result = await service.fetch()
        XCTAssertEqual(result.status, .deadlineExceeded)
        XCTAssertTrue(try archive.profiles().isEmpty)
        XCTAssertNotNil(try tracking.status().nextEligibleAt)
    }
    func testFriendModeUsesRecentCookiesAndFiltersTargetWithoutSubscription() async throws {
        let responses = [jsonResponse(#"{"value":{"user_id":8,"arcaea_online_expire_ts":0}}"#), jsonResponse(#"{"value":{"friends":[{"user_id":9,"recent_score":[{"song_id":"other","difficulty":2,"score":9900000}]},{"user_id":7,"recent_score":[{"song_id":"target","difficulty":2,"score":9700000}]}]}}"#)]
        let transport = ScriptedTransport(responses)
        let (service, sessions, archive, _) = try await make(transport: transport)
        await sessions.save(AccountSession(cookies: testJar(), boundAccount: AccountID("online:8"), recentConfiguration: RecentConfiguration(observer: AccountID("online:8"), target: AccountID("online:7"), mode: .friendAccount)), role: .burner)
        await sessions.save(AccountSession(boundAccount: AccountID("online:7")), role: .main)
        let result = await service.fetch()
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).first?.chartID.songID, "target")
        XCTAssertTrue(try archive.sourceObservations(accountID: AccountID("online:9")).isEmpty)
        let requests = await transport.recorded()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/webapi/user/me", "/webapi/friend/me"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == "session=synthetic" })
    }
}
