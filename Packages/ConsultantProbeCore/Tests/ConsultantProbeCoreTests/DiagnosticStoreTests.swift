import Foundation
import XCTest
@testable import ConsultantProbeCore

final class DiagnosticStoreTests: XCTestCase {
    func testReportAndBoundedHistorySurviveReopeningStore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = ProbeDiagnosticStore(directory: folder)
        try first.save(lines: (0..<55).map { "Event \($0)" }, report: "Connected: true\nRefresh: PASS")
        let reopened = ProbeDiagnosticStore(directory: folder)
        let history = try reopened.loadLines()
        XCTAssertEqual(history.count, 50)
        XCTAssertEqual(history.first, "Event 5")
        XCTAssertEqual(history.last, "Event 54")
        XCTAssertEqual(try String(contentsOf: reopened.reportURL, encoding: .utf8), "Connected: true\nRefresh: PASS")
    }
    func testMissingHistoryIsEmptyButCorruptHistoryIsReported() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProbeDiagnosticStore(directory: folder)
        XCTAssertEqual(try store.loadLines(), [])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: folder.appendingPathComponent("events.json"))
        XCTAssertThrowsError(try store.loadLines())
    }
}
