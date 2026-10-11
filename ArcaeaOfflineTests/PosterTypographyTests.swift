import XCTest
import UIKit
@testable import ArcaeaOffline

@MainActor final class PosterTypographyTests: XCTestCase {
    func testExportFontFilesAreBundledForOfflineUse() {
        for name in ["Exo", "Exo2", "OpenSans", "TitilliumWeb-Regular", "TitilliumWeb-SemiBold", "TitilliumWeb-Bold"] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts"), name)
        }
    }
    func testFontFamiliesLoadInsteadOfSystemFallback() {
        for (family, expected) in [(PosterTypography.Family.exo, "Exo"), (.exo2, "Exo 2"), (.titillium, "Titillium Web"), (.openSans, "Open Sans")] {
            for weight in [UIFont.Weight.regular, .semibold, .bold] {
                let font = PosterTypography.font(family, size: 26, weight: weight)
                XCTAssertEqual(font.familyName, expected)
                XCTAssertEqual(font.pointSize, 26)
            }
        }
    }
    func testPotentialDecimalIsSmallerWithoutChangingItsValue() throws {
        let text = PosterTypography.potential("13.000")
        XCTAssertEqual(text.string, "13.000")
        let whole = try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        let fraction = try XCTUnwrap(text.attribute(.font, at: 2, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(whole.familyName, "Exo")
        XCTAssertEqual(fraction.familyName, "Exo")
        XCTAssertEqual(fraction.pointSize / whole.pointSize, 16.0 / 22, accuracy: 0.001)
        XCTAssertEqual(PosterTypography.potential("—").string, "—")
    }

}
