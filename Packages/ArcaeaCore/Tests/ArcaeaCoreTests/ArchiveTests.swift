import XCTest
@testable import ArcaeaCore

final class ArchiveTests: XCTestCase {
    func testVersionOneCaptureMigrationCanReimportAndExportWithoutDuplicateEvidence() throws {
        let url = temporaryArchiveURL()
        let original = observation("legacy")
        do {
            let store = try ArchiveStore(url: url)
            _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [original]))
            try store.database.execute("DROP TABLE observation_captures")
            try store.database.execute("DROP TABLE IF EXISTS observation_aliases")
            try store.database.execute("PRAGMA user_version = 1")
        }
        let migrated = try ArchiveStore(url: url)
        _ = try migrated.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [original]))
        XCTAssertEqual(try migrated.sourceCaptures(observationID: original.id).count, 1)
        let restored = try ArchiveStore(url: temporaryArchiveURL())
        _ = try ArchiveBackup(store: restored).validateAndRestore(data: ArchiveBackup(store: migrated).export())
        XCTAssertEqual(try restored.sourceObservations(accountID: testAccount).count, 1)
    }

    func testCommittedArchiveSurvivesReopeningAndKeepsAccountsSeparate() throws {
        let url = temporaryArchiveURL()
        do {
            let store = try ArchiveStore(url: url)
            let receipt = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount),
                observations: [observation("a")], importedAt: testDate))
            XCTAssertEqual(receipt.addedCount, 1)
            _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: otherAccount),
                observations: [observation("b", score: 9_900_000, account: otherAccount)], importedAt: testDate))
        }
        let reopened = try ArchiveStore(url: url)
        XCTAssertEqual(try reopened.profiles().count, 2)
        XCTAssertEqual(try reopened.bestScores(accountID: testAccount).map(\.values.score), [9_800_000])
        XCTAssertEqual(try reopened.bestScores(accountID: otherAccount).map(\.values.score), [9_900_000])
        XCTAssertEqual(try reopened.receipts().count, 2)
    }

    func testMalformedLaterRecordRollsBackWholeBatchAndReceipt() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [observation("existing")]))
        XCTAssertThrowsError(try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount, displayName: "changed"),
            observations: [observation("valid"), observation("invalid", score: -1)])))
        XCTAssertEqual(try store.sourceObservations(accountID: testAccount).map(\.id.rawValue), ["existing"])
        XCTAssertNil(try store.profiles().first?.displayName)
        XCTAssertEqual(try store.receipts().count, 1)
    }

    func testWrongOwnerAndGlobalIDCollisionCannotCrossAccounts() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: testAccount), observations: [observation("shared")]))
        XCTAssertThrowsError(try store.apply(batch: ImportBatch(profile: AccountProfile(id: otherAccount),
            observations: [observation("wrong-owner")])))
        XCTAssertThrowsError(try store.apply(batch: ImportBatch(profile: AccountProfile(id: otherAccount),
            observations: [observation("shared", account: otherAccount)])))
        XCTAssertEqual(try store.profiles().map(\.id), [testAccount])
    }
}
