import XCTest
@testable import ArcaeaOffline

final class HistorySamplerTests: XCTestCase {
    private struct Point { let index: Int; let value: Double }
    func testLargeSeriesStaysBoundedAndRetainsEndpointsAndExtrema() {
        let input = (0..<100_000).map { Point(index: $0, value: $0 == 54321 ? 99 : $0 == 34567 ? -99 : 12) }
        let sampled = HistorySampler.sample(input, budget: 1500, value: { $0.value })
        XCTAssertLessThanOrEqual(sampled.count, 1500)
        XCTAssertEqual(sampled.first?.index, 0)
        XCTAssertEqual(sampled.last?.index, 99999)
        XCTAssertTrue(sampled.contains { $0.index == 54321 })
        XCTAssertTrue(sampled.contains { $0.index == 34567 })
        XCTAssertEqual(sampled.map(\.index), sampled.map(\.index).sorted())
    }
    func testInspectionFindsNearestOriginalObservationRatherThanSampledNeighbor() {
        let points = (0..<100_000).map { Point(index: $0, value: 12) }
        XCTAssertEqual(HistorySampler.nearest(points, reference: 54321.25, key: { Double($0.index) })?.index, 54321)
        XCTAssertEqual(HistorySampler.nearest(points, reference: -1, key: { Double($0.index) })?.index, 0)
        XCTAssertEqual(HistorySampler.nearest(points, reference: 100_001, key: { Double($0.index) })?.index, 99999)
    }
    func testSmallSeriesRetainsEveryObservation() {
        let input = [Point(index: 1, value: 12.01), Point(index: 2, value: 11.99)]
        XCTAssertEqual(HistorySampler.sample(input, budget: 1500, value: { $0.value }).map(\.index), [1, 2])
    }
}
