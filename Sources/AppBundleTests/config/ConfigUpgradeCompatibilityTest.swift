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
        layout = 'master'
        [workspace.'3'.display.'Built-in']
        layout = 'tiles'
        """)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        let first = parsed.config.workspaceLayouts["1"]?.defaults
        XCTAssertEqual(first?.layout, .dwindle)
        XCTAssertEqual(first?.rootLayout, .tabGroup, "Accordion was removed and reads as a tab group")
        XCTAssertEqual(parsed.config.workspaceLayouts["2"]?.defaults.layout, .master)
        XCTAssertNil(parsed.config.workspaceLayouts["2"]?.defaults.rootLayout)
        XCTAssertEqual(parsed.config.workspaceLayouts["3"]?.displays.first?.settings.rootLayout, .tiles)
        XCTAssertFalse(parseConfig("[workspace.'1']\nlayout = 'spiral'").errors.isEmpty)
    }
}
