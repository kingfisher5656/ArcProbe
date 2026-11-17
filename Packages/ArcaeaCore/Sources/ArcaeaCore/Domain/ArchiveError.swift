import Foundation

public enum ArchiveError: Error, Equatable, Sendable {
    case invalidRecord(String)
    case accountMismatch
    case identityCollision(String)
    case notFound(String)
    case staleUndo
    case unsupportedVersion(Int)
    case database(String)
    case oversizedBackup
}

extension ArchiveError: LocalizedError {
    /// Without this, a failed save reads "The operation couldn’t be completed" and nothing else.
    public var errorDescription: String? {
        switch self {
        case .invalidRecord(let message): message
        case .accountMismatch: localized("This data belongs to a different account. Nothing was saved.")
        case .identityCollision: localized("Two different plays claim to be the same one. Nothing was saved.")
        case .notFound: localized("That item is no longer in the archive.")
        case .staleUndo: localized("This change can no longer be undone.")
        case .unsupportedVersion(let version): String(format: localized("This archive or backup uses a format ArcProbe does not support (version %lld)."), version)
        case .database: localized("The archive could not be read or written. Saved data is unchanged.")
        case .oversizedBackup: localized("This backup is larger than ArcProbe can restore.")
        }
    }
}
