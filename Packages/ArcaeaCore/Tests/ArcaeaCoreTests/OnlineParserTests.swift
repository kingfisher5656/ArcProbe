import Foundation
import XCTest
@testable import ArcaeaCore

final class OnlineParserTests: XCTestCase {
    func testSubscriptionIsRemainingMillisecondsAndRecentNeedsNoSubscription() throws {
        let account = try OnlineParser.account(Data(#"{"success":true,"value":{"user_id":123,"name":"Example","arcaea_online_expire_ts":86400000,"recent_score":[]}}"#.utf8))
        XCTAssertEqual(account.profile.id, AccountID("online:123"))
        XCTAssertTrue(account.subscriptionActive)
        let unsubscribed = try OnlineParser.account(Data(#"{"value":{"user_id":123,"recent_score":[]}}"#.utf8))
        XCTAssertFalse(unsubscribed.subscriptionActive)
        XCTAssertEqual(unsubscribed.recentScores.count, 0)
    }

    func testRecentStableIdentityKeepsMissingJudgmentsUnknownAndFiltersTarget() throws {
        let payload = Data(#"{"value":{"friends":[{"user_id":8,"name":"Other","recent_score":[]},{"user_id":7,"name":"Target","rating":1100,"recent_score":[{"song_id":"test_song","difficulty":2,"score":9800000,"time_played":1700000000123,"clear_type":1}]}]}}"#.utf8)
        let first = try OnlineParser.friendRecent(payload, target: AccountID("online:7"), now: Date(timeIntervalSince1970: 1_700_000_010))
        let second = try OnlineParser.friendRecent(payload, target: AccountID("online:7"), now: Date(timeIntervalSince1970: 1_700_000_100))
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.first?.values.playedAt?.value, 1700000000123)
        XCTAssertNil(first.first?.values.judgments)
        XCTAssertEqual(first.first?.accountID, AccountID("online:7"))
        XCTAssertThrowsError(try OnlineParser.friendRecent(payload, target: AccountID("online:9"), now: Date()))
    }

    func testMalformedPageRejectsDifficultyMismatchAndFractionalScore() throws {
        let payload = Data(#"{"value":{"count":1,"scores":[{"song_id":"test","difficulty":1,"score":9800000}]}}"#.utf8)
        XCTAssertThrowsError(try OnlineParser.scorePage(payload, difficulty: .future, account: AccountID("online:7"), now: Date()))
        let fraction = Data(#"{"value":{"count":1,"scores":[{"song_id":"test","difficulty":2,"score":1.5}]}}"#.utf8)
        XCTAssertThrowsError(try OnlineParser.scorePage(fraction, difficulty: .future, account: AccountID("online:7"), now: Date()))
    }
    func testUnknownTimestampAndSentinelsRemainUnknownWhileMetadataSurvives() throws {
        let payload = Data(#"{"value":{"user_id":7,"recent_score":[{"song_id":"test","difficulty":3,"difficulty_alias":1,"score":9800000,"time_played":0,"health":-1,"modifier":-1,"title":{"en":"Example"},"bg":"test_bg"}]}}"#.utf8)
        let account = try OnlineParser.account(payload)
        XCTAssertNil(account.recentScores.first?.values.playedAt)
        XCTAssertNil(account.recentScores.first?.values.modifier)
        XCTAssertNil(account.recentScores.first?.values.health)
        XCTAssertEqual(account.recentScores.first?.identityConfidence, .payloadOnly)
        XCTAssertEqual(account.recentCharts.first?.difficultyLabel, "INS")
        XCTAssertEqual(account.recentCharts.first?.artworkIdentifier, "test_bg")
        let noRecent = Data(#"{"value":{"friends":[{"user_id":7,"recent_score":null}]}}"#.utf8)
        XCTAssertEqual(try OnlineParser.friendRecent(noRecent, target: AccountID("online:7"), now: Date()).count, 0)
        let bitmask = Data(#"{"value":{"user_id":7,"recent_score":[{"song_id":"test","difficulty":2,"score":9800000,"modifier":32768,"health":100}]}}"#.utf8)
        XCTAssertEqual(try OnlineParser.account(bitmask).recentScores.first?.values.modifier, 32768)
    }

}
