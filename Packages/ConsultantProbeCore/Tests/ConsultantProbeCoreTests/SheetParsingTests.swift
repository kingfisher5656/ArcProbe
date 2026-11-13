import XCTest
@testable import ConsultantProbeCore

final class SheetParsingTests: XCTestCase {
    func testPickerAcceptsOneIDAndRejectsMissingMultipleOrPath() throws {
        XCTAssertEqual(try SheetParsing.selectedID("abc_123-XYZ"), "abc_123-XYZ")
        for raw in ["", "one,two", "../score", "a?x=1", "a b"] {
            XCTAssertThrowsError(try SheetParsing.selectedID(raw))
        }
    }
    func testMetadataDiscoversBracketedTitleWithoutRelyingOnExcelSanitization() throws {
        let json = Data(##"{"spreadsheetId":"abc","properties":{"title":"Private sheet"},"sheets":[{"properties":{"title":"점수 입력 [Score Input]"}},{"properties":{"title":"DataM"}},{"properties":{"title":"ScoreData"}}]}"##.utf8)
        let metadata = try SheetParsing.metadata(json)
        XCTAssertEqual(metadata.inputTab, "점수 입력 [Score Input]")
        XCTAssertEqual(SheetParsing.range(tab: "Player's [Score Input]", cells: "H5"), "'Player''s [Score Input]'!H5")
    }

    private func calculated(identity: [Any] = ["Sayonara Hatsukoi [PST]", "", "Sayonara Hatsukoi", "PST"], decoded: Any = 0, rating: Any = 0) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["valueRanges": [
            ["values": [identity]], ["values": [[decoded]]],
            ["values": [[decoded, 0, rating, 0, 0, 0, 0, 0, 0, -0.01822]]]
        ]])
    }
    private func score(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["values": [[value]]])
    }
    func testParserAllowsFormulaErrorsDownstreamSoRecoveryCanStillReadInput() throws {
        let result = try SheetParsing.snapshot(input: score(9975813), calculated: calculated(decoded: 9975813, rating: "#ERROR!"))
        XCTAssertEqual(result.input, 9_975_813)
        XCTAssertNil(result.rating)
    }
    func testFormulaInInputCellIsRejectedEvenIfEvaluatedValueIsZero() throws {
        XCTAssertThrowsError(try SheetParsing.snapshot(input: score("=0"), calculated: calculated())) {
            guard case SheetReadError.inputCell(.score, .formula) = $0 else { return XCTFail("Expected the raw-score formula guard") }
        }
    }
    func testSnapshotFailureIdentifiesCellAndTypeWithoutLeakingContents() throws {
        let identityCases: [(Int, Any, String)] = [
            (0, true, "A5 / boolean"),
            (2, "private song title", "C5 / text"),
            (3, "=PRIVATE_DIFFICULTY()", "D5 / formula")
        ]
        for (index, value, expectedLocation) in identityCases {
            var row: [Any] = ["Sayonara Hatsukoi [PST]", "", "Sayonara Hatsukoi", "PST"]
            row[index] = value
            XCTAssertThrowsError(try SheetParsing.snapshot(input: score(0), calculated: calculated(identity: row))) { error in
                XCTAssertTrue(error.localizedDescription.contains(expectedLocation), error.localizedDescription)
                XCTAssertFalse(error.localizedDescription.lowercased().contains("private"))
            }
        }
        let scoreCases: [(Any, String)] = [("private score", "text"), ("=PRIVATE_SCORE()", "formula"), (true, "boolean"), (NSNull(), "missing")]
        for (value, kind) in scoreCases {
            XCTAssertThrowsError(try SheetParsing.snapshot(input: score(value), calculated: calculated())) { error in
                XCTAssertTrue(error.localizedDescription.contains("H5 / " + kind), error.localizedDescription)
                XCTAssertFalse(error.localizedDescription.lowercased().contains("private"))
            }
        }
    }
    func testMissingInputAndCalculatedRangesHaveDistinctDiagnostics() throws {
        XCTAssertThrowsError(try SheetParsing.snapshot(input: Data("{}".utf8), calculated: calculated())) {
            XCTAssertTrue($0.localizedDescription.contains("input row missing"))
        }
        XCTAssertThrowsError(try SheetParsing.snapshot(input: score(0), calculated: Data("{}".utf8))) {
            XCTAssertTrue($0.localizedDescription.contains("calculated ranges missing"))
        }
    }
    func testTitleCharacterDiagnosticIsOptInAndDoesNotIncludeOtherCells() throws {
        let values = try calculated(identity: ["private identity", "", "Sayonara\u{00A0}Hatsukoi", "private difficulty"])
        XCTAssertThrowsError(try SheetParsing.snapshot(input: score(7654321), calculated: values)) {
            XCTAssertFalse($0.localizedDescription.contains("U+00A0"))
        }
        XCTAssertThrowsError(try SheetParsing.snapshot(input: score(7654321), calculated: values, includeTitleCharacters: true)) {
            XCTAssertTrue($0.localizedDescription.contains("U+00A0"))
            XCTAssertFalse($0.localizedDescription.contains("private identity"))
            XCTAssertFalse($0.localizedDescription.contains("private difficulty"))
            XCTAssertFalse($0.localizedDescription.contains("7654321"))
        }
    }
    func testTitleCharacterDiagnosticIsBounded() throws {
        let values = try calculated(identity: ["identity", "", String(repeating: "x", count: 10_000), "PST"])
        XCTAssertThrowsError(try SheetParsing.snapshot(input: score(0), calculated: values, includeTitleCharacters: true)) {
            XCTAssertTrue($0.localizedDescription.contains("10000"))
            XCTAssertLessThan($0.localizedDescription.count, 1_000)
        }
    }
}
