import ArcaeaCore
import SwiftUI
import WebKit

private struct LoginDestination: Identifiable {
    let role: AccountRole
    let mode: RecentSourceMode
    var id: String { role.rawValue }
}

struct AccountSettingsSections: View {
    @Environment(ArchiveModel.self) private var model
    @Environment(OnlineRuntime.self) private var runtime
    @State private var login: LoginDestination?
    @State private var credentialSetup = false
    @State private var mode = RecentSourceMode.ownAccountTesting
    @State private var disconnecting: AccountRole?
    @State private var importTask: Task<Void, Never>?
    @State private var fetching = false
    var body: some View {
        Section {
            if let profile = runtime.mainProfile { LabeledContent("Signed in", value: profile.displayName ?? profile.id.rawValue) }
            Button(runtime.mainProfile == nil ? "Sign in to main account" : "Replace main login", systemImage: "person.crop.circle") { login = LoginDestination(role: .main, mode: mode) }.disabled(runtime.isImporting)
            Button("Import all scores and five-year history", systemImage: "arrow.down.circle") {
                importTask = Task {
                    do { let receipt = try await runtime.fullImport(); model.selectedAccountID = receipt.accountID; try model.reload(); model.notice = "Import complete: \(receipt.addedCount) new plays" }
                    catch { model.errorMessage = error.localizedDescription }
                    importTask = nil
                }
            }.disabled(runtime.mainProfile == nil || runtime.isImporting)
            if runtime.isImporting { HStack { ProgressView(); Text(runtime.progress).font(.subheadline); Spacer(); Button("Cancel") { importTask?.cancel() } } }
            if runtime.mainProfile != nil { Button("Disconnect main login", role: .destructive) { disconnecting = .main }.disabled(runtime.isImporting) }
        } header: { Text("Main account · full import") } footer: { Text("Use your subscribed main account here. Scores and official history are committed together after a complete import.") }
        Section {
            Picker("Recent source", selection: $mode) { Text("Own account (testing)").tag(RecentSourceMode.ownAccountTesting); Text("Friend target (burner)").tag(RecentSourceMode.friendAccount) }
            if let profile = runtime.recentProfile { LabeledContent("Observer login", value: profile.displayName ?? profile.id.rawValue) }
            if let configuration = runtime.recentConfiguration { LabeledContent("Saved mode", value: configuration.mode == .ownAccountTesting ? "Own account testing" : "Friend target"); LabeledContent("Target account", value: targetName(configuration.target)) }
            Button(runtime.recentProfile == nil ? "Sign in to recent account" : "Replace recent login", systemImage: "person.crop.circle.badge.clock") { login = LoginDestination(role: .burner, mode: mode) }.disabled(mode == .friendAccount && runtime.mainProfile == nil)
            Button("Set up automatic session renewal", systemImage: "key") { credentialSetup = true }.disabled(mode == .friendAccount && runtime.mainProfile == nil)
            Button("Fetch recent play now", systemImage: "arrow.clockwise") { Task { fetching = true; let result = await runtime.fetchRecent(); if [.success, .unchanged].contains(result.status) { model.selectedAccountID = runtime.recentConfiguration?.target }; model.perform { try model.reload() }; model.notice = resultMessage(result); fetching = false } }.disabled(runtime.recentConfiguration == nil || fetching)
            if fetching { ProgressView("Fetching recent play…") }
            if runtime.recentProfile != nil { Button("Disconnect recent login", role: .destructive) { disconnecting = .burner } }
        } header: { Text("Recent account · separate session") } footer: { Text(mode == .ownAccountTesting ? "Testing mode reads recent plays from the independently signed-in observer. You may temporarily use your main account identity here; its recent session stays separate from full import." : "Friend mode observes the connected main account through the burner’s friends list. Connect your main login first. The burner must already be friends with it.") }
        Section("Tracking and Shortcuts") {
            Toggle("Enforce 60-second minimum", isOn: Binding(
                get: { runtime.trackingStatus?.minimumIntervalEnabled ?? true },
                set: { enabled in
                    do { try runtime.setMinimumIntervalEnabled(enabled) }
                    catch { model.errorMessage = error.localizedDescription }
                }
            ))
            .accessibilityIdentifier("minimumFetchInterval")
            Text("Applies to manual and Shortcut recent fetches. Turn off to allow earlier requests. Server cooldowns, delays after network failures, and protection against simultaneous requests still apply. Existing Shortcut Wait actions are unchanged.")
                .font(.footnote).foregroundStyle(.secondary)
            TrackingStatusCard()
            Button(runtime.trackingStatus?.isActive == true ? "Set tracking inactive" : "Set tracking active", systemImage: runtime.trackingStatus?.isActive == true ? "stop.circle" : "play.circle") {
                do { if runtime.trackingStatus?.isActive == true { try runtime.stopTracking() } else { _ = try runtime.startTracking() } } catch { model.errorMessage = error.localizedDescription }
            }.disabled(runtime.recentConfiguration == nil)
            NavigationLink("Shortcut setup instructions") { ShortcutInstructionsView() }
        }
        .sheet(item: $login) { destination in OfficialLoginView(role: destination.role, mode: destination.mode) }
        .sheet(isPresented: $credentialSetup) { RecentCredentialsView(mode: mode) }
        .confirmationDialog("Disconnect this login?", isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }), titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) { if let role = disconnecting { Task { do { try await runtime.disconnect(role: role) } catch { model.errorMessage = error.localizedDescription } } }; disconnecting = nil }
        } message: { Text("Only this role’s session secrets are removed. Saved scores and history stay in your archive.") }
        .task { await runtime.refreshStatus(); if let saved = runtime.recentConfiguration { mode = saved.mode } }
    }
    private func targetName(_ id: AccountID) -> String { model.profiles.first { $0.id == id }?.displayName ?? (runtime.mainProfile?.id == id ? runtime.mainProfile?.displayName : nil) ?? id.rawValue }
    private func resultMessage(_ result: FetchResult) -> String {
        switch result.status {
        case .success: "Saved \(result.addedCount) new play\(result.addedCount == 1 ? "" : "s")"
        case .unchanged: "Recent play is already saved"
        case .cooldown, .rateLimited: "Fetch is waiting for the next eligible time"
        case .alreadyFetching: "A recent fetch is already running"
        case .authenticationRequired, .attentionRequired, .locked: "Recent login needs attention in Settings"
        case .offline: "No connection. Your saved plays are available offline"
        case .deadlineExceeded: "Fetch reached its time limit; try again later"
        case .trackingStopped, .staleGeneration: "Tracking session has stopped"
        case .cancelled: "Fetch cancelled"
        case .wrongAccount: "Recent observer or target does not match the saved setup"
        case .unsupportedSchema: "Website response changed; saved data is preserved"
        case .failed: "Recent fetch could not finish"
        }
    }
}

private struct OfficialLoginView: View {
    @Environment(OnlineRuntime.self) private var runtime
    @Environment(ArchiveModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let role: AccountRole
    let mode: RecentSourceMode
    @State private var confirming = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(role == .main ? "Sign in on the official site, then use the signed-in account for full import." : "Sign in independently for the recent role. This browser uses a separate session from main-account import.").font(.subheadline).foregroundStyle(.secondary).padding()
                OfficialWebView(runtime: runtime, role: role)
                if let error { Text(error).font(.subheadline).foregroundStyle(.red).padding() }
                Button {
                    Task { confirming = true; do { _ = try await runtime.captureLogin(role: role); if role == .burner { try await runtime.configureRecentFromBrowser(mode: mode) }; dismiss() } catch { self.error = error.localizedDescription }; confirming = false }
                } label: { if confirming { ProgressView() } else { Text("Use signed-in account").fontWeight(.semibold).frame(maxWidth: .infinity) } }.buttonStyle(.borderedProminent).disabled(confirming).padding()
            }
            .navigationTitle(role == .main ? "Main account login" : "Recent account login").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

private struct OfficialWebView: UIViewRepresentable {
    let runtime: OnlineRuntime
    let role: AccountRole
    func makeUIView(context: Context) -> WKWebView { runtime.loginWebView(role: role) }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

private struct RecentCredentialsView: View {
    @Environment(OnlineRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    let mode: RecentSourceMode
    @State private var email = ""
    @State private var password = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Email", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress); SecureField("Password", text: $password) } header: { Text("Recent account credentials") } footer: { Text("These credentials are stored in the device Keychain for one bounded renewal after an expired session. They are excluded from backups and diagnostics.") }
                Section { LabeledContent("Mode", value: mode == .ownAccountTesting ? "Own account testing" : "Friend target"); if mode == .friendAccount { LabeledContent("Main target", value: runtime.mainProfile?.displayName ?? "Connect main account first") } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section { Text("If the website requests a CAPTCHA or other verification, finish it through Recent account login. A browser-only setup may require you to sign in again when its session expires.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Automatic renewal").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { saving = true; do { try await runtime.configureRecent(email: email, password: password, mode: mode); password = ""; dismiss() } catch { self.error = error.localizedDescription }; saving = false } }.disabled(email.isEmpty || password.isEmpty || saving) } }
            .overlay { if saving { ProgressView("Verifying recent account…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
    }
}

struct ShortcutInstructionsView: View {
    var body: some View {
        List {
            Section("One-shot fetch") { Text("Set up the recent account in Settings, then add Fetch Recent Play to a Shortcut. It reuses the recent session and reports status, added count, and the next eligible request time.") }
            Section("Arcaea opened") { Text("Create an Arcaea App Opened automation. Run Set Tracking Active with Active enabled, keep its generation result, then use Fetch Recent Play with that generation. A bounded Repeat / Wait experiment can target 70 seconds between requests.") }
            Section("Arcaea closed") { Text("Create an Arcaea App Closed automation that disables Set Tracking Active. In the polling Shortcut’s inactive branch, Repeat 2 times: Wait 65 seconds, then Fetch Recent Play with Final Fetch After Closing enabled and the original generation. Then stop the Shortcut. Keep this option off for normal polling. A new generation cancels old closing fetches. Respect nextEligibleAt if the server requires a longer wait; cooldown is not a completed sync.") }
            Section("Timing") { Text("Respect the saved next eligible time and server cooldowns. The optional 60-second minimum can be disabled in Tracking and Shortcuts. iPadOS can suspend a Shortcut loop; sustained 60–80-second capture remains experimental until a 30–60-minute device test verifies it.") }
            Section("Credentials") { Text("Configure Recent Account accepts credentials once. Remove literal passwords from saved setup actions after configuration; recurring Fetch Recent Play has no password parameter.") }
        }.navigationTitle("Shortcut setup")
    }
}
