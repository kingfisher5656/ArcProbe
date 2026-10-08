import Foundation
import XCTest
@testable import ArcaeaCore

@MainActor final class MainImportTests: XCTestCase {
    let active = #"{"value":{"user_id":7,"name":"Example","arcaea_online_expire_ts":86400000}}"#
    func make(_ responses: [HTTPResponse]) async throws -> (MainImportService, ScriptedTransport, ArchiveStore) {
        let store = try ArchiveStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite"))
        let sessions = TestSessionStore()
        await sessions.save(AccountSession(cookies: testJar(), boundAccount: AccountID("online:7")), role: .main)
        let transport = ScriptedTransport(responses)
        let service = MainImportService(client: ArcaeaWebClient(transport: transport, sessions: sessions), archive: store, requestInterval: 0)
        return (service, transport, store)
    }
    func emptyPage() -> HTTPResponse { jsonResponse(#"{"value":{"count":0,"scores":[]}}"#) }

    func testAllDifficultiesPagesAndHistoryCommitTogether() async throws {
        let pages = (0...4).map { difficulty in jsonResponse("{\"value\":{\"count\":1,\"scores\":[{\"song_id\":\"test\",\"difficulty\":\(difficulty),\"score\":9800000}]}}") }
        let (service, transport, archive) = try await make([jsonResponse(active)] + pages + [jsonResponse(#"{"value":[{"time_played":1700000000000,"user_rating":12345}]}"#), jsonResponse(active)])
        let receipt = try await service.sync(expectedAccount: AccountID("online:7"))
        XCTAssertEqual(receipt.addedCount, 5)
        XCTAssertEqual(receipt.addedPotentialCount, 1)
        XCTAssertEqual(try archive.sourceObservations(accountID: AccountID("online:7")).count, 5)
        let requests = await transport.recorded()
        XCTAssertEqual(requests.filter { $0.url?.path == "/webapi/score/song/me/all" }.count, 5)
    }

    func testDuplicatePageAndFinalAccountChangeSaveNothing() async throws {
        let page = jsonResponse(#"{"value":{"count":2,"scores":[{"song_id":"test","difficulty":0,"score":9800000}]}}"#)
        let (duplicate, _, archive) = try await make([jsonResponse(active), page, page])
        do { _ = try await duplicate.sync(expectedAccount: AccountID("online:7")); XCTFail("Duplicate page must fail") } catch { XCTAssertEqual(error as? OnlineError, .unsupportedResponse) }
        XCTAssertEqual(try archive.profiles().count, 0)
        let (changed, _, unchangedArchive) = try await make([jsonResponse(active)] + (0...4).map { _ in emptyPage() } + [jsonResponse(#"{"value":[]}"#), jsonResponse(#"{"value":{"user_id":8,"arcaea_online_expire_ts":86400000}}"#)])
        do { _ = try await changed.sync(expectedAccount: AccountID("online:7")); XCTFail("Account change must fail") } catch { XCTAssertEqual(error as? OnlineError, .wrongAccount) }
        XCTAssertEqual(try unchangedArchive.profiles().count, 0)
    }

    func testRequiredHistoryFailurePreservesArchive() async throws {
        let (service, _, archive) = try await make([jsonResponse(active)] + (0...4).map { _ in emptyPage() } + [jsonResponse("{}", status: 503)])
        do { _ = try await service.sync(expectedAccount: AccountID("online:7")); XCTFail("History failure must fail") } catch { XCTAssertEqual(error as? OnlineError, .network) }
        XCTAssertEqual(try archive.receipts().count, 0)
    }
}

@MainActor final class MainImportInvalidationTests: XCTestCase {
    func testDisconnectAtFinalProgressGateCannotCommitCompletedBatch() async throws {
        let archive = try ArchiveStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite"))
        let sessions = TestSessionStore()
        await sessions.save(AccountSession(cookies: testJar(), boundAccount: AccountID("online:7")), role: .main)
        let active = jsonResponse(#"{"value":{"user_id":7,"arcaea_online_expire_ts":86400000}}"#)
        let empty = jsonResponse(#"{"value":{"count":0,"scores":[]}}"#)
        let transport = ScriptedTransport([active] + Array(repeating: empty, count: 5) + [jsonResponse(#"{"value":[]}"#), active])
        let service = MainImportService(client: ArcaeaWebClient(transport: transport, sessions: sessions), archive: archive, requestInterval: 0)
        do {
            _ = try await service.sync(expectedAccount: AccountID("online:7")) { update in
                if update.stage == .saving { await sessions.clear(role: .main) }
            }
            XCTFail("Disconnected completed import must reject")
        } catch { XCTAssertEqual(error as? OnlineError, .cancelled) }
        XCTAssertTrue(try archive.profiles().isEmpty)
    }

    func testServerCooldownSurvivesClientRecreationAndNeverSendsEarlyRequest() async throws {
        let sessions = TestSessionStore()
        await sessions.save(AccountSession(cookies: testJar(), boundAccount: AccountID("online:7")), role: .main)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let firstTransport = ScriptedTransport([jsonResponse("{}", status: 429, headers: ["Retry-After": "180"])])
        let first = ArcaeaWebClient(transport: firstTransport, sessions: sessions)
        do { _ = try await first.readAccount(role: .main, now: now); XCTFail("429 must stop") } catch { XCTAssertEqual(error as? OnlineError, .rateLimited(until: now.addingTimeInterval(180))) }
        let secondTransport = ScriptedTransport([])
        let second = ArcaeaWebClient(transport: secondTransport, sessions: sessions)
        do { _ = try await second.readAccount(role: .main, now: now.addingTimeInterval(70)); XCTFail("Cooldown must persist") } catch { XCTAssertEqual(error as? OnlineError, .rateLimited(until: now.addingTimeInterval(180))) }
        let requests = await secondTransport.paths()
        XCTAssertTrue(requests.isEmpty)
    }
}
