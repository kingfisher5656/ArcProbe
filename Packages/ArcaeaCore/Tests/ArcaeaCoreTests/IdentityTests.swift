import XCTest
@testable import ArcaeaCore

final class IdentityTests: XCTestCase {
    func testInvalidDirectMillisecondsAreUnknownInsteadOfHugeDates() {
        XCTAssertNil(SourceTimestamp(value: Int64.max, unit: .milliseconds).milliseconds)
        XCTAssertNil(SourceTimestamp(value: Int64.max, unit: .milliseconds).date)
        XCTAssertNil(SourceTimestamp(value: -1, unit: .milliseconds).date)
    }

    func testSourceEventIdentityIgnoresPollTimeAndKeepsOwnerSeparate() throws {
        let values = ScoreValues(score: 9_800_000)
        let first = try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialRecent,
                                               values: values, firstSeenAt: testDate, eventID: "event-1")
        let repeated = try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialRecent,
                                                  values: values, firstSeenAt: testDate.addingTimeInterval(70), eventID: "event-1")
        let other = try ScoreObservation.remote(accountID: otherAccount, chartID: testChart, source: .officialRecent,
                                               values: values, firstSeenAt: testDate, eventID: "event-1")
        XCTAssertEqual(first.id, repeated.id)
        XCTAssertNotEqual(first.id, other.id)
        XCTAssertEqual(first.identityConfidence, .sourceEvent)
    }

    func testFallbackNormalizesUnitsRetainsPrecisionAndDistinguishesAttempts() throws {
        func remote(_ time: SourceTimestamp) throws -> ScoreObservation {
            try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialRecent,
                values: ScoreValues(score: 9_800_000, playedAt: time), firstSeenAt: testDate)
        }
        let seconds = try remote(SourceTimestamp(value: 1_800_000_000, unit: .seconds))
        let millis = try remote(SourceTimestamp(value: 1_800_000_000_000, unit: .milliseconds))
        let next = try remote(SourceTimestamp(value: 1_800_000_000_001, unit: .milliseconds))
        XCTAssertEqual(seconds.id, millis.id)
        XCTAssertNotEqual(seconds.id, next.id)
        XCTAssertEqual(seconds.values.playedAt?.unit, .seconds)
        XCTAssertEqual(millis.values.playedAt?.unit, .milliseconds)
        XCTAssertEqual(seconds.identityConfidence, .exactTimestampAndPayload)
    }

    func testMissingTimestampUsesStableUncertainIdentityAndRejectsOverflow() throws {
        let first = try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialRecent,
            values: ScoreValues(score: 9_800_000), firstSeenAt: testDate)
        let repeated = try ScoreObservation.remote(accountID: testAccount, chartID: testChart, source: .officialRecent,
            values: ScoreValues(score: 9_800_000), firstSeenAt: testDate.addingTimeInterval(70))
        XCTAssertEqual(first.id, repeated.id)
        XCTAssertEqual(first.identityConfidence, .payloadOnly)
        XCTAssertNil(first.values.playedAt)
        let overflow = SourceTimestamp(value: Int64.max, unit: .seconds)
        XCTAssertNil(overflow.milliseconds)
        XCTAssertNil(overflow.date)
        XCTAssertThrowsError(try ScoreObservation.remote(accountID: testAccount, chartID: testChart,
            source: .officialRecent, values: ScoreValues(score: 1, playedAt: overflow), firstSeenAt: testDate))
    }
}
