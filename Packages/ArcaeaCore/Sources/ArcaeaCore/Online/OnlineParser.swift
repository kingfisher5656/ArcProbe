import Foundation
import CoreFoundation

/// Defensive adaptation of the current official frontend and ArcPot read-contract evidence.
public enum OnlineParser {
    public static let maximumResponseBytes = 8 * 1024 * 1024

    public static func value(_ data: Data) throws -> Any {
        guard data.count <= maximumResponseBytes else { throw OnlineError.oversizedResponse }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["error_code"] == nil,
              let value = root["value"], !(value is NSNull) else { throw OnlineError.unsupportedResponse }
        if let success = root["success"] {
            guard let number = success as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), number.boolValue else { throw OnlineError.unsupportedResponse }
        }
        return value
    }

    public static func validateLogin(_ data: Data) throws {
        guard data.count <= maximumResponseBytes, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OnlineError.unsupportedResponse }
        if root["error_code"] != nil { throw OnlineError.interactionRequired }
        if let success = root["success"] {
            guard let number = success as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw OnlineError.unsupportedResponse }
            guard number.boolValue else { throw OnlineError.interactionRequired }
        }
        // The public login caller does not consume a value field. Identity is verified by user/me.
    }

    public static func account(_ data: Data, now: Date = Date()) throws -> RemoteAccount {
        guard let object = try value(data) as? [String: Any] else { throw OnlineError.unsupportedResponse }
        let profile = try profile(object)
        let remaining = try optionalInteger(object, "arcaea_online_expire_ts", min: Int64.min, max: Int64.max)
        let recent: [(ScoreObservation, ChartMetadata)]
        if let raw = object["recent_score"], !(raw is NSNull) {
            guard let list = raw as? [[String: Any]], list.count <= 1_000 else { throw OnlineError.unsupportedResponse }
            recent = try list.map { try score($0, account: profile.id, source: .officialRecent, now: now) }
        } else { recent = [] }
        return RemoteAccount(profile: profile, subscriptionRemainingMilliseconds: remaining, recentScores: recent.map { $0.0 }, recentCharts: recent.map { $0.1 })
    }

    public static func friendRecent(_ data: Data, target: AccountID, now: Date) throws -> [ScoreObservation] {
        try friendPayload(data, target: target, now: now).observations
    }

    public static func friendPayload(_ data: Data, target: AccountID, now: Date) throws -> RecentPayload {
        guard let object = try value(data) as? [String: Any], let friends = object["friends"] as? [[String: Any]],
              friends.count <= 1_000 else { throw OnlineError.unsupportedResponse }
        var matches: [[String: Any]] = []
        for friend in friends where try profile(friend).id == target { matches.append(friend) }
        guard matches.count == 1 else { throw matches.isEmpty ? OnlineError.targetNotFound : OnlineError.unsupportedResponse }
        guard let raw = matches[0]["recent_score"], !(raw is NSNull) else {
            return RecentPayload(profile: try profile(matches[0]), observations: [])
        }
        guard let scores = raw as? [[String: Any]], scores.count <= 1_000 else { throw OnlineError.unsupportedResponse }
        let parsed = try scores.map { try score($0, account: target, source: .officialRecent, now: now) }
        return RecentPayload(profile: try profile(matches[0]), observations: parsed.map { $0.0 }, charts: parsed.map { $0.1 })
    }

    public static func scorePage(_ data: Data, difficulty: Difficulty, account: AccountID, now: Date) throws -> ScorePage {
        guard let object = try value(data) as? [String: Any], let scores = object["scores"] as? [[String: Any]],
              scores.count <= 1_000 else { throw OnlineError.unsupportedResponse }
        let count = Int(try integer(object["count"], min: 0, max: 10_000))
        let parsed = try scores.map { try score($0, account: account, source: .officialImport, now: now) }
        guard parsed.allSatisfy({ $0.0.chartID.difficulty == difficulty }) else { throw OnlineError.unsupportedResponse }
        return ScorePage(count: count, observations: parsed.map { $0.0 }, charts: parsed.map { $0.1 })
    }

    public static func potentialHistory(_ data: Data, account: AccountID, now: Date) throws -> [PotentialPoint] {
        guard let rows = try value(data) as? [[String: Any]], rows.count <= 200_000 else { throw OnlineError.unsupportedResponse }
        var times = Set<Int64>()
        return try rows.map { row in
            let time = try integer(row["time_played"], min: 1_420_070_400_000, max: Int64(now.addingTimeInterval(86_400).timeIntervalSince1970 * 1_000))
            let rating = try integer(row["user_rating"], min: 0, max: 30_000)
            guard times.insert(time).inserted else { throw OnlineError.unsupportedResponse }
            return PotentialPoint(accountID: account, sourceID: "online:\(time)", timestamp: SourceTimestamp(value: time, unit: .milliseconds),
                                  value: PotentialValue(rawValue: rating, decimalPlaces: 3), firstSeenAt: now)
        }
    }

    private static func profile(_ object: [String: Any]) throws -> AccountProfile {
        let key: String
        if let string = object["user_id"] as? String { key = string }
        else { key = String(try integer(object["user_id"], min: 0, max: 9_007_199_254_740_991)) }
        guard validIdentifier(key, maximum: 80) else { throw OnlineError.unsupportedResponse }
        return AccountProfile(id: AccountID("online:\(key)"), displayName: object["name"] as? String)
    }

    private static func score(_ row: [String: Any], account: AccountID, source: ObservationSource, now: Date) throws -> (ScoreObservation, ChartMetadata) {
        guard let song = row["song_id"] as? String, validIdentifier(song, maximum: 160),
              let difficulty = Difficulty(rawValue: Int(try integer(row["difficulty"], min: 0, max: 4))) else { throw OnlineError.unsupportedResponse }
        let chart = ChartID(songID: song, difficulty: difficulty)
        let score = Int(try integer(row["score"], min: 0, max: 10_100_000))
        let timestamp = try optionalInteger(row, "time_played", min: 0, max: Int64(now.addingTimeInterval(86_400).timeIntervalSince1970 * 1_000))
        let judgmentKeys = ["perfect_count", "shiny_perfect_count", "near_count", "miss_count", "early_count", "late_count"]
        let counts = try judgmentKeys.map { try optionalInteger(row, $0, min: 0, max: 100_000).map(Int.init) }
        let judgments = counts.allSatisfy { $0 == nil } ? nil : Judgments(pure: counts[0], shinyPure: counts[1], far: counts[2], lost: counts[3], early: counts[4], late: counts[5])
        let play = try optionalInteger(row, "clear_type", min: 0, max: 5).flatMap { ClearType(rawValue: Int($0)) }
        let best = try optionalInteger(row, "best_clear_type", min: 0, max: 5).flatMap { ClearType(rawValue: Int($0)) }
        let values = ScoreValues(score: score, playedAt: timestamp.flatMap { $0 > 0 ? SourceTimestamp(value: $0, unit: .milliseconds) : nil }, judgments: judgments, playClear: play, bestClear: best, modifier: try optionalInteger(row, "modifier", min: -1, max: 65535).flatMap { $0 >= 0 ? Int($0) : nil }, health: try optionalInteger(row, "health", min: -1, max: 100).flatMap { $0 >= 0 ? Int($0) : nil })
        let eventID: String?
        if let event = row["score_id"] as? String, validIdentifier(event, maximum: 160) { eventID = event }
        else { eventID = nil }
        let observation = try ScoreObservation.remote(accountID: account, chartID: chart, source: source, values: values, firstSeenAt: now, eventID: eventID)
        let title = (row["title"] as? [String: String])?["en"] ?? row["title"] as? String
        let alias = try optionalInteger(row, "difficulty_alias", min: 0, max: 100)
        let metadata = ChartMetadata(id: chart, difficultyLabel: difficulty == .beyond && alias == 1 ? "INS" : nil,
                                     title: title, artist: row["artist"] as? String, artworkIdentifier: (row["bg"] as? String).flatMap { ArtworkPolicy.validIdentifier($0) ? $0 : nil }, provenance: "Official website payload; constants remain from the dated local catalog")
        return (observation, metadata)
    }

    private static func validIdentifier(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximum && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 || $0 == 45 }
    }

    private static func optionalInteger(_ object: [String: Any], _ key: String, min: Int64, max: Int64) throws -> Int64? {
        guard let value = object[key], !(value is NSNull) else { return nil }
        return try integer(value, min: min, max: max)
    }

    private static func integer(_ value: Any?, min: Int64, max: Int64) throws -> Int64 {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { throw OnlineError.unsupportedResponse }
        let double = number.doubleValue
        guard double.isFinite, double.rounded(.towardZero) == double,
              double >= Double(min), double <= Double(max),
              let integer = Int64(number.stringValue), integer >= min, integer <= max else { throw OnlineError.unsupportedResponse }
        return integer
    }
}
