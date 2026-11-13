import ArcaeaCore
import SwiftUI

/// The second login that watches for new plays while Arcaea is open.
/// Usually a spare account that is friends with the main account.
struct TrackerAccountView: View {
    @Environment(ArchiveModel.self) private var model
    @Environment(OnlineRuntime.self) private var runtime
    @State private var mode = RecentSourceMode.friendAccount
    @State private var login: LoginRequest?
    @State private var savingPassword = false
    @State private var confirmingSignOut = false
    @State private var fetching = false
    private var needsMain: Bool { mode == .friendAccount && runtime.mainProfile == nil }
    var body: some View {
        List {
            Section {
                Picker("Watch", selection: $mode) {
                    Text("Main account, as its friend").tag(RecentSourceMode.friendAccount)
                    Text("The tracker account itself").tag(RecentSourceMode.ownAccountTesting)
                }.accessibilityIdentifier("tracker.mode")
            } footer: {
                Text(mode == .friendAccount
                     ? "Sign in here with a spare account that has your main account as a friend. Sign in to the main account first, so ArcProbe knows whom to watch."
                     : "Sign in here with the account you play on. No spare account is needed.")
            }
            Section {
                LabeledContent("Signed in as", value: runtime.recentProfile.map { $0.displayName ?? $0.id.rawValue } ?? "Not signed in")
                if let configuration = runtime.recentConfiguration { LabeledContent("Watching", value: name(configuration.target)) }
                if runtime.recentNeedsAttention {
                    Label("The website rejected this login. Sign in again.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Button(runtime.recentProfile == nil ? "Sign in" : "Sign in again", systemImage: "person.crop.circle.badge.clock") { login = LoginRequest(role: .burner, mode: mode) }
                    .disabled(needsMain).accessibilityIdentifier("tracker.signIn")
                Button("Save password for automatic re-login", systemImage: "key") { savingPassword = true }
                    .disabled(needsMain).accessibilityIdentifier("tracker.password")
            } footer: {
                Text("Website logins expire. With a saved password ArcProbe signs in again by itself; without one, tracking pauses until you sign in here.")
            }
            if runtime.recentConfiguration != nil {
                Section {
                    Button { fetch() } label: {
                        HStack { Label("Check for a new play now", systemImage: "arrow.clockwise"); Spacer(); if fetching { ProgressView() } }
                    }.disabled(fetching).accessibilityIdentifier("tracker.fetch")
                }
            }
            if runtime.recentProfile != nil {
                Section { Button("Sign out", role: .destructive) { confirmingSignOut = true } }
            }
        }
        .navigationTitle("Tracker account").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $login) { OfficialLoginView(request: $0) }
        .sheet(isPresented: $savingPassword) { TrackerPasswordView(mode: mode) }
        .confirmationDialog("Sign out of the tracker account?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { do { try await runtime.disconnect(role: .burner) } catch { model.errorMessage = error.localizedDescription } } }
        } message: { Text("Automatic tracking stops. Saved scores stay on this device.") }
        .task {
            await runtime.refreshStatus()
            if let saved = runtime.recentConfiguration { mode = saved.mode }
            else if runtime.mainProfile == nil, runtime.recentProfile != nil { mode = .ownAccountTesting }
        }
        .onChange(of: mode) { _, selected in
            // Already signed in: apply the new choice right away instead of asking to sign in again.
            guard runtime.recentProfile != nil, runtime.recentConfiguration?.mode != selected, !needsMain else { return }
            Task {
                do { try await runtime.configureRecentFromBrowser(mode: selected) }
                catch {
                    model.errorMessage = error.localizedDescription
                    if let saved = runtime.recentConfiguration { mode = saved.mode }
                }
            }
        }
    }
    private func name(_ id: AccountID) -> String {
        model.profiles.first { $0.id == id }?.displayName ?? (runtime.mainProfile?.id == id ? runtime.mainProfile?.displayName : nil) ?? id.rawValue
    }
    private func fetch() {
        Task {
            fetching = true; defer { fetching = false }
            let result = await runtime.fetchRecent()
            if result.status.reachedServer { model.selectedAccountID = runtime.recentConfiguration?.target }
            model.perform { try model.reload() }
            model.notice = result.summary
        }
    }
}

private struct TrackerPasswordView: View {
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
                Section {
                    TextField("Email", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.emailAddress).textContentType(.username)
                    SecureField("Password", text: $password).textContentType(.password)
                } footer: {
                    Text("Stored only in this device’s Keychain and used only to sign the tracker account in again when its login expires. If the website asks for a verification check, use Sign in instead.")
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Tracker password").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(email.isEmpty || password.isEmpty || saving) }
            }
            .overlay { if saving { ProgressView("Signing in…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        }
    }
    private func save() {
        Task {
            saving = true; defer { saving = false }
            do { try await runtime.configureRecent(email: email, password: password, mode: mode); password = ""; dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}
