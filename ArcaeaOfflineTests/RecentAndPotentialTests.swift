import ArcaeaCore
import XCTest
@testable import ArcaeaOffline

@MainActor final class RecentAndPotentialTests: XCTestCase {
    private var calendar: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!; return calendar }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    private func play(_ id: String, at: Date?, seen: Date = Date(timeIntervalSince1970: 0)) -> EffectiveObservation {
        let original = ScoreObservation(id: ObservationID(id), accountID: AccountID("a"), chartID: ChartID(songID: "song", difficulty: .future), source: .officialRecent,
            values: ScoreValues(score: 9_900_000, playedAt: at.map { SourceTimestamp(value: Int64($0.timeIntervalSince1970), unit: .seconds) }), firstSeenAt: seen)
        return EffectiveObservation(original: original, values: original.values, isOverridden: false)
    }

    func testPlaysAreGroupedLikeABrowserHistory() {
        let now = date(2026, 11, 17, 9)
        let groups = RecentGroup.groups([
            play("month-a", at: date(2026, 11, 2)), play("unknown", at: nil), play("today-early", at: date(2026, 11, 17, 1)),
            play("yesterday", at: date(2026, 11, 16, 23)), play("today-late", at: date(2026, 11, 17, 8)), play("weekday", at: date(2026, 11, 13)),
            play("month-b", at: date(2026, 11, 9)), play("older", at: date(2026, 10, 30)), play("ahead", at: date(2026, 11, 18, 2))
        ], now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.kind), [.today, .yesterday, .day(date(2026, 11, 13, 0)), .month(date(2026, 11, 1, 0)), .month(date(2026, 10, 1, 0)), .unknown])
        XCTAssertEqual(groups[0].plays.map(\.original.id.rawValue), ["ahead", "today-late", "today-early"], "Newest first; a clock running ahead stays in Today")
        XCTAssertEqual(groups[3].plays.map(\.original.id.rawValue), ["month-b", "month-a"])
        XCTAssertEqual(groups.map(\.opensByDefault), [true, true, false, false, false, false])
        XCTAssertEqual(groups.map(\.isSingleDay), [true, true, true, false, false, false])
    }

    func testOneSavedPointStillGetsAnAxisTheRightWayUp() {
        let values = PotentialViewport.valueDomain([12.5])
        XCTAssertLessThan(values.lowerBound, 12.5); XCTAssertGreaterThan(values.upperBound, 12.5)
        XCTAssertEqual(PotentialViewport.valueDomain([]), 0...1)
        let now = date(2026, 11, 17)
        let range = PotentialViewport.dataRange(first: now, last: now, now: now)
        XCTAssertEqual(range.upperBound.timeIntervalSince(range.lowerBound), PotentialViewport.shortest)
    }

    func testPresetsEndNowAndZoomStaysInsideTheHistory() {
        let now = date(2026, 11, 17), first = date(2024, 11, 17)
        let viewport = PotentialViewport()
        viewport.load([.init(time: first, value: 10), .init(time: date(2026, 11, 10), value: 12), .init(time: now, value: 12.4)], now: now, range: .month)
        // Thirty days of data on screen, with the same small room on both sides.
        XCTAssertEqual(viewport.length * (1 - 2 * PotentialViewport.margin), 30 * 86_400, accuracy: 1)
        XCTAssertEqual(viewport.end.timeIntervalSince(now), viewport.length * PotentialViewport.margin, accuracy: 1)
        // The value axis follows what is on screen (12 and 12.4, plus the point before them), not the whole history.
        XCTAssertLessThan(viewport.values.upperBound, 13)
        viewport.show(.fiveYears)
        XCTAssertEqual(viewport.length * (1 - 2 * PotentialViewport.margin), now.timeIntervalSince(first), accuracy: 1, "No more than the history that exists")
        viewport.zoom(to: 10, around: 0.5)
        XCTAssertEqual(viewport.length, PotentialViewport.shortest)
        viewport.zoom(to: 1e12, around: 0)
        XCTAssertEqual(viewport.position, viewport.domain.lowerBound)
        XCTAssertEqual(viewport.end, viewport.domain.upperBound)
    }
}
