@testable import AppBundle
import Common
import XCTest

/// Every key the Settings window writes must land as TOML the parser reads back.
@MainActor
final class SettingsNewKeysTest: XCTestCase {
    private func write(_ text: String, _ edits: [(String?, String, String)]) -> Config {
        let result = applyingSettingsConfigEdits(edits.map { SettingsConfigEdit(section: $0.0, key: $0.1, renderedValue: $0.2) }, to: text)
        let parsed = parseConfig(result)
        XCTAssertEqual(parsed.errors.descriptions, [], result)
        return parsed.config
    }

    func testSettingsWritesForEveryNewKeyParseBack() {
        let config = write("", [
            ("master", "size", "0.7"), ("master", "side", "'right'"), ("master", "stack-layout", "'accordion'"),
            ("master", "ultrawide-mains", "2"),
            ("scrolling", "center-focused-column", "'on-overflow'"),
            ("scrolling", "minimap-hold-modifiers", tomlCommaSeparatedStringArray("ctrl, alt")),
            ("hover-bar", "enabled", "false"),
            ("dimming", "inactive-windows", "0.25"),
            ("follow-app-activation", "enabled", "false"),
            ("follow-app-activation", "exclude-apps", tomlCommaSeparatedStringArray("com.apple.finder")),
        ])
        XCTAssertEqual(config.master.size, 0.7)
        XCTAssertEqual(config.master.side, .right)
        XCTAssertEqual(config.master.stackLayout, .stacked)
        XCTAssertEqual(config.master.ultrawideMains, 2)
        XCTAssertEqual(config.scrolling.centerFocusedColumn, .onOverflow)
        XCTAssertEqual(config.scrolling.minimapHoldModifiers, [.control, .option])
        XCTAssertFalse(config.hoverBar.enabled)
        XCTAssertEqual(config.dimming.inactiveWindows, 0.25)
        XCTAssertFalse(config.followAppActivation.enabled)
        XCTAssertEqual(config.followAppActivation.excludeApps, ["com.apple.finder"])
    }

    func testFollowAppActivationWrittenAsABooleanBecomesATable() {
        let config = write("follow-app-activation = false\n", [("follow-app-activation", "exclude-apps", "['com.apple.finder']")])
        XCTAssertEqual(config.followAppActivation.excludeApps, ["com.apple.finder"])
        XCTAssertFalse(config.followAppActivation.enabled, "The shorthand's value is kept as enabled")
    }

    func testMinimapHoldKeysRoundTripAndRejectUnknownNames() {
        XCTAssertEqual(minimapHoldModifierNames([.option, .control]), "ctrl, alt")
        XCTAssertNil(minimapHoldModifierError("ctrl, alt"))
        XCTAssertNil(minimapHoldModifierError(""))
        XCTAssertNotNil(minimapHoldModifierError("ctrl, hyper"))
    }
}
