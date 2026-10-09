import ArcaeaCore
import Foundation
import XCTest
@testable import ArcaeaOffline

@MainActor final class IntentTests: XCTestCase {
    func testShortcutFetchStatusAndStopUseSameDurableRuntimeAndExcludeSecrets() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = try ArchiveStore(url: folder.appendingPathComponent("archive.sqlite"))
        let sessions = RuntimeTestSessions()
        let config = RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting)
        var jar = CookieJar()
        jar.absorb(headers: ["Set-Cookie": "session=synthetic-private-value; Path=/; Secure"], url: URL(string: "https://webapi.lowiro.com/auth/login")!, now: Date())
        await sessions.save(AccountSession(cookies: jar, boundAccount: config.observer, credentials: LoginCredentials(email: "example@example.invalid", password: "synthetic-password"), recentConfiguration: config), role: .burner)
        let response = HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(#"{"value":{"user_id":7,"recent_score":[{"song_id":"test","difficulty":2,"score":9800000}]}}"#.utf8))
        let runtime = try OnlineRuntime(store: archive, directory: folder, sessions: sessions, transport: RuntimeTestTransport([response, response]))
        let generation = try ShortcutActions.setTracking(runtime: runtime, active: true)
        XCTAssertNotNil(UUID(uuidString: generation))
        let output = try await ShortcutActions.fetch(runtime: runtime, generation: generation)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "success")
        XCTAssertEqual(result["addedCount"] as? Int, 1)
        XCTAssertNotNil(result["lastSuccessAt"])
        XCTAssertFalse(output.contains("synthetic-password"))
        XCTAssertFalse(output.contains("synthetic-private-value"))
        _ = try ShortcutActions.setTracking(runtime: runtime, active: false)
        let stopped = try await ShortcutActions.fetch(runtime: runtime, generation: generation)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(stopped.utf8)) as? [String: Any])?["status"] as? String, "trackingStopped")
        let closing = try await ShortcutActions.fetch(runtime: runtime, generation: generation, finalFetch: true)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(closing.utf8)) as? [String: Any])?["status"] as? String, "cooldown")
        do {
            _ = try await ShortcutActions.fetch(runtime: runtime, generation: nil, finalFetch: true)
            XCTFail("A closing fetch must retain its original generation")
        } catch { XCTAssertTrue(error is ShortcutActionError) }
        try runtime.setMinimumIntervalEnabled(false)
        let immediate = try await ShortcutActions.fetch(runtime: runtime, generation: generation, finalFetch: true)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(immediate.utf8)) as? [String: Any])?["status"] as? String, "unchanged")
        XCTAssertFalse(try runtime.status().minimumIntervalEnabled)
        let status = try ShortcutActions.status(runtime: runtime)
        let dictionary = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(status.utf8)) as? [String: Any])
        XCTAssertEqual(dictionary["isActive"] as? Bool, false)
        XCTAssertNil(dictionary["lease"])
        XCTAssertNil(dictionary["credentials"])
    }
}
