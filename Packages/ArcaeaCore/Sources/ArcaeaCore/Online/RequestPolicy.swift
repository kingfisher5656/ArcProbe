import Foundation

public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public init(status: Int, headers: [String: String], body: Data) { self.status = status; self.headers = headers; self.body = body }
    public func header(_ name: String) -> String? { headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value }
}

public enum RequestPolicy {
    public static let origin = "https://webapi.lowiro.com"

    public static func url(path: String) throws -> URL {
        guard let url = URL(string: origin + path) else { throw OnlineError.forbiddenURL }
        try validate(url)
        return url
    }

    public static func scoreURL(difficulty: Difficulty, page: Int) throws -> URL {
        guard (1...1_000).contains(page) else { throw OnlineError.unsupportedResponse }
        return try url(path: "/webapi/score/song/me/all?difficulty=\(difficulty.rawValue)&page=\(page)&sort=date&term=")
    }

    public static func validate(_ url: URL) throws {
        guard url.scheme == "https", url.host == "webapi.lowiro.com", url.user == nil, url.password == nil,
              url.fragment == nil, url.port == nil || url.port == 443 else { throw OnlineError.forbiddenURL }
        switch url.path {
        case "/auth/login", "/webapi/user/me", "/webapi/friend/me", "/webapi/score/rating/me":
            guard url.query == nil else { throw OnlineError.forbiddenURL }
        case "/webapi/score/rating_progression/me":
            guard url.query == "duration=5y" else { throw OnlineError.forbiddenURL }
        case "/webapi/score/song/me/all":
            guard let query = url.query, query.range(of: #"^difficulty=[0-4]&page=[1-9][0-9]{0,3}&sort=date&term=$"#, options: .regularExpression) != nil,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let pageString = components.queryItems?.first(where: { $0.name == "page" })?.value,
                  let page = Int(pageString), page <= 1_000 else { throw OnlineError.forbiddenURL }
        default: throw OnlineError.forbiddenURL
        }
    }

    public static func validateResponse(_ response: HTTPResponse, now: Date, isLogin: Bool = false) throws {
        if response.status == 429 { throw OnlineError.rateLimited(until: retryDate(response.header("Retry-After"), now: now)) }
        // A 403 can be a JSON Cloudflare challenge (observed code 1010); it is never session expiry.
        if response.status == 403 || (300..<400).contains(response.status) || response.header("Content-Type")?.lowercased().contains("text/html") == true { throw OnlineError.interactionRequired }
        if response.status == 401 { throw isLogin ? OnlineError.credentialsRejected : OnlineError.expiredSession }
        if isLogin && response.status == 400 { throw OnlineError.credentialsRejected }
        guard response.status == 200 else { throw OnlineError.network }
        guard response.body.count <= OnlineParser.maximumResponseBytes else { throw OnlineError.oversizedResponse }
        guard response.header("Content-Type")?.lowercased().contains("json") == true else { throw OnlineError.unsupportedResponse }
    }

    public static func retryDate(_ value: String?, now: Date) -> Date {
        let minimum = now.addingTimeInterval(60)
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return minimum }
        if let seconds = Double(value), seconds.isFinite, seconds >= 0, seconds <= 31_536_000 { return max(minimum, now.addingTimeInterval(seconds)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(minimum, $0) } ?? minimum
    }
}
