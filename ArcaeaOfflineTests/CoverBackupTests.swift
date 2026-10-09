import ArcaeaCore
import CryptoKit
import UIKit
import XCTest
@testable import ArcaeaOffline

@MainActor final class CoverBackupTests: XCTestCase {
    func testRoundTripPreservesBytesDifficultyKeysAndSharperExistingCover() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let future = LibraryResources.coverKey("wiki:test:2") + ".jpg"
        let beyond = LibraryResources.coverKey("wiki:test:3") + ".jpg"
        let official = LibraryResources.coverKey("official-art") + ".jpg"
        let small = try image(256), large = try image(512)
        try small.write(to: source.appendingPathComponent(future))
        try large.write(to: source.appendingPathComponent(beyond))
        try small.write(to: source.appendingPathComponent(official))
        try large.write(to: destination.appendingPathComponent(future))
        let backup = root.appendingPathComponent("covers.arcprobe-covers")
        XCTAssertEqual(try CoverBackup.export(from: source, to: backup), 3)
        let result = try CoverBackup.restore(from: backup, into: destination)
        XCTAssertEqual(result.imported, 2); XCTAssertEqual(result.retained, 1)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(future)), large)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(beyond)), large)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(official)), small)
    }

    func testRestoreInvalidatesCachedImageAndRevision() async throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let chart = ChartID(songID: "cover-restore-" + UUID().uuidString, difficulty: .future)
        let key = "wiki:\(chart.songID):\(chart.difficulty.rawValue)"
        let name = LibraryResources.coverKey(key) + ".jpg"
        let cached = try ArchiveLocation.directory().appendingPathComponent("covers").appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: cached) }
        let resources = LibraryResources.shared
        try resources.saveWikiCover(image(256), chart: chart)
        XCTAssertEqual(resources.image(for: key)?.cgImage?.width, 256)
        let revision = resources.revision
        let backup = root.appendingPathComponent("backup.arcprobe-covers")
        let original = try image(512)
        try archive([(name, original)]).write(to: backup)
        try await resources.restoreCoverBackup(from: backup)
        XCTAssertGreaterThan(resources.revision, revision)
        XCTAssertFalse(resources.managingCoverBackup)
        XCTAssertEqual(resources.image(for: key)?.cgImage?.width, 512)
        XCTAssertEqual(try Data(contentsOf: cached), original)
    }

    func testCorruptLateRecordInstallsNothing() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("destination")
        let backup = root.appendingPathComponent("bad.arcprobe-covers")
        var data = archive([(String(repeating: "a", count: 64) + ".jpg", try image(256)), (String(repeating: "b", count: 64) + ".jpg", Data("not an image".utf8))])
        try data.write(to: backup)
        XCTAssertThrowsError(try CoverBackup.restore(from: backup, into: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        data = archive([(String(repeating: "a", count: 64) + ".jpg", try image(256))]); data.removeLast()
        try data.write(to: backup)
        XCTAssertThrowsError(try CoverBackup.restore(from: backup, into: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testRejectsTraversalDuplicatesChecksumDamageAndTrailingBytes() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let backup = root.appendingPathComponent("bad.arcprobe-covers"), destination = root.appendingPathComponent("destination")
        let name = String(repeating: "a", count: 64) + ".jpg", bytes = try image(256)
        var checksumDamage = archive([(name, bytes)]); checksumDamage[84] ^= 1
        var trailing = archive([(name, bytes)]); trailing.append(0)
        var oversized = Data("APCOV001".utf8) + Data([0, 0, 0, 1]) + Data(name.utf8)
        oversized += Data([0, 128, 0, 1]) // 8 MiB + 1, rejected before allocation.
        for data in [archive([("../" + String(repeating: "a", count: 61) + ".jpg", bytes)]), archive([(name, bytes), (name, bytes)]), checksumDamage, trailing, oversized, Data("APCOV001".utf8) + Data([0xff, 0xff, 0xff, 0xff])] {
            try data.write(to: backup)
            XCTAssertThrowsError(try CoverBackup.restore(from: backup, into: destination))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testRejectsSymlinkSourceAndDestinationWithoutChangingTarget() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let name = String(repeating: "a", count: 64) + ".jpg", bytes = try image(256)
        let target = root.appendingPathComponent("target"); try bytes.write(to: target)
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent(name), withDestinationURL: target)
        XCTAssertThrowsError(try CoverBackup.export(from: source, to: root.appendingPathComponent("export")))
        let backup = root.appendingPathComponent("backup"); try archive([(name, bytes)]).write(to: backup)
        try FileManager.default.createSymbolicLink(at: destination.appendingPathComponent(name), withDestinationURL: target)
        XCTAssertThrowsError(try CoverBackup.restore(from: backup, into: destination))
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func image(_ size: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            UIColor.purple.setFill(); context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }.pngData())
    }
    private func archive(_ entries: [(String, Data)]) -> Data {
        func number(_ value: Int) -> Data { Data([UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]) }
        var data = Data("APCOV001".utf8) + number(entries.count)
        for (name, bytes) in entries { data += Data(name.utf8) + number(bytes.count) + Data(SHA256.hash(data: bytes)) + bytes }
        return data
    }
}
