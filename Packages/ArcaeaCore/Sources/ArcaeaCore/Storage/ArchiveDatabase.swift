import Foundation
import CSQLite

internal enum SQLValue {
    case text(String), integer(Int64), blob(Data), null
}

internal final class ArchiveDatabase {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let code = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK else { throw failure() }
        sqlite3_busy_timeout(handle, 5_000)
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = FULL")
    }

    deinit { sqlite3_close_v2(handle) }

    func execute(_ sql: String, _ values: [SQLValue] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW { result = sqlite3_step(statement) }
        guard result == SQLITE_DONE else { throw failure() }
    }

    func dataRows(_ sql: String, _ values: [SQLValue] = []) throws -> [Data] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var rows: [Data] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return rows }
            guard code == SQLITE_ROW else { throw failure() }
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard let pointer = sqlite3_column_blob(statement, 0) else {
                rows.append(Data()); continue
            }
            rows.append(Data(bytes: pointer, count: count))
        }
    }

    func integer(_ sql: String, _ values: [SQLValue] = []) throws -> Int64? {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE { return nil }
        guard code == SQLITE_ROW else { throw failure() }
        if sqlite3_column_type(statement, 0) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    func transaction<T>(write: Bool = true, _ body: () throws -> T) throws -> T {
        try execute(write ? "BEGIN IMMEDIATE" : "BEGIN DEFERRED")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ values: [SQLValue]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        do {
            for (index, value) in values.enumerated() {
                let slot = Int32(index + 1)
                let code: Int32
                switch value {
                case .text(let text): code = text.withCString { sqlite3_bind_text(statement, slot, $0, -1, transient) }
                case .integer(let number): code = sqlite3_bind_int64(statement, slot, number)
                case .blob(let bytes):
                    code = bytes.withUnsafeBytes { sqlite3_bind_blob(statement, slot, $0.baseAddress, Int32($0.count), transient) }
                case .null: code = sqlite3_bind_null(statement, slot)
                }
                guard code == SQLITE_OK else { throw failure() }
            }
            return statement
        } catch { sqlite3_finalize(statement); throw error }
    }

    private func failure() -> ArchiveError {
        ArchiveError.database(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open archive")
    }
}
