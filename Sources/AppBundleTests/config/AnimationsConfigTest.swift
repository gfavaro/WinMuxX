@testable import AppBundle
import XCTest

@MainActor
final class AnimationsConfigTest: XCTestCase {
    func testDefaultsAndOverrides() {
        let (defaults, errors) = parseConfig("")
        XCTAssertTrue(errors.isEmpty)
        XCTAssertTrue(defaults.animations.enabled)
        XCTAssertEqual(defaults.animations.durationMs, 150)
        let (custom, customErrors) = parseConfig("[animations]\nenabled = false\nduration-ms = 120")
        XCTAssertTrue(customErrors.isEmpty)
        XCTAssertFalse(custom.animations.enabled)
        XCTAssertEqual(custom.animations.durationMs, 120)
    }

    func testInvalidDurationsAndTypes() {
        for value in ["-1", "2001", "1.5", "'fast'"] {
            XCTAssertFalse(parseConfig("[animations]\nduration-ms = \(value)").errors.isEmpty)
        }
        XCTAssertTrue(parseConfig("[animations]\nduration-ms = 0").errors.isEmpty)
    }
}
