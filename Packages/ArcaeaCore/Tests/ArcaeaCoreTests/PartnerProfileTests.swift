import Foundation
import XCTest
@testable import ArcaeaCore

final class PartnerProfileTests: XCTestCase {
    private func icon(_ profile: AccountProfile) throws -> String? {
        (try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])?["partnerIcon"] as? String
    }
    func testFriendsSelectTargetPartnerEvenWithoutRecentScore() throws {
        let data = Data(#"{"value":{"friends":[{"user_id":8,"icon":"other"},{"user_id":7,"icon":"target_awaken","recent_score":[]}]}}"#.utf8)
        let payload = try OnlineParser.friendPayload(data, target: AccountID("online:7"), now: Date())
        XCTAssertEqual(try icon(payload.profile), "target_awaken")
        XCTAssertTrue(payload.observations.isEmpty)
    }
    func testOwnAccountUsesEquippedCharacterIconAndIgnoresUnsafeIdentifiers() throws {
        let data = Data(#"{"value":{"user_id":7,"character":12,"character_stats":[{"character_id":1,"icon":"other"},{"character_id":12,"icon":"equipped_uncapped"}]}}"#.utf8)
        XCTAssertEqual(try icon(OnlineParser.account(data).profile), "equipped_uncapped")
        let invalid = Data(#"{"value":{"user_id":7,"icon":"../../secret"}}"#.utf8)
        XCTAssertNil(try icon(OnlineParser.account(invalid).profile))
        XCTAssertEqual(try icon(OnlineParser.account(Data(#"{"value":{"user_id":7,"icon":0}}"#.utf8)).profile), "0")
        XCTAssertNil(try icon(OnlineParser.account(Data(#"{"value":{"user_id":7,"icon":true}}"#.utf8)).profile))
    }
    func testPartnerSurvivesSparseImportAndBackupThenChangesOnNextFetch() throws {
        let store = try ArchiveStore(url: temporaryArchiveURL())
        func profile(_ name: String) throws -> AccountProfile {
            try OnlineParser.account(Data("{\"value\":{\"user_id\":7,\"icon\":\"\(name)\"}}".utf8)).profile
        }
        _ = try store.apply(batch: ImportBatch(profile: profile("first")))
        _ = try store.apply(batch: ImportBatch(profile: AccountProfile(id: AccountID("online:7"))))
        XCTAssertEqual(try icon(XCTUnwrap(store.profiles().first)), "first")
        _ = try store.apply(batch: ImportBatch(profile: profile("second")))
        let restored = try ArchiveStore(url: temporaryArchiveURL())
        _ = try ArchiveBackup(store: restored).validateAndRestore(data: ArchiveBackup(store: store).export())
        XCTAssertEqual(try icon(XCTUnwrap(restored.profiles().first)), "second")
        let legacy = try JSONDecoder().decode(AccountProfile.self, from: Data(#"{"id":"legacy","displayName":"Legacy"}"#.utf8))
        XCTAssertNil(try icon(legacy))
    }
}
