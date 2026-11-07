@testable import AppBundle
import XCTest

@MainActor
final class WindowBordersConfigTest: XCTestCase {
    func testDinkyConfigurationSupportsFractionalWidthAlphaAndExclusions() {
        let (config, errors) = parseConfig("""
        [borders]
        enabled = true
        width = 4.5
        active-color = '#e1e3e480'
        inactive-color = '#494d64'
        order = 'above'
        exclude-apps = ['com.apple.finder', 'com.mitchellh.ghostty']
        """)
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        XCTAssertEqual(config.windowBorders.width, 4.5)
        XCTAssertEqual(config.windowBorders.activeColor, "#E1E3E480")
        XCTAssertEqual(config.windowBorders.order, .above)
        XCTAssertEqual(config.windowBorders.excludeApps, ["com.apple.finder", "com.mitchellh.ghostty"])
    }

    func testDefaultsAndZeroWidthAreAccepted() {
        let (config, errors) = parseConfig("[borders]\nwidth = 0")
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(config.windowBorders.width, 0)
        XCTAssertEqual(config.windowBorders.activeColor, "accent")
        XCTAssertEqual(config.windowBorders.inactiveColor, "#00000000")
        XCTAssertEqual(config.windowBorders.order, .below)
        XCTAssertTrue(config.windowBorders.enabled)
    }

    func testAccentIsAcceptedForEitherColorAndResolvesOpaque() {
        let (config, errors) = parseConfig("[borders]\nactive-color = 'Accent'\ninactive-color = 'accent'")
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        XCTAssertEqual(config.windowBorders.activeColor, "accent")
        XCTAssertEqual(config.windowBorders.inactiveColor, "accent")
        XCTAssertEqual(windowBorderRGBA("accent") & 255, 255)
    }

    func testHexColorsResolveToRGBA() {
        XCTAssertEqual(windowBorderRGBA("#E1E3E4"), 0xE1E3_E4FF)
        XCTAssertEqual(windowBorderRGBA("#E1E3E480"), 0xE1E3_E480)
        XCTAssertEqual(windowBorderRGBA("#00000000"), 0)
        XCTAssertEqual(windowBorderRGBA("#XYZXYZ"), 0x0000_00FF)
    }

    func testInvalidBorderSettingsAreRejected() {
        for setting in ["width = -1", "width = nan", "order = 'front'", "active-color = '#xyzxyz'", "active-color = 'accentx'",
                        "inactive-color = '#12345'", "exclude-apps = [42]"] {
            let (_, errors) = parseConfig("[borders]\n\(setting)")
            XCTAssertFalse(errors.isEmpty, setting)
        }
    }
}
