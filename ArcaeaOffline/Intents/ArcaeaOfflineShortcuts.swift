import AppIntents
import ArcaeaCore
import Foundation

struct ArcaeaOfflineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartNotificationTrackingIntent(), phrases: ["Start notification tracking in \(.applicationName)"], shortTitle: "Start Notifications", systemImageName: "bell.badge")
        AppShortcut(intent: StopNotificationTrackingIntent(), phrases: ["Stop notification tracking in \(.applicationName)"], shortTitle: "Stop Notifications", systemImageName: "bell.slash")
        AppShortcut(intent: ProcessTrackingNotificationIntent(), phrases: ["Process tracking notification in \(.applicationName)"], shortTitle: "Process Notification", systemImageName: "arrow.clockwise")
        AppShortcut(intent: FetchRecentPlayIntent(), phrases: ["Fetch recent plays with \(.applicationName)"], shortTitle: "Fetch Recent Play", systemImageName: "arrow.clockwise")
        AppShortcut(intent: GetTrackingStatusIntent(), phrases: ["Get tracking status in \(.applicationName)"], shortTitle: "Tracking Status", systemImageName: "clock")
        AppShortcut(intent: SetTrackingActiveIntent(), phrases: ["Set tracking in \(.applicationName)"], shortTitle: "Set Tracking", systemImageName: "playpause")
        AppShortcut(intent: ConfigureBurnerIntent(), phrases: ["Configure recent account in \(.applicationName)"], shortTitle: "Configure Account", systemImageName: "person.badge.key")
    }
}

enum ShortcutRecentMode: String, AppEnum {
    case ownAccountTesting, friendAccount
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Recent play source")
    static let caseDisplayRepresentations: [ShortcutRecentMode: DisplayRepresentation] = [
        .ownAccountTesting: "Own account (testing)", .friendAccount: "Friend account"
    ]
    var coreMode: RecentSourceMode { self == .ownAccountTesting ? .ownAccountTesting : .friendAccount }
}

enum ShortcutActionError: Error, LocalizedError {
    case invalidGeneration
    var errorDescription: String? { "Pass the generation returned by Set Tracking Active, or omit it for a one-shot fetch." }
}

struct ShortcutFetchOutput: Codable {
    let status: String
    let addedCount: Int
    let lastPlayAt: Date?
    let lastSuccessAt: Date?
    let nextEligibleAt: Date?
    init(_ result: FetchResult) {
        status = result.status.rawValue; addedCount = result.addedCount
        lastPlayAt = result.lastPlayAt; lastSuccessAt = result.lastSuccessAt; nextEligibleAt = result.nextEligibleAt
    }
}
struct ShortcutTrackingOutput: Codable {
    let isActive: Bool
    let generation: String?
    let status: String?
    let lastAttemptAt: Date?
    let lastSuccessAt: Date?
    let lastNewPlayAt: Date?
    let lastPlayAt: Date?
    let nextEligibleAt: Date?
    init(_ state: TrackingStatus) {
        isActive = state.isActive; generation = state.generation?.uuidString; status = state.lastStatus?.rawValue
        lastAttemptAt = state.lastAttemptAt; lastSuccessAt = state.lastSuccessAt; lastNewPlayAt = state.lastNewPlayAt
        lastPlayAt = state.lastPlayAt; nextEligibleAt = state.nextEligibleAt
    }
}
func shortcutJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

@MainActor enum ShortcutActions {
    static func fetch(runtime: OnlineRuntime, generation: String?, finalFetch: Bool = false) async throws -> String {
        let parsed: UUID?
        if let generation, !generation.isEmpty {
            guard let id = UUID(uuidString: generation) else { throw ShortcutActionError.invalidGeneration }
            parsed = id
        } else { parsed = nil }
        if finalFetch && parsed == nil { throw ShortcutActionError.invalidGeneration }
        let result = await runtime.fetchRecent(generation: parsed, finalFetch: finalFetch)
        return try shortcutJSON(ShortcutFetchOutput(result))
    }
    static func setTracking(runtime: OnlineRuntime, active: Bool) throws -> String {
        if active { return try runtime.startTracking().uuidString }
        try runtime.stopTracking(); return ""
    }
    static func status(runtime: OnlineRuntime) throws -> String {
        try shortcutJSON(ShortcutTrackingOutput(runtime.status()))
    }
}
