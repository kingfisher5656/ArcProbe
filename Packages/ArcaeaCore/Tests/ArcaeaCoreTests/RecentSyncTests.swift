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
        let first = await service.fetch(now: now)
        let second = await service.fetch(now: now.addingTimeInterval(70))
        XCTAssertEqual(first.status, .success)
        XCTAssertEqual(second.status, .unchanged)
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 1)
        XCTAssertEqual(try archive.chartCatalog()[ChartID(songID: "test", difficulty: .future)]?.title, "Test title")
        let paths = await transport.paths()
        XCTAssertEqual(paths, ["/webapi/user/me", "/webapi/user/me"])
    }

    func testPollFetchesWhenDueThenWaitsAndDeduplicates() async throws {
        let newer = accountJSON.replacingOccurrences(of: "9800000", with: "9900000")
            .replacingOccurrences(of: "1700000000123", with: "1700000040123")
        let (service, transport, archive, tracking, _) = try await makeService([jsonResponse(accountJSON), jsonResponse(newer)])
        try tracking.bind(configuration: RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting))
        let now = Date(timeIntervalSince1970: 1_700_000_010)
        let session = try tracking.start(now: now)
        guard case .wait(let seconds) = await service.poll(session: session, now: now) else { return XCTFail("First poll fetches, then waits") }
        XCTAssertTrue((65...81).contains(seconds))
        // A duplicate or early call must not reach the server.
        let early = await service.poll(session: session, now: now.addingTimeInterval(10))
        guard case .wait(let remaining) = early else { return XCTFail("Early poll waits") }
        XCTAssertLessThanOrEqual(remaining, seconds - 9)
        var paths = await transport.paths()
        XCTAssertEqual(paths.count, 1)
        guard case .wait = await service.poll(session: session, now: now.addingTimeInterval(Double(seconds))) else { return XCTFail("Due poll fetches") }
        paths = await transport.paths()
        XCTAssertEqual(paths.count, 2)
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 2)
    }

    func testReopeningQuicklyKeepsScheduleAndRetiresOldLoop() async throws {
        let (service, transport, _, tracking, _) = try await makeService([jsonResponse(accountJSON), jsonResponse(accountJSON)])
        try tracking.bind(configuration: RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting))
        let now = Date(timeIntervalSince1970: 1_700_000_010)
        let first = try tracking.start(now: now)
        guard case .wait(let seconds) = await service.poll(session: first, now: now) else { return XCTFail("First poll fetches") }
        // Close and reopen three times within a few seconds.
        var latest = first
        for offset in [20.0, 24, 28] {
            try tracking.stop(now: now.addingTimeInterval(offset))
            latest = try tracking.start(now: now.addingTimeInterval(offset + 1))
            // Each new loop is told to wait for the schedule already running, not a fresh interval.
            guard case .wait(let remaining) = await service.poll(session: latest, now: now.addingTimeInterval(offset + 1)) else { return XCTFail("New loop waits") }
            XCTAssertEqual(remaining, seconds - Int(offset + 1))
        }
        let stale = await service.poll(session: first, now: now.addingTimeInterval(Double(seconds)))
        XCTAssertEqual(stale, .stop(.superseded))
        guard case .wait = await service.poll(session: latest, now: now.addingTimeInterval(Double(seconds))) else { return XCTFail("Newest loop fetches on schedule") }
        let paths = await transport.paths()
        XCTAssertEqual(paths.count, 2)
    }

    func testClosingRunsTwoChecksThenEndsLoopAndCatchesLatePlay() async throws {
        let delayed = accountJSON.replacingOccurrences(of: "9800000", with: "9900000")
            .replacingOccurrences(of: "1700000000123", with: "1700000040123")
        let (service, _, archive, tracking, _) = try await makeService([jsonResponse(accountJSON), jsonResponse(accountJSON), jsonResponse(delayed)])
        try tracking.bind(configuration: RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting))
        let now = Date(timeIntervalSince1970: 1_700_000_010)
        let session = try tracking.start(now: now)
        guard case .wait(let seconds) = await service.poll(session: session, now: now) else { return XCTFail("First poll fetches") }
        try tracking.stop(now: now.addingTimeInterval(30))
        // A repeated close event must not restart the countdown.
        try tracking.stop(now: now.addingTimeInterval(31))
        let firstClosing = now.addingTimeInterval(Double(seconds))
        guard case .wait(let closingWait) = await service.poll(session: session, now: firstClosing) else { return XCTFail("First closing check continues") }
        XCTAssertEqual(closingWait, Int(TrackingPolicy.closingInterval))
        let last = await service.poll(session: session, now: firstClosing.addingTimeInterval(Double(closingWait)))
        XCTAssertEqual(last, .stop(.finished))
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 2)
        let after = await service.poll(session: session, now: firstClosing.addingTimeInterval(200))
        XCTAssertEqual(after, .stop(.finished))
    }

    func testSupersededLoopStillSavesItsInFlightResult() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = try ArchiveStore(url: folder.appendingPathComponent("archive.sqlite"))
        let tracking = try TrackingStore(url: folder.appendingPathComponent("tracking.sqlite"))
        let sessions = TestSessionStore()
        let config = RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting)
        await sessions.save(AccountSession(cookies: testJar(), boundAccount: config.observer, recentConfiguration: config), role: .burner)
        try tracking.bind(configuration: config)
        let transport = SuspendedTransport()
        let service = RecentSyncService(client: ArcaeaWebClient(transport: transport, sessions: sessions), archive: archive, tracking: tracking)
        let old = try tracking.start()
        let task = Task { await service.poll(session: old) }
        await transport.waitForRequest()
        try tracking.stop()
        let replacement = try tracking.start()
        await transport.resume(jsonResponse(accountJSON))
        let decision = await task.value
        XCTAssertEqual(decision, .stop(.superseded))
        // The play is real regardless of which loop asked for it.
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 1)
        XCTAssertEqual(try tracking.status().session, replacement)
        XCTAssertTrue(try tracking.status().isActive)
    }

    func testRateLimitDelaysNextPollUntilServerAllows() async throws {
        let (service, _, _, tracking, _) = try await makeService([jsonResponse("{}", status: 429, headers: ["Retry-After": "180"])])
        try tracking.bind(configuration: RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting))
        let now = Date(timeIntervalSince1970: 1_700_000_010)
        let session = try tracking.start(now: now)
        let decision = await service.poll(session: session, now: now)
        XCTAssertEqual(decision, .wait(seconds: 180))
        let manual = await service.fetch(now: now.addingTimeInterval(65))
        XCTAssertEqual(manual.status, .cooldown)
        XCTAssertEqual(manual.nextEligibleAt, now.addingTimeInterval(180))
    }

    func testExpiredSessionRefreshesOnceAndRetryNeverRefreshesAgain() async throws {
        let (service, transport, archive, _, _) = try await makeService([
            jsonResponse("{}", status: 401), jsonResponse(#"{"value":{}}"#), jsonResponse(accountJSON), jsonResponse("{}", status: 401)
        ])
        let result = await service.fetch()
        XCTAssertEqual(result.status, .authenticationRequired)
        let paths = await transport.paths()
        XCTAssertEqual(paths.filter { $0 == "/auth/login" }.count, 1)
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 0)
    }

    func testSingleChallengeIsRetriedButRepeatedChallengeLatchesAttention() async throws {
        let challenge = jsonResponse(#"{"error_code":1010}"#, status: 403)
        let (service, transport, archive, tracking, sessions) = try await makeService([challenge, jsonResponse(accountJSON), challenge, challenge, challenge])
        try tracking.bind(configuration: RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting))
        var now = Date(timeIntervalSince1970: 1_700_000_010)
        let session = try tracking.start(now: now)
        // One odd answer only slows the loop down.
        guard case .wait = await service.poll(session: session, now: now) else { return XCTFail("A single challenge must not end tracking") }
        XCTAssertEqual(try tracking.status().lastStatus, .failed)
        var latched = await sessions.load(role: .burner)?.requiresAttention
        XCTAssertEqual(latched, false)
        now = try XCTUnwrap(tracking.status().nextPollAt)
        guard case .wait = await service.poll(session: session, now: now) else { return XCTFail("Recovered poll continues") }
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 1)
        XCTAssertEqual(try tracking.status().consecutiveFailures, 0)
        // Three in a row is a real problem: stop and ask the user.
        var decision = PollDecision.fetch
        for _ in 0..<3 {
            now = try XCTUnwrap(tracking.status().nextPollAt)
            decision = await service.poll(session: session, now: now)
        }
        XCTAssertEqual(decision, .stop(.needsAttention))
        latched = await sessions.load(role: .burner)?.requiresAttention
        XCTAssertEqual(latched, true)
        XCTAssertFalse(try tracking.status().isActive)
        let requests = await transport.paths().count
        let blocked = await service.fetch(now: now.addingTimeInterval(600))
        XCTAssertEqual(blocked.status, .attentionRequired)
        let afterwards = await transport.paths().count
        XCTAssertEqual(requests, afterwards)
    }

    func testRateLimitPersistsCooldown() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let (limited, _, _, tracking, _) = try await makeService([jsonResponse("{}", status: 429, headers: ["Retry-After": "180"])])
        let result = await limited.fetch(now: now)
        XCTAssertEqual(result.status, .rateLimited)
        XCTAssertEqual(try tracking.status().cooldownUntil, now.addingTimeInterval(180))
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
        XCTAssertNotNil(try tracking.status().cooldownUntil)
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
