import Foundation

/// A production write was never submitted, or Google explicitly rejected it.
public struct SheetWriteNotSent: Error {
    public let underlying: any Error
    public init(underlying: any Error) { self.underlying = underlying }
}

import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SheetMetadata: Sendable {
    public let id: String
    public let title: String
    public let inputTab: String?
}
/// General diagnostics use fixed identifiers. Opt-in fixture inspection records only C5 character codes.
public enum SheetReadError: Error, LocalizedError {
    public enum Cell: String, Sendable { case identity = "A5", title = "C5", difficulty = "D5", score = "H5" }
    public enum Kind: String, Sendable { case missing, boolean, number, formula, text, other
        fileprivate init(_ value: Any?) {
            if value == nil || value is NSNull { self = .missing }
            else if let number = value as? NSNumber {
                self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .boolean : .number
            } else if let text = value as? String { self = text.hasPrefix("=") ? .formula : .text }
            else { self = .other }
        }
    }
    case inputRowMissing, inputCell(Cell, Kind), calculatedRangesMissing
    case titleCharacters(scalars: [UInt32], total: Int)
    public var errorDescription: String? {
        switch self {
        case .inputRowMissing: "Test sheet read stopped: input row missing. Check any pending recovery before retrying."
        case let .inputCell(cell, kind): "Test sheet read stopped: \(cell.rawValue) / \(kind.rawValue) does not match the expected fixture. Cell contents were not recorded."
        case let .titleCharacters(scalars, total):
            "Test sheet read stopped: C5 / text differs. Unicode scalar count: \(total); first96: " + scalars.map { String(format: "U+%04X", $0) }.joined(separator: " ")
        case .calculatedRangesMissing: "Test sheet read stopped: calculated ranges missing or unexpected. Check any pending recovery before retrying."
        }
    }
}

public enum SheetParsing {
    public static func selectedID(_ raw: String) throws -> String {
        guard !raw.isEmpty, raw.count <= 200,
              raw.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw ProbeError.invalidSelection
        }
        return raw
    }
    public static func range(tab: String, cells: String) -> String { "'\(tab.replacingOccurrences(of: "'", with: "''"))'!\(cells)" }
    public static func metadata(_ data: Data) throws -> SheetMetadata {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let id = object?["spreadsheetId"] as? String,
              let title = (object?["properties"] as? [String: Any])?["title"] as? String,
              let sheets = object?["sheets"] as? [[String: Any]] else { throw ProbeError.unsupported }
        let titles = sheets.compactMap { ($0["properties"] as? [String: Any])?["title"] as? String }
        let inputs = titles.filter { $0.contains("[Score Input]") }
        return SheetMetadata(id: try selectedID(id), title: title,
            inputTab: inputs.count == 1 && titles.contains("DataM") && titles.contains("ScoreData") ? inputs[0] : nil)
    }
    public static func snapshot(input: Data, calculated: Data, includeTitleCharacters: Bool = false) throws -> ProbeSnapshot {
        let raw = try JSONSerialization.jsonObject(with: input) as? [String: Any]
        guard let scoreRow = (raw?["values"] as? [[Any]])?.first, !scoreRow.isEmpty else { throw SheetReadError.inputRowMissing }
        // Read only H5 in FORMULA mode: never replace a formula or a text score.
        guard let inputNumber = scoreRow[0] as? NSNumber, CFGetTypeID(inputNumber) != CFBooleanGetTypeID() else {
            throw SheetReadError.inputCell(.score, .init(scoreRow[0]))
        }
        let result = try JSONSerialization.jsonObject(with: calculated) as? [String: Any]
        guard let ranges = result?["valueRanges"] as? [[String: Any]], ranges.count == 3 else { throw SheetReadError.calculatedRangesMissing }
        // Chart labels can be spill results. FORMULA mode returned an empty C5 on the real sheet.
        // A5:D5 comes from the same UNFORMATTED_VALUE batch as the downstream calculations.
        let row = (ranges[0]["values"] as? [[Any]])?.first ?? []
        func cell(_ index: Int) -> Any? { row.indices.contains(index) ? row[index] : nil }
        guard let identity = cell(0) as? String else { throw SheetReadError.inputCell(.identity, .init(cell(0))) }
        guard cell(2) as? String == "Sayonara Hatsukoi" else {
            if includeTitleCharacters, let title = cell(2) as? String, !title.hasPrefix("=") {
                throw SheetReadError.titleCharacters(scalars: Array(title.unicodeScalars.prefix(96).map(\.value)), total: title.unicodeScalars.count)
            }
            throw SheetReadError.inputCell(.title, .init(cell(2)))
        }
        guard cell(3) as? String == "PST" else { throw SheetReadError.inputCell(.difficulty, .init(cell(3))) }
        let scoreData = (ranges[1]["values"] as? [[Any]])?.first ?? []
        let computed = (ranges[2]["values"] as? [[Any]])?.first ?? []
        func number(_ row: [Any], _ index: Int) -> Double? {
            guard row.indices.contains(index) else { return nil }
            if let n = row[index] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue.isFinite ? n.doubleValue : nil }
            if let s = row[index] as? String, let n = Double(s), n.isFinite { return n }
            return nil
        }
        let decoded = number(computed, 0)
        return ProbeSnapshot(input: inputNumber.doubleValue,
            decoded: number(scoreData, 0) == decoded ? decoded : nil,
            rating: number(computed, 2), priority: number(computed, 9), identity: identity)
    }
}

public struct SheetHTTPError: Error, LocalizedError, Sendable {
    public let status: Int
    public let retryAfter: String?
    public var errorDescription: String? {
        switch status {
        case 401: "Google authorization expired. Connect again, then retry recovery if needed."
        case 403: "Google denied access. Check the selected account, file permissions and that Sheets / Drive / Picker APIs are enabled."
        case 404: "Google could not access the selected file. Select it again through Google Picker."
        case 429: "Google rate limited this request. Wait \(retryAfter ?? "at least 60") seconds before retrying."
        default: "Google Sheets request failed (HTTP \(status)). Retry later; pending recovery is preserved."
        }
    }
}
@MainActor public final class GoogleSheetAPI: ProbeSheet {
    public typealias Transport = @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let token: @MainActor () async throws -> String
    private let transport: Transport
    public init(token: @escaping @MainActor () async throws -> String, transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }) { self.token = token; self.transport = transport }
    public func metadata(fileID: String) async throws -> SheetMetadata {
        try SheetParsing.metadata(await request(fileID: fileID, query: [URLQueryItem(name: "fields", value: "spreadsheetId,properties(title),sheets(properties(title))")]))
    }
    public func snapshot(fileID: String, inputTab: String) async throws -> ProbeSnapshot {
        let inputRange = SheetParsing.range(tab: inputTab, cells: "H5")
        let raw = try await request(fileID: fileID, suffix: "/values/" + inputRange, query: [URLQueryItem(name: "valueRenderOption", value: "FORMULA")])
        let calculated = try await request(fileID: fileID, suffix: "/values:batchGet", query: [
            URLQueryItem(name: "ranges", value: SheetParsing.range(tab: inputTab, cells: "A5:D5")),
            URLQueryItem(name: "ranges", value: "'ScoreData'!C2"), URLQueryItem(name: "ranges", value: "'DataM'!J3:S3"),
            URLQueryItem(name: "valueRenderOption", value: "UNFORMATTED_VALUE")])
        return try SheetParsing.snapshot(input: raw, calculated: calculated, includeTitleCharacters: fileID == ProbeRunner.testFileID)
    }
    /// Read-only production import source. DataM contains decoded mobile scores, including sheet shorthand.
    public func scoreImportData(fileID: String) async throws -> Data {
        let data = try await request(fileID: fileID, suffix: "/values:batchGet", query: [
            URLQueryItem(name: "ranges", value: "'DevSettings'!C4"),
            URLQueryItem(name: "ranges", value: "'DataM'!G2:J"),
            URLQueryItem(name: "valueRenderOption", value: "UNFORMATTED_VALUE")])
        guard data.count <= 8 * 1024 * 1024 else { throw ProbeError.unsupported }
        return data
    }
    /// Stable English identities (A), localized join keys (B), and decoded mobile scores.
    /// Raw H is read separately so formulas are protected even when their result is numeric.
    public func scoreExportData(fileID: String, inputTab: String) async throws -> (evaluated: Data, raw: Data) {
        guard inputTab.contains("[Score Input]") else { throw ProbeError.unsupported }
        let evaluated = try await request(fileID: fileID, suffix: "/values:batchGet", query: [
            URLQueryItem(name: "ranges", value: "'DevSettings'!C4"),
            URLQueryItem(name: "ranges", value: "'DataM'!G2:J"),
            URLQueryItem(name: "ranges", value: SheetParsing.range(tab: inputTab, cells: "A5:D")),
            URLQueryItem(name: "ranges", value: SheetParsing.range(tab: inputTab, cells: "H4:I4")),
            URLQueryItem(name: "valueRenderOption", value: "UNFORMATTED_VALUE")])
        let raw = try await request(fileID: fileID, suffix: "/values/" + SheetParsing.range(tab: inputTab, cells: "H4:H"),
                                    query: [URLQueryItem(name: "valueRenderOption", value: "FORMULA")])
        guard evaluated.count <= 8 * 1024 * 1024, raw.count <= 2 * 1024 * 1024 else { throw ProbeError.unsupported }
        return (evaluated, raw)
    }
    /// Production sends are planned, confirmed and journaled by ConsultantExportService.
    /// This transport can only change explicit mobile input cells; never formulas or whole ranges.
    public func writeMobileScores(fileID: String, inputTab: String, scores: [Int: Int]) async throws {
        guard inputTab.contains("[Score Input]"), !scores.isEmpty, scores.count <= 10_000,
              scores.allSatisfy({ (5...10_004).contains($0.key) && (0...10_100_000).contains($0.value) }) else { throw ProbeError.restricted }
        let values: [[String: Any]] = scores.keys.sorted().map { row in
            ["range": SheetParsing.range(tab: inputTab, cells: "H\(row)"), "values": [[scores[row]!]]]
        }
        let body = try JSONSerialization.data(withJSONObject: ["valueInputOption": "RAW", "data": values])
        _ = try await request(fileID: fileID, suffix: "/values:batchUpdate", body: body, reportUnsentWrite: true)
    }
    public func write(fileID: String, inputTab: String, value: Double) async throws {
        guard fileID == ProbeRunner.testFileID, value == 0 || value == ProbeRunner.testScore else { throw ProbeError.restricted }
        let range = SheetParsing.range(tab: inputTab, cells: "H5")
        let body = try JSONSerialization.data(withJSONObject: ["valueInputOption": "RAW", "data": [["range": range, "values": [[value]]]]])
        _ = try await request(fileID: fileID, suffix: "/values:batchUpdate", body: body)
    }
    private func request(fileID: String, suffix: String = "", query: [URLQueryItem] = [], body: Data? = nil, reportUnsentWrite: Bool = false) async throws -> Data {
        let request: URLRequest
        do {
            try Task.checkCancellation()
            let id = try SheetParsing.selectedID(fileID)
            var components = URLComponents(); components.scheme = "https"; components.host = "sheets.googleapis.com"
            components.path = "/v4/spreadsheets/" + id + suffix; components.queryItems = query.isEmpty ? nil : query
            guard let url = components.url else { throw ProbeError.invalidSelection }
            var prepared = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
            prepared.httpMethod = body == nil ? "GET" : "POST"; prepared.httpBody = body
            prepared.setValue("Bearer " + (try await token()), forHTTPHeaderField: "Authorization")
            prepared.setValue("application/json", forHTTPHeaderField: "Accept")
            if body != nil { prepared.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            try Task.checkCancellation()
            request = prepared
        } catch {
            if reportUnsentWrite { throw SheetWriteNotSent(underlying: error) }
            throw error
        }
        let (data, response) = try await transport(request)
        guard (200..<300).contains(response.statusCode) else {
            // Never expose API response bodies or request URLs in shareable diagnostics.
            let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init).map { String(max(1, $0)) }
            let error = SheetHTTPError(status: response.statusCode, retryAfter: retry)
            if reportUnsentWrite, [400, 401, 403, 404, 429].contains(response.statusCode) {
                throw SheetWriteNotSent(underlying: error)
            }
            throw error
        }
        return data
    }
}
