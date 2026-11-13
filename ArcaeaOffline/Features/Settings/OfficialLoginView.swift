import ArcaeaCore
import SwiftUI
import WebKit

/// Identifies which login sheet is open. A sheet driven by this must be attached to a
/// whole screen, never to a Form `Section`: SwiftUI copies a section's modifiers onto every
/// row, and the duplicate sheets dismiss each other the first time they are shown.
struct LoginRequest: Identifiable {
    let role: AccountRole
    var mode: RecentSourceMode = .friendAccount
    var id: String { role.rawValue }
}

/// The official Arcaea login page in an isolated in-app browser, one per account role.
struct OfficialLoginView: View {
    @Environment(OnlineRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    let request: LoginRequest
    @State private var confirming = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OfficialWebView(runtime: runtime, role: request.role)
                VStack(spacing: 10) {
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
                    Button { confirm() } label: {
                        Group { if confirming { ProgressView() } else { Text("Use this account").fontWeight(.semibold) } }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(confirming)
                    .accessibilityIdentifier("login.confirm")
                    Text("Log in above, then tap the button.").font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle(request.role == .main ? "Main account" : "Tracker account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Reload", systemImage: "arrow.clockwise") { runtime.reloadLogin(role: request.role) } }
            }
        }
        .interactiveDismissDisabled(confirming)
        .presentationSizing(.page)
    }
    private func confirm() {
        Task {
            confirming = true; defer { confirming = false }
            do {
                _ = try await runtime.captureLogin(role: request.role)
                if request.role == .burner { try await runtime.configureRecentFromBrowser(mode: request.mode) }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct OfficialWebView: UIViewRepresentable {
    let runtime: OnlineRuntime
    let role: AccountRole
    func makeUIView(context: Context) -> WKWebView { runtime.loginWebView(role: role) }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}
