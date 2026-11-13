import ArcaeaCore
import UIKit
import XCTest
@testable import ArcaeaOffline

@MainActor private final class TestPulseDelivery: PulseDelivery {
    var allowed = true
    var scheduled: [(session: UUID, seconds: Int)] = []
    var pending: UUID?
    func authorized() async -> Bool { allowed }
    func schedule(session: UUID, after seconds: Int) async throws { scheduled.append((session, seconds)); pending = session }
    func cancel() { pending = nil }
}

@MainActor final class ArcProbeTests: XCTestCase {
    private func fixture(_ count: Int = 3) async throws -> (NotificationTracking, OnlineRuntime, TestPulseDelivery, ArchiveStore) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = try ArchiveStore(url: folder.appendingPathComponent("archive.sqlite"))
        let sessions = RuntimeTestSessions()
        let config = RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting)
        var jar = CookieJar()
        jar.absorb(headers: ["Set-Cookie": "session=test; Path=/; Secure"], url: URL(string: "https://webapi.lowiro.com/auth/login")!, now: Date())
        await sessions.save(AccountSession(cookies: jar, boundAccount: config.observer, recentConfiguration: config), role: .burner)
        let response = HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(#"{"value":{"user_id":7,"recent_score":[{"song_id":"test","difficulty":2,"score":9800000}]}}"#.utf8))
        let runtime = try OnlineRuntime(store: archive, directory: folder, sessions: sessions, transport: RuntimeTestTransport(Array(repeating: response, count: count)))
        let delivery = TestPulseDelivery()
        return (NotificationTracking(delivery: delivery), runtime, delivery, archive)
    }
    func testNotificationChainChecksOnceAndKeepsASinglePendingPulse() async throws {
        let (service, runtime, delivery, archive) = try await fixture()
        try await service.start(runtime: runtime)
        let session = try XCTUnwrap(runtime.status().session)
        XCTAssertEqual(delivery.pending, session)
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 1)
        // A duplicate or early pulse only re-schedules the same single notification.
        let wait = try await service.process(message: NotificationTracking.message(session: session), runtime: runtime)
        XCTAssertGreaterThan(wait, 0)
        XCTAssertEqual(delivery.scheduled.count, 2)
        XCTAssertEqual(delivery.pending, session)
        // After a reopen the old pulse does nothing and leaves the new chain alone.
        try runtime.stopTracking()
        try await service.start(runtime: runtime)
        let replacement = try XCTUnwrap(runtime.status().session)
        let stale = try await service.process(message: "\(NotificationTracking.title)\n" + NotificationTracking.message(session: session), runtime: runtime)
        XCTAssertEqual(stale, 0)
        XCTAssertEqual(delivery.pending, replacement)
    }
    func testNotificationTrackingNeedsPermissionAndAValidMessage() async throws {
        let (service, runtime, delivery, _) = try await fixture()
        delivery.allowed = false
        do { try await service.start(runtime: runtime); XCTFail("Expected permission error") }
        catch { XCTAssertEqual(error as? NotificationTrackingError, .permission) }
        XCTAssertFalse(try runtime.status().isActive)
        do { _ = try await service.process(message: "hello", runtime: runtime); XCTFail("Expected message error") }
        catch { XCTAssertEqual(error as? NotificationTrackingError, .invalidMessage) }
        XCTAssertTrue(delivery.scheduled.isEmpty)
    }
    func testOfficialArtworkURLAndInvalidImage() throws {
        XCTAssertEqual(LibraryResources.coverURL("songs/test/base")?.absoluteString, "https://webassets.lowiro.com/songs/test/base.jpg")
        for identifier in ["../private", "https://example.com/image", "test?token=secret", "test/../private"] { XCTAssertNil(LibraryResources.coverURL(identifier)) }
        XCTAssertThrowsError(try LibraryResources.thumbnail(Data("not an image".utf8)))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in UIColor.purple.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32)) }
        XCTAssertNotNil(UIImage(data: try LibraryResources.thumbnail(XCTUnwrap(image.pngData()))))
    }
}
