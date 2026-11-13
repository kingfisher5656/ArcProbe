import Foundation
import Security
import UIKit
@preconcurrency import AppAuth
import ConsultantProbeCore

/// Isolated from Arcaea main/burner sessions. No token, code or callback URL is logged.
@MainActor final class GoogleProbeAuth: NSObject, OIDAuthStateChangeDelegate {
    static let clientID = "43405400206-6jkgod4gb5c5np2qnnr3jak74b336sj8.apps.googleusercontent.com"
    static let callbackScheme = "com.googleusercontent.apps.43405400206-6jkgod4gb5c5np2qnnr3jak74b336sj8"
    static let scope = "https://www.googleapis.com/auth/drive.file"
    private var state: OIDAuthState?
    private var session: (any OIDExternalUserAgentSession)?
    private(set) var fileID: String?
    private(set) var storageIssue = false
    var connected: Bool { state?.isAuthorized == true }
    var canRefresh: Bool { state?.refreshToken != nil }
    private struct SavedSession: Codable { let state: Data; let fileID: String }
    private var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "app.arcaeaoffline") + ".consultant-probe",
         kSecAttrAccount as String: "google-oauth"]
    }
    override init() {
        super.init()
        var query = keychainQuery
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return }
        do {
            guard status == errSecSuccess, let data = result as? Data else { throw AuthError.storage }
            let saved = try JSONDecoder().decode(SavedSession.self, from: data)
            let restored = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: saved.state)
            guard let restored else { throw AuthError.storage }
            fileID = try SheetParsing.selectedID(saved.fileID)
            state = restored; restored.stateChangeDelegate = self
        } catch { storageIssue = true }
    }
    func connect(requiredFileID: String? = nil) async throws {
        let (candidate, selected) = try await authorize(requiredFileID: requiredFileID)
        try install(candidate, selectedID: selected)
    }
    private func install(_ candidate: OIDAuthState, selectedID: String) throws {
        try persist(state: candidate, fileID: selectedID)
        state?.stateChangeDelegate = nil
        state = candidate; fileID = selectedID; candidate.stateChangeDelegate = self
    }
    private func authorize(requiredFileID: String?) async throws -> (OIDAuthState, String) {
        guard session == nil else { throw ProbeError.busy }
        guard let presenter = presenter() else { throw AuthError.presentation }
        let configuration = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!)
        var parameters = ["access_type": "offline", "prompt": "consent", "trigger_onepick": "true",
                          "include_granted_scopes": "false", "mimetypes": "application/vnd.google-apps.spreadsheet"]
        if let requiredFileID { parameters["file_ids"] = requiredFileID }
        let request = OIDAuthorizationRequest(configuration: configuration, clientId: Self.clientID,
            clientSecret: nil, scopes: [Self.scope], redirectURL: URL(string: Self.callbackScheme + ":/oauthredirect")!,
            responseType: OIDResponseTypeCode, additionalParameters: parameters)
        // AppAuth generates and verifies PKCE + state, and uses ASWebAuthenticationSession.
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(OIDAuthState, String), Error>) in
            session = OIDAuthState.authState(byPresenting: request, presenting: presenter) { [weak self] newState, error in
                MainActor.assumeIsolated {
                    guard let self else { continuation.resume(throwing: AuthError.cancelled); return }
                    self.session = nil
                    guard let newState, error == nil, newState.isAuthorized else {
                        continuation.resume(throwing: AuthError.authorization); return
                    }
                    do {
                        let selected = try SheetParsing.selectedID(newState.lastAuthorizationResponse.additionalParameters?["picked_file_ids"] as? String ?? "")
                        if let requiredFileID, selected != requiredFileID { throw ProbeError.pending }
                        continuation.resume(returning: (newState, selected))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
    @discardableResult func resume(_ url: URL) -> Bool {
        guard url.scheme == Self.callbackScheme, url.path == "/oauthredirect" else { return false }
        guard let session else { return false }
        do { try session.resumeExternalUserAgentFlow(url); return true } catch { return false }
    }
    func token(forceRefresh: Bool = false) async throws -> String {
        guard let state, state.isAuthorized else { throw AuthError.authorization }
        if forceRefresh {
            guard state.refreshToken != nil else { throw AuthError.noRefresh }
            state.setNeedsTokenRefresh()
        }
        return try await withCheckedThrowingContinuation { continuation in
            state.performAction { [weak self] accessToken, _, error in
                MainActor.assumeIsolated {
                    if let error { continuation.resume(throwing: Self.refreshError(error)); return }
                    guard let self, let accessToken else { continuation.resume(throwing: AuthError.authorization); return }
                    do { try self.save(); continuation.resume(returning: accessToken) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
    nonisolated func didChange(_ state: OIDAuthState) {
        Task { @MainActor [weak self] in
            do { try self?.save() } catch { self?.storageIssue = true }
        }
    }
    func disconnect() throws {
        let status = SecItemDelete(keychainQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AuthError.storage }
        state = nil; fileID = nil; storageIssue = false
    }
    private func save() throws {
        guard let state, let fileID else { return }
        try persist(state: state, fileID: fileID)
    }
    private func persist(state: OIDAuthState, fileID: String) throws {
        let archive = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
        let data = try JSONEncoder().encode(SavedSession(state: archive, fileID: fileID))
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(keychainQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = keychainQuery; attributes.forEach { query[$0.key] = $0.value }
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { storageIssue = true; throw AuthError.storage }
        storageIssue = false
    }
    private func presenter() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
    /// Inspect only error categories; never expose token responses in diagnostics.
    nonisolated static func refreshError(_ error: Error) -> AuthError {
        var current = error as NSError
        for _ in 0..<8 {
            if current.domain == NSURLErrorDomain
                || (current.domain == OIDGeneralErrorDomain && current.code == -5)
                || (current.domain == OIDHTTPErrorDomain && (current.code == 429 || current.code >= 500)) {
                return .temporaryRefresh
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        return .authorization
    }
    enum AuthError: Error, LocalizedError, Equatable {
        case storage, presentation, authorization, noRefresh, cancelled, temporaryRefresh
        var errorDescription: String? {
            switch self {
            case .storage: "Google session could not be saved in Keychain. Unlock the device and retry."
            case .presentation: "Keep ArcProbe in the foreground, then connect again."
            case .authorization: "Google sign-in was cancelled or failed. Check consent test-user access, client configuration and the callback after SideStore installation, then reconnect."
            case .noRefresh: "No refresh token was granted. Connect again and complete consent."
            case .cancelled: "Sign-in was cancelled."
            case .temporaryRefresh: "Google token refresh temporarily failed. Retry when connected."
            }
        }
    }
}
