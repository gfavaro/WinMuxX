@testable import AppBundle
import XCTest

@MainActor
final class AccentColorConfigTest: XCTestCase {
    override func tearDown() async throws {
        config.accentColor = nil
    }

    func testAccentColorIsOptionalAndNormalized() {
        XCTAssertNil(parseConfig("").config.accentColor)
        let (parsed, errors) = parseConfig("accent-color = '7aa2f7'")
        XCTAssertTrue(errors.isEmpty, "\(errors)")
        XCTAssertEqual(parsed.accentColor, "#7AA2F7")
    }

    func testInvalidAccentColorsAreRejected() {
        for value in ["'#7aa2f780'", "'accent'", "'#12345'", "42"] {
            XCTAssertFalse(parseConfig("accent-color = \(value)").errors.isEmpty, value)
        }
    }

    func testAccentBordersAndModeIndicatorsFollowAccentColor() {
        config.accentColor = "#7AA2F7"
        XCTAssertEqual(windowBorderRGBA("accent"), 0x7AA2_F7FF)
        let indicator = ModePresentation(name: "navigation", mode: .zero).color(dark: true, increasedContrast: false)
        XCTAssertEqual(indicator.redComponent, 0x7A / 255, accuracy: 0.01)
        XCTAssertEqual(indicator.blueComponent, 0xF7 / 255, accuracy: 0.01)
    }
}
