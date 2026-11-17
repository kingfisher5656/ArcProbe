import Foundation

/// Wording meant for people, in their language where the app has a translation.
///
/// The package carries no translations of its own. They live in the app's string catalog (`scripts/check-strings.py`
/// collects the English strings from these calls), which is why the lookup goes to the
/// main bundle. In the package's own tests there is no catalog and the English text comes back unchanged.
func localized(_ english: String) -> String {
    Bundle.main.localizedString(forKey: english, value: english, table: nil)
}
