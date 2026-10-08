import ArcaeaCore
import UIKit
import XCTest
@testable import ArcaeaOffline

@MainActor private final class TestPulseDelivery: PulseDelivery {
    var allowed = true
    var fails = false
    var pending: Set<UUID> = []
    var onSchedule: (() throws -> Void)?
    func authorized() async -> Bool { allowed }
    func schedule(_ state: NotificationPulseState) async throws {
        if fails { throw LibraryResourceError.unavailable }
        pending.insert(state.token!)
        try onSchedule?()
    }
    func cancel(token: UUID) { pending.remove(token) }
}

@MainActor final class ArcProbeTests: XCTestCase {
    private func fixture() async throws -> (NotificationTracking, OnlineRuntime, TestPulseDelivery, ArchiveStore) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = try ArchiveStore(url: folder.appendingPathComponent("archive.sqlite"))
        let sessions = RuntimeTestSessions()
        let config = RecentConfiguration(observer: AccountID("online:7"), target: AccountID("online:7"), mode: .ownAccountTesting)
        var jar = CookieJar()
        jar.absorb(headers: ["Set-Cookie": "session=test; Path=/; Secure"], url: URL(string: "https://webapi.lowiro.com/auth/login")!, now: Date())
        await sessions.save(AccountSession(cookies: jar, boundAccount: config.observer, recentConfiguration: config), role: .burner)
        let response = HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(#"{"value":{"user_id":7,"recent_score":[{"song_id":"test","difficulty":2,"score":9800000}]}}"#.utf8))
        let runtime = try OnlineRuntime(store: archive, directory: folder, sessions: sessions, transport: RuntimeTestTransport([response]))
        let delivery = TestPulseDelivery()
        let service = NotificationTracking(store: try NotificationPulseStore(url: folder.appendingPathComponent("pulses.sqlite")), delivery: delivery)
        return (service, runtime, delivery, archive)
    }
    func testNotificationRenewsOnceThenStopRejectsDeliveredPulse() async throws {
        let (service, runtime, delivery, archive) = try await fixture()
        let first = try await service.start(runtime: runtime)
        let body = "arcprobe:\(first.generation!):\(first.token!)"
        let result = try await service.process(message: body, runtime: runtime, now: first.nextAt!)
        XCTAssertTrue(result.contains("success"))
        let second = try service.state()
        XCTAssertNotEqual(second.token, first.token)
        XCTAssertEqual(delivery.pending, Set([second.token!]))
        _ = try await service.process(message: body, runtime: runtime, now: first.nextAt!)
        XCTAssertEqual(try service.state().token, second.token)
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 1)
        try service.stop(runtime: runtime)
        _ = try await service.process(message: "arcprobe:\(second.generation!):\(second.token!)", runtime: runtime, now: second.nextAt!)
        XCTAssertFalse(try service.state().isActive)
        XCTAssertTrue(delivery.pending.isEmpty)
        XCTAssertFalse(try runtime.status().isActive)
    }
    func testScheduleFailureAndStopDuringRegistrationLeaveNoPendingPulse() async throws {
        let (service, runtime, delivery, _) = try await fixture()
        delivery.fails = true
        do { _ = try await service.start(runtime: runtime); XCTFail("Expected scheduling failure") } catch {}
        XCTAssertFalse(try service.state().isActive)
        XCTAssertTrue(delivery.pending.isEmpty)
        XCTAssertFalse(try runtime.status().isActive)
        delivery.fails = false
        delivery.onSchedule = { try service.stop(runtime: runtime) }
        _ = try await service.start(runtime: runtime)
        XCTAssertFalse(try service.state().isActive)
        XCTAssertTrue(delivery.pending.isEmpty)
    }
    func testOfficialArtworkURLAndInvalidImage() throws {
        XCTAssertEqual(LibraryResources.coverURL("songs/test/base")?.absoluteString, "https://webassets.lowiro.com/songs/test/base.jpg")
        for identifier in ["../private", "https://example.com/image", "test?token=secret", "test/../private"] { XCTAssertNil(LibraryResources.coverURL(identifier)) }
        XCTAssertThrowsError(try LibraryResources.thumbnail(Data("not an image".utf8)))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in UIColor.purple.setFill(); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32)) }
        XCTAssertNotNil(UIImage(data: try LibraryResources.thumbnail(XCTUnwrap(image.pngData()))))
    }
}
