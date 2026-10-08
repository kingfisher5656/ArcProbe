import XCTest
@testable import ArcaeaCore

final class RatingTests: XCTestCase {
    func testObservationRankingProjectsOneCoherentBestAndRejectsMixedOwnersOrInvalidUnratedScores() throws {
        let calculator = RatingCalculator(catalog: ChartCatalog(charts: [ChartMetadata(id: testChart, constant: ChartConstant(tenths: 100), provenance: "synthetic")]))
        let high = observation("high", score: 9_900_000, judgments: Judgments(pure: 900, far: 10), clear: .normal)
        let low = observation("low", score: 9_800_000, judgments: Judgments(pure: 880, far: 30), clear: .fullRecall)
        let snapshot = try calculator.rank(observations: [high, low])
        XCTAssertEqual(snapshot.rows.count, 1)
        XCTAssertEqual(snapshot.rows.first?.best.values.judgments, high.values.judgments)
        XCTAssertEqual(snapshot.rows.first?.ratingUnits, 7_020_000)
        XCTAssertEqual(snapshot.potentialUnits, 234_000)
        XCTAssertThrowsError(try calculator.rank(observations: [high, observation("other", account: otherAccount)]))
        XCTAssertThrowsError(try calculator.rank(observations: [observation("bad-unrated", score: -1, chart: ChartID(songID: "unknown", difficulty: .past))]))
    }

    func testExactlyFiftyRankedChartsContributeWithTopTenDoubleWeight() throws {
        let charts = (1...51).map { ChartID(songID: "chart-\($0)", difficulty: .future) }
        let calculator = RatingCalculator(catalog: ChartCatalog(charts: charts.map { ChartMetadata(id: $0, constant: ChartConstant(tenths: 100), provenance: "synthetic") }))
        let snapshot = try calculator.rank(observations: charts.enumerated().map { observation("id-\($0.offset)", score: 10_000_000, chart: $0.element, clear: .normal) })
        XCTAssertEqual(snapshot.potentialUnits, 7_320_000)
        XCTAssertEqual(snapshot.best50AverageUnits, 7_320_000)
        XCTAssertEqual(snapshot.rows.count, 51)
        XCTAssertEqual(snapshot.rows.last?.rank, 51)
    }

    func testBundledDatedMetadataKeepsAliasesIndependentOfPlayerRecords() throws {
        let catalog = try ChartCatalog.bundled()
        XCTAssertEqual(catalog[ChartID(songID: "sayonarahatsukoi", difficulty: .past)]?.constant?.tenths, 15)
        XCTAssertEqual(catalog[ChartID(songID: "cataclysmcry", difficulty: .beyond)]?.displayDifficulty, "INS")
        XCTAssertNil(catalog[ChartID(songID: "not-in-catalog", difficulty: .future)])
    }

    func testExactScoreBoundariesAndClearBonuses() throws {
        let constant = ChartConstant(tenths: 100)
        let cases: [(Int, Int64)] = [
            (0, 0), (9_499_999, 5_999_998), (9_500_000, 6_000_000),
            (9_799_999, 6_599_998), (9_800_000, 6_600_000),
            (9_999_999, 7_199_997), (10_000_000, 7_200_000), (10_001_000, 7_200_000)
        ]
        for (score, expected) in cases {
            XCTAssertEqual(try RatingCalculator.base(constant: constant, score: score), expected, "score \(score)")
        }
        for clear in ClearType.allCases {
            let expected: Int64 = [1, 2, 3, 5].contains(clear.rawValue) ? 7_320_000 : 7_200_000
            XCTAssertEqual(try RatingCalculator.play(constant: constant, score: 10_000_000, clear: clear), expected)
        }
        XCTAssertEqual(try RatingCalculator.play(constant: constant, score: 10_000_000, clear: nil), 7_200_000)
    }

    func testSparseRankingUsesZeroForMissingSlotsAndSkipsOutdatedConstants() throws {
        let known = ChartID(songID: "known", difficulty: .future)
        let old = ChartID(songID: "old", difficulty: .beyond)
        let missing = ChartID(songID: "missing", difficulty: .eternal)
        let catalog = ChartCatalog(charts: [
            ChartMetadata(id: known, constant: ChartConstant(tenths: 100), provenance: "test"),
            ChartMetadata(id: old, constant: ChartConstant(tenths: 120), isOutdated: true, provenance: "test")
        ])
        let best = [known, old, missing].map { chart in
            BestScore(accountID: AccountID("a"), chartID: chart, observationID: nil,
                      values: ScoreValues(score: 10_000_000), bestClear: .normal,
                      isOverridden: false, isBestCorrection: false)
        }
        let snapshot = try RatingCalculator(catalog: catalog).rank(bestScores: best)
        XCTAssertEqual(snapshot.rows.first?.best.chartID, known)
        XCTAssertEqual(snapshot.rows.first?.ratingUnits, 7_320_000)
        XCTAssertEqual(snapshot.potentialUnits, 244_000)
        XCTAssertEqual(snapshot.best50AverageUnits, 146_400)
        XCTAssertEqual(snapshot.missingConstants, 2)
        XCTAssertEqual(snapshot.rows.compactMap(\.rank), [1])
        XCTAssertTrue(snapshot.isEstimate)
        XCTAssertEqual(RatingCalculator.display(snapshot.potentialUnits), "0.406")
        XCTAssertEqual(RatingCalculator.display(7_320_300, rounded: true), "12.201")
    }
}
