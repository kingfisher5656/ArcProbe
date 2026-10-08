import ArcaeaCore
import Darwin
import Foundation
import Security

/// Device-only secrets are available after the first unlock for background Shortcut reads.
actor KeychainSessionStore: SessionStore {
    private let service: String
    private let lockURL: URL
    init(directory: URL, service: String = (Bundle.main.bundleIdentifier ?? "ArcaeaOffline") + ".sessions") throws {
        self.service = service
        self.lockURL = directory.appendingPathComponent("session-operation.lock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load(role: AccountRole) throws -> AccountSession? { try locked { try read(role: role) } }
    func save(_ session: AccountSession, role: AccountRole) throws { try locked { try write(session, role: role) } }
    func clear(role: AccountRole) throws {
        try locked {
            let status = SecItemDelete(query(role: role) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
        }
    }
    func compareAndSave(_ session: AccountSession, role: AccountRole, expectedRevision: UUID?) throws -> Bool {
        try locked {
            guard try read(role: role)?.revision == expectedRevision else { return false }
            try write(session, role: role); return true
        }
    }
    func withValidSession<T: Sendable>(role: AccountRole, expectedRevision: UUID, operation: @Sendable () throws -> T) throws -> T {
        try locked {
            guard try read(role: role)?.revision == expectedRevision else { throw OnlineError.cancelled }
            try Task.checkCancellation()
            return try operation()
        }
    }

    private func query(role: AccountRole) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: role.rawValue, kSecAttrSynchronizable as String: false]
    }
    private func read(role: AccountRole) throws -> AccountSession? {
        var query = query(role: role)
        query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw keychainError(status) }
        guard let data = result as? Data, data.count <= 256 * 1024,
              let session = try? JSONDecoder().decode(AccountSession.self, from: data) else { throw OnlineError.unsupportedResponse }
        return session
    }
    private func write(_ session: AccountSession, role: AccountRole) throws {
        let data = try JSONEncoder().encode(session)
        guard data.count <= 256 * 1024 else { throw OnlineError.oversizedResponse }
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query(role: role) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query(role: role)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw keychainError(added) }
        } else if status != errSecSuccess { throw keychainError(status) }
    }
    private func keychainError(_ status: OSStatus) -> Error {
        if status == errSecInteractionNotAllowed || status == errSecNotAvailable { return OnlineError.locked }
        return SessionStorageError.keychainFailure(status)
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw SessionStorageError.unavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw SessionStorageError.unavailable }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}

enum SessionStorageError: Error, LocalizedError {
    case unavailable
    case keychainFailure(OSStatus)
    var errorDescription: String? { "Secure account storage is unavailable. Saved scores are unchanged." }
}
