import Foundation

internal enum Migrations {
    static let currentVersion = 4
    static func run(_ db: ArchiveDatabase) throws {
        try db.transaction {
            let version = Int(try db.integer("PRAGMA user_version") ?? 0)
            guard version <= currentVersion else { throw ArchiveError.unsupportedVersion(version) }
            if version == 0 {
                let statements = [
                    "CREATE TABLE profiles (account_id TEXT PRIMARY KEY, payload BLOB NOT NULL)",
                    "CREATE TABLE charts (song_id TEXT NOT NULL, difficulty INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(song_id, difficulty))",
                    "CREATE TABLE observations (observation_id TEXT PRIMARY KEY, account_id TEXT NOT NULL REFERENCES profiles(account_id), song_id TEXT NOT NULL, difficulty INTEGER NOT NULL, payload BLOB NOT NULL)",
                    "CREATE INDEX observations_by_account ON observations(account_id, song_id, difficulty)",
                    "CREATE TABLE overrides (observation_id TEXT PRIMARY KEY REFERENCES observations(observation_id) ON DELETE CASCADE, payload BLOB NOT NULL)",
                    "CREATE TABLE suppressions (observation_id TEXT PRIMARY KEY REFERENCES observations(observation_id) ON DELETE CASCADE, payload BLOB NOT NULL)",
                    "CREATE TABLE best_corrections (account_id TEXT NOT NULL REFERENCES profiles(account_id), song_id TEXT NOT NULL, difficulty INTEGER NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(account_id, song_id, difficulty))",
                    "CREATE TABLE potential_points (account_id TEXT NOT NULL REFERENCES profiles(account_id), series TEXT NOT NULL, source_id TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(account_id, series, source_id))",
                    "CREATE TABLE receipts (id TEXT PRIMARY KEY, account_id TEXT REFERENCES profiles(account_id), payload BLOB NOT NULL)",
                    "CREATE TABLE manual_undo (sequence INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT NOT NULL UNIQUE, payload BLOB NOT NULL)"
                ]
                for sql in statements { try db.execute(sql) }
                try db.execute("PRAGMA user_version = 1")
            }
            if version < 2 {
                try db.execute("CREATE TABLE observation_captures (observation_id TEXT NOT NULL REFERENCES observations(observation_id) ON DELETE CASCADE, capture_id TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(observation_id, capture_id))")
                try db.execute("INSERT INTO observation_captures SELECT observation_id, 'initial', payload FROM observations")
                try db.execute("PRAGMA user_version = 2")
            }
            if version < 3 {
                try db.execute("CREATE TABLE observation_aliases (external_id TEXT PRIMARY KEY, observation_id TEXT NOT NULL REFERENCES observations(observation_id) ON DELETE CASCADE, payload BLOB NOT NULL)")
                try db.execute("PRAGMA user_version = 3")
            }
            if version < 4 {
                try db.execute("CREATE TABLE potential_baselines (account_id TEXT PRIMARY KEY REFERENCES profiles(account_id), payload BLOB NOT NULL)")
                try db.execute("PRAGMA user_version = 4")
            }
        }
    }
}
