import Foundation

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// URLSession never uses shared cookies, credentials, or redirects. The caller provides its role's jar.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let maximumBytes: Int
    private let session: URLSession
    public init(maximumBytes: Int = OnlineParser.maximumResponseBytes) {
        self.maximumBytes = maximumBytes
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        guard let url = request.url else { throw OnlineError.forbiddenURL }
        try RequestPolicy.validate(url)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.url == url else { throw OnlineError.forbiddenURL }
            guard response.expectedContentLength <= maximumBytes else { throw OnlineError.oversizedResponse }
            var data = Data()
            for try await byte in bytes {
                if data.count >= maximumBytes { throw OnlineError.oversizedResponse }
                data.append(byte)
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data)
        } catch is CancellationError { throw OnlineError.cancelled }
        catch let error as OnlineError { throw error }
        catch let error as URLError where error.code == .cancelled { throw OnlineError.cancelled }
        catch { throw OnlineError.network }
    }
}

public actor ArcaeaWebClient {
    private let transport: any HTTPTransport
    public let sessions: any SessionStore
    public init(transport: any HTTPTransport = URLSessionTransport(), sessions: any SessionStore) {
        self.transport = transport; self.sessions = sessions
    }

    public func readAccount(role: AccountRole, expected: AccountID? = nil, now: Date = Date(), expectedRevision: UUID? = nil) async throws -> RemoteAccount {
        let data = try await request(path: "/webapi/user/me", role: role, now: now, expectedRevision: expectedRevision)
        let account = try OnlineParser.account(data, now: now)
        let session = try await sessions.load(role: role) ?? AccountSession()
        guard expectedRevision == nil || session.revision == expectedRevision else { throw OnlineError.cancelled }
        guard expected == nil || account.profile.id == expected,
              session.boundAccount == nil || session.boundAccount == account.profile.id else { throw OnlineError.wrongAccount }
        return account
    }

    public func scorePage(difficulty: Difficulty, page: Int, account: AccountID, now: Date = Date(), expectedRevision: UUID? = nil) async throws -> ScorePage {
        let url = try RequestPolicy.scoreURL(difficulty: difficulty, page: page)
        return try OnlineParser.scorePage(await request(url: url, role: .main, now: now, expectedRevision: expectedRevision), difficulty: difficulty, account: account, now: now)
    }

    public func history(account: AccountID, now: Date = Date(), expectedRevision: UUID? = nil) async throws -> [PotentialPoint] {
        try OnlineParser.potentialHistory(await request(path: "/webapi/score/rating_progression/me?duration=5y", role: .main, now: now, expectedRevision: expectedRevision), account: account, now: now)
    }

    public func recent(configuration: RecentConfiguration, now: Date = Date(), expectedRevision: UUID? = nil) async throws -> RecentPayload {
        let account = try await readAccount(role: .burner, expected: configuration.observer, now: now, expectedRevision: expectedRevision)
        if configuration.mode == .ownAccountTesting {
            guard configuration.target == configuration.observer else { throw OnlineError.wrongAccount }
            return RecentPayload(profile: account.profile, observations: account.recentScores, charts: account.recentCharts)
        }
        let data = try await request(path: "/webapi/friend/me", role: .burner, now: now, expectedRevision: expectedRevision)
        return try OnlineParser.friendPayload(data, target: configuration.target, now: now)
    }

    /// At most one call is made by RecentSyncService after a documented 401, or once for bootstrap.
    public func login(role: AccountRole, credentials: LoginCredentials, expected: AccountID? = nil, now: Date = Date(), replacementRevision: UUID = UUID(), expectation: SessionExpectation = .any, reuseRoleCookies: Bool = false) async throws -> RemoteAccount {
        guard !credentials.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !credentials.password.isEmpty else { throw OnlineError.credentialsRejected }
        let old = try await sessions.load(role: role)
        if case let .revision(expected) = expectation, old?.revision != expected { throw OnlineError.cancelled }
        try Task.checkCancellation()
        var replacement = AccountSession(revision: replacementRevision, credentials: role == .burner ? credentials : nil, recentConfiguration: reuseRoleCookies ? old?.recentConfiguration : nil, browserUserAgent: old?.browserUserAgent, serverCooldownUntil: old?.serverCooldownUntil, nextImportEligibleAt: old?.nextImportEligibleAt)
        // Refresh keeps valid verification cookies from this same role's legitimate login.
        // Intentional replacement starts a fresh role jar, retaining only its CSRF context.
        if let cookies = old?.cookies.cookies.filter({ reuseRoleCookies || $0.name == "csrf" }) { replacement.cookies.merge(cookies, now: now) }
        guard try await sessions.compareAndSave(replacement, role: role, expectedRevision: old?.revision) else { throw OnlineError.cancelled }
        let body = try JSONEncoder().encode(credentials)
        let response = try await request(path: "/auth/login", role: role, method: "POST", body: body, now: now, isLogin: true, expectedRevision: replacementRevision)
        try OnlineParser.validateLogin(response)
        let account = try await readAccount(role: role, expected: expected, now: now, expectedRevision: replacementRevision)
        var saved = try await sessions.load(role: role) ?? replacement
        saved.boundAccount = account.profile.id; saved.requiresAttention = false
        guard try await sessions.compareAndSave(saved, role: role, expectedRevision: replacement.revision) else { throw OnlineError.cancelled }
        return account
    }

    public func bind(role: AccountRole, account: AccountID, expectedRevision: UUID) async throws {
        let existing = try await sessions.load(role: role)
        guard existing?.revision == expectedRevision else { throw OnlineError.cancelled }
        var session = existing ?? AccountSession()
        session.boundAccount = account; session.requiresAttention = false
        guard try await sessions.compareAndSave(session, role: role, expectedRevision: existing?.revision) else { throw OnlineError.cancelled }
    }

    public func request(path: String, role: AccountRole, method: String = "GET", body: Data? = nil, now: Date = Date(), isLogin: Bool = false, expectedRevision: UUID? = nil) async throws -> Data {
        try await request(url: RequestPolicy.url(path: path), role: role, method: method, body: body, now: now, isLogin: isLogin, expectedRevision: expectedRevision)
    }

    private func request(url: URL, role: AccountRole, method: String = "GET", body: Data? = nil, now: Date, isLogin: Bool = false, expectedRevision: UUID? = nil) async throws -> Data {
        try Task.checkCancellation()
        let existing = try await sessions.load(role: role)
        guard expectedRevision == nil || existing?.revision == expectedRevision else { throw OnlineError.cancelled }
        var session = existing ?? AccountSession()
        if let cooldown = session.serverCooldownUntil, cooldown > now { throw OnlineError.rateLimited(until: cooldown) }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://arcaea.lowiro.com", forHTTPHeaderField: "Origin")
        request.setValue("https://arcaea.lowiro.com/", forHTTPHeaderField: "Referer")
        if let userAgent = session.browserUserAgent, userAgent.utf8.count <= 1024, !userAgent.contains("\n"), !userAgent.contains("\r") {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let cookie = session.cookies.header(for: url, now: now)
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        if let csrf = session.cookies.csrfToken(for: url, now: now) { request.setValue(csrf, forHTTPHeaderField: "X-CSRF-TOKEN") }
        let response = try await transport.send(request)
        // Persist rotations and explicit cookie deletions even on an error response.
        session.cookies.absorb(headers: response.headers, url: url, now: now)
        if response.status == 429 { session.serverCooldownUntil = RequestPolicy.retryDate(response.header("Retry-After"), now: now) }
        guard try await sessions.compareAndSave(session, role: role, expectedRevision: existing?.revision) else { throw OnlineError.cancelled }
        try Task.checkCancellation()
        try RequestPolicy.validateResponse(response, now: now, isLogin: isLogin)
        return response.body
    }
}
