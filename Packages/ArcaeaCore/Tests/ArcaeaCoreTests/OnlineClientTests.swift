import Foundation
import XCTest
@testable import ArcaeaCore

actor TestSessionStore: SessionStore {
    var sessions: [AccountRole: AccountSession] = [:]
    var replaceAfterCompare: AccountSession?
    func replaceAfterNextCompare(with session: AccountSession) { replaceAfterCompare = session }
    func load(role: AccountRole) -> AccountSession? { sessions[role] }
    func save(_ session: AccountSession, role: AccountRole) { sessions[role] = session }
    func clear(role: AccountRole) { sessions[role] = nil }
    func withValidSession<T: Sendable>(role: AccountRole, expectedRevision: UUID, operation: @Sendable () throws -> T) throws -> T {
        guard sessions[role]?.revision == expectedRevision else { throw OnlineError.cancelled }
        return try operation()
    }
    func compareAndSave(_ session: AccountSession, role: AccountRole, expectedRevision: UUID?) -> Bool {
        guard sessions[role]?.revision == expectedRevision else { return false }
        sessions[role] = session
        if let replacement = replaceAfterCompare { sessions[role] = replacement; replaceAfterCompare = nil }
        return true
    }
}

actor ScriptedTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [HTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw OnlineError.network }
        return responses.removeFirst()
    }
    func paths() -> [String] { requests.compactMap { $0.url?.path } }
    func recorded() -> [URLRequest] { requests }
}

func jsonResponse(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(status: status, headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a }, body: Data(body.utf8))
}

func testJar() -> CookieJar {
    var jar = CookieJar()
    jar.absorb(headers: ["Set-Cookie": "session=synthetic; Path=/; Secure"], url: URL(string: "https://webapi.lowiro.com/auth/login")!, now: Date())
    return jar
}

@MainActor final class OnlineClientTests: XCTestCase {
    func testRolesKeepCookiesAndRotationIsDurable() async throws {
        let store = TestSessionStore()
        await store.save(AccountSession(cookies: testJar(), boundAccount: AccountID("online:7")), role: .burner)
        let transport = ScriptedTransport([jsonResponse(#"{"value":{"user_id":7}}"#, headers: ["Set-Cookie": "session=rotated; Path=/; Secure"]), jsonResponse(#"{"value":{"user_id":8}}"#)])
        let client = ArcaeaWebClient(transport: transport, sessions: store)
        _ = try await client.readAccount(role: .burner, expected: AccountID("online:7"))
        _ = try await client.readAccount(role: .main, expected: nil)
        let requests = await transport.recorded()
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Cookie"), "session=synthetic")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Cookie"))
        let persisted = await store.load(role: .burner)
        XCTAssertEqual(persisted?.cookies.header(for: URL(string: "https://webapi.lowiro.com/webapi/user/me")!, now: Date()), "session=rotated")
    }

    func testWrongIdentityDoesNotBindOrReturnData() async throws {
        let store = TestSessionStore()
        let transport = ScriptedTransport([jsonResponse(#"{"value":{"user_id":8}}"#)])
        let client = ArcaeaWebClient(transport: transport, sessions: store)
        do { _ = try await client.readAccount(role: .burner, expected: AccountID("online:7")); XCTFail("Expected identity rejection") }
        catch { XCTAssertEqual(error as? OnlineError, .wrongAccount) }
    }
    func testFailedLoginEnvelopeStopsBeforeReadingAccount() async throws {
        let store = TestSessionStore()
        let transport = ScriptedTransport([jsonResponse(#"{"success":false,"error_code":999}"#)])
        let client = ArcaeaWebClient(transport: transport, sessions: store)
        do {
            _ = try await client.login(role: .burner, credentials: LoginCredentials(email: "synthetic@example.invalid", password: "synthetic"))
            XCTFail("Failed envelope must stop login")
        } catch { XCTAssertEqual(error as? OnlineError, .interactionRequired) }
        let paths = await transport.paths()
        XCTAssertEqual(paths, ["/auth/login"])
    }

}

actor SuspendedTransport: HTTPTransport {
    private var pending: CheckedContinuation<HTTPResponse, Error>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var started = false
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        started = true; waiter?.resume(); waiter = nil
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func waitForRequest() async {
        if started { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func resume(_ response: HTTPResponse) { pending?.resume(returning: response); pending = nil }
}

@MainActor final class SessionInvalidationTests: XCTestCase {
    func testDisconnectDuringResponseCannotResurrectSession() async throws {
        let store = TestSessionStore()
        await store.save(AccountSession(cookies: testJar(), boundAccount: AccountID("online:7")), role: .burner)
        let transport = SuspendedTransport()
        let client = ArcaeaWebClient(transport: transport, sessions: store)
        let task = Task { try await client.readAccount(role: .burner, expected: AccountID("online:7")) }
        await transport.waitForRequest()
        await store.clear(role: .burner)
        await transport.resume(jsonResponse(#"{"value":{"user_id":7}}"#, headers: ["Set-Cookie": "session=stale; Path=/; Secure"]))
        do { _ = try await task.value; XCTFail("Disconnected response must be rejected") } catch { XCTAssertEqual(error as? OnlineError, .cancelled) }
        let current = await store.load(role: .burner)
        XCTAssertNil(current)
    }

    func testRefreshWithOldRevisionCannotOverwriteReplacement() async throws {
        let store = TestSessionStore()
        let old = AccountSession(cookies: testJar(), boundAccount: AccountID("online:7"))
        let replacement = AccountSession(cookies: testJar(), boundAccount: AccountID("online:8"))
        await store.save(old, role: .burner)
        await store.save(replacement, role: .burner)
        let transport = ScriptedTransport([])
        let client = ArcaeaWebClient(transport: transport, sessions: store)
        do {
            _ = try await client.login(role: .burner, credentials: LoginCredentials(email: "example@example.invalid", password: "synthetic"), expected: old.boundAccount, expectation: .revision(old.revision), reuseRoleCookies: true)
            XCTFail("Stale refresh must reject before sending credentials")
        } catch { XCTAssertEqual(error as? OnlineError, .cancelled) }
        let current = await store.load(role: .burner)
        XCTAssertEqual(current?.revision, replacement.revision)
        let paths = await transport.paths()
        XCTAssertTrue(paths.isEmpty)
    }

    func testRoleUserAgentAndRefererContinueOnlyThatRoleBrowserSession() async throws {
        let store = TestSessionStore()
        await store.save(AccountSession(cookies: testJar(), browserUserAgent: "Synthetic browser session agent"), role: .main)
        let transport = ScriptedTransport([jsonResponse(#"{"value":{"user_id":7}}"#), jsonResponse(#"{"value":{"user_id":8}}"#)])
        let client = ArcaeaWebClient(transport: transport, sessions: store)
        _ = try await client.readAccount(role: .main)
        _ = try await client.readAccount(role: .burner)
        let requests = await transport.recorded()
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "User-Agent"), "Synthetic browser session agent")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "User-Agent"))
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Referer"), "https://arcaea.lowiro.com/")
    }
    func testLoginSubrequestCannotUseLaterReplacementJar() async throws {
        let store = TestSessionStore()
        let old = AccountSession(cookies: testJar(), boundAccount: AccountID("online:7"))
        let replacement = AccountSession(cookies: testJar(), boundAccount: AccountID("online:8"))
        await store.save(old, role: .burner)
        await store.replaceAfterNextCompare(with: replacement)
        let transport = ScriptedTransport([])
        let client = ArcaeaWebClient(transport: transport, sessions: store)
        do {
            _ = try await client.login(role: .burner, credentials: LoginCredentials(email: "synthetic@example.invalid", password: "synthetic"), expectation: .revision(old.revision))
            XCTFail("A replaced login must reject before POST")
        } catch { XCTAssertEqual(error as? OnlineError, .cancelled) }
        let requests = await transport.paths()
        XCTAssertTrue(requests.isEmpty)
        let current = await store.load(role: .burner)
        XCTAssertEqual(current?.revision, replacement.revision)
    }

}
