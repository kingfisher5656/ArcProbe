import Foundation

public struct SessionCookie: Codable, Sendable, Hashable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let secure: Bool
    public let httpOnly: Bool
    public let expiresAt: Date?
    public let hostOnly: Bool

    public init(_ cookie: HTTPCookie, maximumAge: TimeInterval? = nil, now: Date = Date()) {
        name = cookie.name; value = cookie.value; domain = cookie.domain.lowercased()
        path = cookie.path; secure = cookie.isSecure; httpOnly = cookie.isHTTPOnly
        expiresAt = maximumAge.map { now.addingTimeInterval($0) } ?? cookie.expiresDate; hostOnly = !cookie.domain.hasPrefix(".")
    }

    public func matches(_ url: URL, now: Date) -> Bool {
        guard let host = url.host?.lowercased(), !secure || url.scheme == "https", expiresAt == nil || expiresAt! > now else { return false }
        let normalized = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
        guard host == normalized || (!hostOnly && host.hasSuffix("." + normalized)) else { return false }
        let requestPath = url.path.isEmpty ? "/" : url.path
        return requestPath == path || (requestPath.hasPrefix(path) && (path.hasSuffix("/") || requestPath.dropFirst(path.count).first == "/"))
    }
}

public struct CookieJar: Codable, Sendable {
    public private(set) var cookies: [SessionCookie]
    public init(cookies: [SessionCookie] = []) { self.cookies = cookies }

    public mutating func absorb(headers: [String: String], url: URL, now: Date) {
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        let raw = headers.first { $0.key.caseInsensitiveCompare("Set-Cookie") == .orderedSame }?.value ?? ""
        // Split only commas introducing another name=value, never the comma in Expires.
        let separator = try! NSRegularExpression(pattern: #",(?=\s*[^\s;,=]+\s*=)"#)
        let pieces = separator.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "\n").components(separatedBy: "\n")
        let cookies = parsed.map { cookie in
            let piece = pieces.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(cookie.name + "=") }
            let maxAge = piece?.components(separatedBy: ";").dropFirst().first { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("max-age=") }
            let seconds = maxAge.flatMap { TimeInterval($0.components(separatedBy: "=").last!.trimmingCharacters(in: .whitespaces)) }
            return SessionCookie(cookie, maximumAge: seconds, now: now)
        }
        merge(cookies, now: now)
    }

    public mutating func merge(_ incoming: [SessionCookie], now: Date = Date()) {
        cookies.removeAll { $0.expiresAt.map { $0 <= now } ?? false }
        for cookie in incoming {
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard ["lowiro.com", "webapi.lowiro.com", "arcaea.lowiro.com"].contains(domain),
                  !cookie.name.isEmpty, !cookie.name.contains("\n"), !cookie.value.contains("\n"),
                  !cookie.value.contains("\r"), cookie.path.hasPrefix("/") else { continue }
            cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            if cookie.expiresAt == nil || cookie.expiresAt! > now { cookies.append(cookie) }
        }
    }

    public func header(for url: URL, now: Date) -> String {
        cookies.filter { $0.matches(url, now: now) }.sorted {
            $0.path.count == $1.path.count ? $0.name < $1.name : $0.path.count > $1.path.count
        }.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    public func csrfToken(for url: URL, now: Date) -> String? {
        cookies.first { $0.name == "csrf" && $0.matches(url, now: now) }?.value.removingPercentEncoding
    }

    public func hasUsableCookies(now: Date) -> Bool {
        !header(for: URL(string: "https://webapi.lowiro.com/webapi/user/me")!, now: now).isEmpty
    }
}
