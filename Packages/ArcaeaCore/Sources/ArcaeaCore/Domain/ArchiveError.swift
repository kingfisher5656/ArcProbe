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
