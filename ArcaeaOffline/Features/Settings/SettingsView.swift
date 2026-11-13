import ArcaeaCore
import SwiftUI

/// Top level of Settings: one row per area, details one tap away.
struct SettingsView: View {
    @Environment(ArchiveModel.self) private var model
    @Environment(OnlineRuntime.self) private var runtime
    var body: some View {
        List {
            if model.profiles.count > 1 {
                Section {
                    Picker("Showing scores for", selection: Binding(get: { model.selectedAccountID }, set: { model.selectedAccountID = $0; model.perform { try model.reload() } })) {
                        ForEach(model.profiles, id: \.id) { Text($0.displayName ?? $0.id.rawValue).tag(Optional($0.id)) }
                    }
                }
            }
            Section("Accounts") {
                NavigationLink { MainAccountView() } label: {
                    SettingsRow(title: "Main account", detail: runtime.mainProfile.map { $0.displayName ?? $0.id.rawValue } ?? "Not signed in", systemImage: "person.crop.circle")
                }.accessibilityIdentifier("settings.main")
                NavigationLink { TrackerAccountView() } label: {
                    SettingsRow(title: "Tracker account", detail: trackerDetail, systemImage: "binoculars", warning: runtime.recentNeedsAttention)
                }.accessibilityIdentifier("settings.tracker")
            }
            Section("Automatic tracking") {
                TrackingStatusCard()
                NavigationLink { ShortcutSetupView() } label: { Label("Shortcut setup", systemImage: "square.2.layers.3d") }
                    .accessibilityIdentifier("settings.shortcuts")
            }
            Section("Google Sheets") {
                NavigationLink { SheetView() } label: { Label("Consultant sheet", systemImage: "tablecells") }
                    .accessibilityIdentifier("settings.sheet")
            }
            Section("Library") {
                NavigationLink { LibraryView() } label: { Label("Charts & cover art", systemImage: "photo.stack") }
                    .accessibilityIdentifier("settings.library")
                NavigationLink { BackupView() } label: { Label("Backup & restore", systemImage: "externaldrive") }
                    .accessibilityIdentifier("settings.backup")
            }
            Section {
                LabeledContent("Version", value: AppInfo.version)
                NavigationLink("Diagnostics") { DiagnosticsView() }
            } footer: {
                Text("ArcProbe is unofficial. It only reads your Arcaea Online data and keeps everything on this device.")
            }
        }
        .navigationTitle("Settings")
        .task { await runtime.refreshStatus() }
    }
    private var trackerDetail: String {
        if runtime.recentNeedsAttention { return "Needs sign-in" }
        guard let profile = runtime.recentProfile else { return "Not set up" }
        return profile.displayName ?? profile.id.rawValue
    }
}

struct SettingsRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var warning = false
    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if warning { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            Text(detail).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

enum AppInfo {
    static var shortVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }
}
