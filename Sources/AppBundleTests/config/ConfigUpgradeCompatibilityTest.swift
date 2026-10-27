@testable import AppBundle
import Common
import XCTest

@MainActor
final class ConfigUpgradeCompatibilityTest: XCTestCase {
    func testWorkspaceLayoutStillAcceptsRootLayoutsFromBeforeArrangements() {
        let parsed = parseConfig("""
        [workspace.'1']
        layout = 'accordion'
        [workspace.'2']
        layout = 'scrolling'
        [workspace.'3'.display.'Built-in']
        layout = 'tiles'
        """)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        let first = parsed.config.workspaceLayouts["1"]?.defaults
        XCTAssertEqual(first?.layout, .dwindle)
        XCTAssertEqual(first?.rootLayout, .stacked)
        XCTAssertEqual(parsed.config.workspaceLayouts["2"]?.defaults.layout, .scrolling)
        XCTAssertNil(parsed.config.workspaceLayouts["2"]?.defaults.rootLayout)
        XCTAssertEqual(parsed.config.workspaceLayouts["3"]?.displays.first?.settings.rootLayout, .tiles)
        XCTAssertFalse(parseConfig("[workspace.'1']\nlayout = 'spiral'").errors.isEmpty)
    }

    func testOnlyAConfigAskingForNativeSpacesStartsReadOnlyWhenItFailsToParse() {
        XCTAssertTrue(configTextRequestsNativeBackend("[workspace-backend]\ntype = 'native'\n"))
        XCTAssertTrue(configTextRequestsNativeBackend("workspace-backend.type = \"native\" # opt in"))
        XCTAssertFalse(configTextRequestsNativeBackend("[workspace-backend]\n# type = 'native'\ntype = 'virtual'"))
        XCTAssertFalse(configTextRequestsNativeBackend("[gaps]\ntype = 'native'"), "Only the backend table counts")
        XCTAssertFalse(configTextRequestsNativeBackend("broken = = toml"))
    }
}
