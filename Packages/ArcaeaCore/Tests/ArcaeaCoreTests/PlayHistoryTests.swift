import XCTest
@testable import ArcaeaCore

final class PlayHistoryTests: XCTestCase {
    private func play(_ id: String, _ score: Int, at: Int64?, seen: TimeInterval = 1_800_000_000, chart: ChartID = testChart) -> EffectiveObservation {
        let original = ScoreObservation(id: ObservationID(id), accountID: testAccount, chartID: chart, source: at == nil ? .gameData : .officialRecent,
            values: ScoreValues(score: score, playedAt: at.map { SourceTimestamp(value: $0, unit: .seconds) }), firstSeenAt: Date(timeIntervalSince1970: seen))
        return EffectiveObservation(original: original, values: original.values, isOverridden: false)
    }

    func testEachPlayIsComparedWithTheBestBeforeIt() {
        let changes = PlayHistory.changes([
            play("c", 9_900_000, at: 300), play("a", 9_800_000, at: 100), play("b", 9_750_000, at: 200), play("d", 9_900_000, at: 400)
        ])
        XCTAssertEqual(changes[ObservationID("a")], .first)
        XCTAssertEqual(changes[ObservationID("b")], .below(by: 50_000))
        XCTAssertEqual(changes[ObservationID("c")], .newBest(by: 100_000))
        XCTAssertEqual(changes[ObservationID("d")], .tie)
    }

    func testChartsAreKeptApart() {
        let other = ChartID(songID: "other", difficulty: .beyond)
        let changes = PlayHistory.changes([play("a", 9_900_000, at: 100), play("b", 9_000_000, at: 200, chart: other)])
        XCTAssertEqual(changes[ObservationID("b")], .first)
    }

    func testAnEditedScoreIsTheOneCompared() {
        let earlier = play("a", 9_800_000, at: 100)
        let edited = EffectiveObservation(original: earlier.original, values: ScoreValues(score: 9_600_000, playedAt: earlier.values.playedAt), isOverridden: true)
        XCTAssertEqual(PlayHistory.changes([edited, play("b", 9_700_000, at: 200)])[ObservationID("b")], .newBest(by: 100_000))
    }

    func testAPlayWithoutADateSeenEarlierCountsAsEarlier() {
        // A game-folder score was saved at 1000; a play made at 2000 came after it.
        let changes = PlayHistory.changes([play("folder", 9_900_000, at: nil, seen: 1_000), play("later", 9_950_000, at: 2_000)])
        XCTAssertNil(changes[ObservationID("folder")], "A play without a date has no place in the order")
        XCTAssertEqual(changes[ObservationID("later")], .newBest(by: 50_000))
    }

    func testNothingIsClaimedWhenTheOrderIsUnknown() {
        // The undated score was first seen after the dated play: it may have been made before or after it.
        let changes = PlayHistory.changes([play("early", 9_800_000, at: 500), play("folder", 9_900_000, at: nil, seen: 1_000), play("later", 9_950_000, at: 2_000)])
        XCTAssertNil(changes[ObservationID("early")])
        XCTAssertEqual(changes[ObservationID("later")], .newBest(by: 50_000))
    }
}
