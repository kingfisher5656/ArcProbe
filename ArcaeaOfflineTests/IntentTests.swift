import ArcaeaCore
import Foundation
import XCTest
@testable import ArcaeaOffline

/// The Shortcut loop as the Shortcuts app drives it: Start → Check → wait → Check → …
@MainActor final class IntentTests: XCTestCase {
    private let recent = #"{"value":{"user_id":7,"recent_score":[{"song_id":"test","difficulty":2,"score":9800000}]}}"#
    private func response(_ body: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }
    private func makeRuntime(_ responses: [HTTPResponse], configured: Bool = true) async throws -> (OnlineRuntime, ArchiveStore, RuntimeTestSessions) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = try ArchiveStore(url: folder.appendingPathComponent("archive.sqlite"))
        let sessions = RuntimeTestSessions()
        if configured {
            let config = RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting)
            var jar = CookieJar()
            jar.absorb(headers: ["Set-Cookie": "session=synthetic-private-value; Path=/; Secure"], url: URL(string: "https://webapi.lowiro.com/auth/login")!, now: Date())
            await sessions.save(AccountSession(cookies: jar, boundAccount: config.observer, recentConfiguration: config), role: .burner)
        }
        return (try OnlineRuntime(store: archive, directory: folder, sessions: sessions, transport: RuntimeTestTransport(responses)), archive, sessions)
    }

    func testStartThenCheckSavesPlayAndReturnsWait() async throws {
        let (runtime, archive, _) = try await makeRuntime([response(recent)])
        var changes = 0
        runtime.onArchiveChanged = { changes += 1 }
        let session = try await TrackingActions.start(runtime: runtime)
        XCTAssertNotNil(UUID(uuidString: session))
        let wait = try await TrackingActions.check(runtime: runtime, session: session)
        XCTAssertTrue((65...81).contains(wait))
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 1)
        XCTAssertEqual(changes, 1)
        // Checking again right away only reports the remaining wait; no second request is made.
        let again = try await TrackingActions.check(runtime: runtime, session: session)
        XCTAssertTrue((1...wait).contains(again))
        XCTAssertEqual(changes, 1)
    }

    func testOlderLoopEndsAfterReopenAndBadSessionIsRejected() async throws {
        let (runtime, _, _) = try await makeRuntime([response(recent)])
        let old = try await TrackingActions.start(runtime: runtime)
        try runtime.stopTracking()
        let new = try await TrackingActions.start(runtime: runtime)
        let stale = try await TrackingActions.check(runtime: runtime, session: old)
        XCTAssertEqual(stale, 0)
        let current = try await TrackingActions.check(runtime: runtime, session: new)
        XCTAssertGreaterThan(current, 0)
        do { _ = try await TrackingActions.check(runtime: runtime, session: "not a session"); XCTFail("Expected an error") }
        catch { XCTAssertEqual(error as? TrackingSetupError, .invalidSession) }
    }

    func testStartWithoutTrackerAccountExplainsWhatToDo() async throws {
        let (runtime, _, _) = try await makeRuntime([], configured: false)
        do { _ = try await TrackingActions.start(runtime: runtime); XCTFail("Expected an error") }
        catch { XCTAssertEqual(error as? TrackingSetupError, .notConfigured) }
    }

    func testExpiredLoginStopsLoopWithAnErrorAndMarksAccount() async throws {
        let (runtime, _, sessions) = try await makeRuntime([response("{}", status: 401)])
        let session = try await TrackingActions.start(runtime: runtime)
        do { _ = try await TrackingActions.check(runtime: runtime, session: session); XCTFail("Expected an error") }
        catch { XCTAssertEqual(error as? TrackingSetupError, .needsAttention) }
        let latched = await sessions.load(role: .burner)?.requiresAttention
        XCTAssertEqual(latched, true)
        XCTAssertTrue(runtime.recentNeedsAttention)
        XCTAssertFalse(try runtime.status().isActive)
    }

    func testOneShotFetchSummaryContainsNoSecrets() async throws {
        let (runtime, _, _) = try await makeRuntime([response(recent), response(recent)])
        let first = await runtime.fetchRecent()
        XCTAssertEqual(first.summary, "Saved 1 new play")
        let second = await runtime.fetchRecent()
        XCTAssertEqual(second.summary, "No new play")
        XCTAssertFalse(first.summary.contains("synthetic-private-value"))
    }
}
