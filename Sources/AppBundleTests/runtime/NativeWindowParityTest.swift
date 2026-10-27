import Common
import XCTest
@testable import AppBundle

@MainActor
final class NativeWindowParityTest: WorkspaceTestCase {
    override func setUp() async throws {
        try await super.setUp()
        runtime.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        nativeSkippedWindowRuleCommands = []
    }

    func testPerWindowActionsAreNativeCommands() throws {
        for script in ["fullscreen", "macos-native-fullscreen", "macos-native-minimize", "close", "close-all-windows-but-current"] {
            let command = try XCTUnwrap(parseCommand(script).cmdOrNil, script)
            XCTAssertTrue(runtime.workspaceBackend.accepts(command), script)
        }
    }

    func testRulesFloatOrTileNewWindowsAndReportWhatTheySkip() async throws {
        config.onWindowDetected = parseConfig("""
        [[on-window-detected]]
        run = ['layout floating', 'move-node-to-monitor 2']
        """).config.onWindowDetected
        let workspace = Workspace.get(byName: "native-desktop")
        let window = TestWindow.new(id: 40, parent: workspace.rootTilingContainer)
        try await applyNativeWindowDetectedRules(window) { true }
        XCTAssertTrue(window.parent === workspace, "Floated on its own desktop")
        XCTAssertEqual(nativeSkippedWindowRuleCommands, ["move-node-to-monitor 2"])
    }

    func testRulesLeaveAWindowWhoseOwnershipChangedDuringMatching() async throws {
        config.onWindowDetected = parseConfig("""
        [[on-window-detected]]
        run = 'layout floating'
        """).config.onWindowDetected
        let workspace = Workspace.get(byName: "native-desktop")
        let window = TestWindow.new(id: 41, parent: workspace.rootTilingContainer)
        try await applyNativeWindowDetectedRules(window) { false }
        XCTAssertTrue(window.parent === workspace.rootTilingContainer)
    }
}
