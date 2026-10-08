import Foundation
import XCTest
@testable import ArcaeaCore

final class SessionTests: XCTestCase {
    func testCookieRotationExpiryPathAndSecureMatching() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let origin = URL(string: "https://webapi.lowiro.com/auth/login")!
        var jar = CookieJar()
        jar.absorb(headers: ["Set-Cookie": "session=first; Path=/; Secure; HttpOnly"], url: origin, now: now)
        jar.absorb(headers: ["Set-Cookie": "session=second; Path=/; Secure; HttpOnly"], url: origin, now: now)
        jar.absorb(headers: ["Set-Cookie": "csrf=a%20b; Path=/webapi; Secure"], url: origin, now: now)
        XCTAssertEqual(jar.header(for: URL(string: "https://webapi.lowiro.com/webapi/user/me")!, now: now), "csrf=a%20b; session=second")
        XCTAssertEqual(jar.csrfToken(for: URL(string: "https://webapi.lowiro.com/webapi/user/me")!, now: now), "a b")
        XCTAssertEqual(jar.header(for: URL(string: "https://arcaea.lowiro.com/webapi/user/me")!, now: now), "")
        XCTAssertEqual(jar.header(for: URL(string: "http://webapi.lowiro.com/webapi/user/me")!, now: now), "")
        jar.absorb(headers: ["Set-Cookie": "session=gone; Max-Age=0; Path=/; Secure"], url: origin, now: now)
        XCTAssertEqual(jar.header(for: origin, now: now), "")
    }

    func testRequestPolicyRejectsNonOfficialURLsAndParsesRetryAfter() throws {
        XCTAssertThrowsError(try RequestPolicy.validate(URL(string: "https://webapi.lowiro.com.evil.example/webapi/user/me")!))
        XCTAssertThrowsError(try RequestPolicy.validate(URL(string: "http://webapi.lowiro.com/webapi/user/me")!))
        XCTAssertThrowsError(try RequestPolicy.validate(URL(string: "https://webapi.lowiro.com/webapi/user/me?unknown=1")!))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(RequestPolicy.retryDate("120", now: now), now.addingTimeInterval(120))
        XCTAssertEqual(RequestPolicy.retryDate("invalid", now: now), now.addingTimeInterval(60))
        XCTAssertEqual(RequestPolicy.retryDate("Wed, 15 Nov 2023 00:00:00 GMT", now: now).timeIntervalSince1970, 1_700_006_400)
    }

    func testResponseClassificationDoesNotRefreshChallenges() throws {
        let now = Date()
        XCTAssertThrowsError(try RequestPolicy.validateResponse(HTTPResponse(status: 403, headers: ["Content-Type": "application/json"], body: Data()), now: now)) { XCTAssertEqual($0 as? OnlineError, .interactionRequired) }
        XCTAssertThrowsError(try RequestPolicy.validateResponse(HTTPResponse(status: 200, headers: ["Content-Type": "text/html"], body: Data()), now: now)) { XCTAssertEqual($0 as? OnlineError, .interactionRequired) }
        XCTAssertThrowsError(try RequestPolicy.validateResponse(HTTPResponse(status: 401, headers: [:], body: Data()), now: now)) { XCTAssertEqual($0 as? OnlineError, .expiredSession) }
    }
}
