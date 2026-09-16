import SwiftUI
import XCTest
@testable import Mono

@MainActor
final class BloudAppearanceTests: XCTestCase {
    func testCustomColorsKeepTextControlsAndEyesLegibleInBothAppearances() {
        for hex in ["000000", "FFFFFF", "FFFF00", "00FF00", "0000FF", "FF0066", "9470DB", "F7B354"] {
            for dark in [false, true] {
                let palette = BloudPalette(character: .bloud, customHex: hex, dark: dark, coverAccent: .red)
                XCTAssertGreaterThanOrEqual(ThemeColorCustomization.contrastRatio(between: palette.ink, and: palette.paper), 4.5)
                XCTAssertGreaterThanOrEqual(ThemeColorCustomization.contrastRatio(between: palette.secondary, and: palette.paper), 4.5)
                XCTAssertGreaterThanOrEqual(ThemeColorCustomization.contrastRatio(between: palette.eyes, and: palette.body), 4.5)
                XCTAssertGreaterThanOrEqual(ThemeColorCustomization.contrastRatio(between: palette.accent, and: palette.paper), 3)
                XCTAssertGreaterThanOrEqual(ThemeColorCustomization.contrastRatio(between: palette.onAccent, and: palette.accent), 4.5)
            }
        }
    }

    func testDefaultCompanionsKeepTheirOwnOriginalColors() {
        let bloud = BloudPalette(character: .bloud, customHex: "", dark: false, coverAccent: .red)
        let paw = BloudPalette(character: .paw, customHex: "", dark: false, coverAccent: .red)
        XCTAssertEqual(bloud.body.toHex(), "111214")
        XCTAssertEqual(paw.body.toHex(), "F4AE58")
        let cat = BloudPalette(character: .pawCat, customHex: "", dark: false, coverAccent: .red)
        XCTAssertEqual(cat.body.toHex(), "F4F2F3")
        XCTAssertNotEqual(bloud.paper.toHex(), paw.paper.toHex())
    }
}
