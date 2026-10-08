import XCTest
@testable import ArcaeaCore

final class HistoryTests: XCTestCase {
    func testEmptyMovingWindowRetainsOldOfficialPointsAndSeparateLocalEstimates() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let old = PotentialPoint(accountID: testAccount, sourceID: "old-official",
            timestamp: SourceTimestamp(value: 1_600_000_000, unit: .seconds),
            value: PotentialValue(rawValue: 12_345, decimalPlaces: 3), firstSeenAt: testDate)
        let estimate = PotentialPoint(accountID: testAccount, sourceID: "estimate",
            timestamp: SourceTimestamp(value: 1_800_000_000_001, unit: .milliseconds),
            value: PotentialValue(rawValue: 12_345_678, decimalPlaces: 6), series: .localEstimate, firstSeenAt: testDate)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), potentialPoints: [old, estimate]))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), potentialPoints: []))
        XCTAssertEqual(try store.potentialHistory(accountID: testAccount), [old])
        XCTAssertEqual(try store.potentialHistory(accountID: testAccount, series: .localEstimate), [estimate])
        _ = try store.applyManual(change: .add(observation("manual", score: 1, source: .manual)))
        XCTAssertEqual(try store.potentialHistory(accountID: testAccount), [old])
        XCTAssertTrue(try store.potentialHistory(accountID: otherAccount).isEmpty)
    }

    func testHistoryDedupNormalizesUnitsWithoutLosingOriginalPrecisionAndConflictsRollBack() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        let point = PotentialPoint(accountID: testAccount, sourceID: "point",
            timestamp: SourceTimestamp(value: 1_800_000_000, unit: .seconds),
            value: PotentialValue(rawValue: 12_300, decimalPlaces: 3), firstSeenAt: testDate)
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), potentialPoints: [point]))
        let same = PotentialPoint(accountID: testAccount, sourceID: "point",
            timestamp: SourceTimestamp(value: 1_800_000_000_000, unit: .milliseconds),
            value: PotentialValue(rawValue: 123_000, decimalPlaces: 4), firstSeenAt: testDate.addingTimeInterval(70))
        let receipt = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), potentialPoints: [same]))
        XCTAssertEqual(receipt.addedPotentialCount, 0)
        XCTAssertEqual(try store.potentialHistory(accountID: testAccount), [point])
        let conflict = PotentialPoint(accountID: testAccount, sourceID: "point", timestamp: point.timestamp,
            value: PotentialValue(rawValue: 12_301, decimalPlaces: 3), firstSeenAt: testDate)
        XCTAssertThrowsError(try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount),
            observations: [observation("would-roll-back")], potentialPoints: [conflict])))
        XCTAssertTrue(try store.sourceObservations(accountID: testAccount).isEmpty)
        XCTAssertEqual(try store.potentialHistory(accountID: testAccount), [point])
    }
}
