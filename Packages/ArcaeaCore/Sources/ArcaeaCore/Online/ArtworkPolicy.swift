import Foundation

public enum ArtworkPolicy {
    public static func validIdentifier(_ value: String) -> Bool {
        // Only opaque official asset identifiers, never supplied URLs or traversals.
        value.utf8.count <= 512 && value.range(of: #"^[a-zA-Z0-9_-][a-zA-Z0-9_.-]*(/[a-zA-Z0-9_-][a-zA-Z0-9_.-]*)*$"#, options: .regularExpression) != nil
    }
}
