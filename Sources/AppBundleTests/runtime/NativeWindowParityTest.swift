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

    func testMoveRulesSkipWindowsThatExistedAtLaunchEvenWhenFirstSeenLater() async throws {
        config.onWindowDetected = parseConfig("""
        [[on-window-detected]]
        run = 'move-node-to-workspace 3'
        """).config.onWindowDetected
        var scheduled: [UInt32] = []
        let original = nativeRuleMoveScheduler
        nativeRuleMoveScheduler = { _, id in scheduled.append(id) }
        defer { nativeRuleMoveScheduler = original }
        runtime.workspaceBackend.windowsPresentAtLaunch = [50]
        let workspace = Workspace.get(byName: "native-desktop")
        try await applyNativeWindowDetectedRules(TestWindow.new(id: 50, parent: workspace.rootTilingContainer)) { true }
        try await applyNativeWindowDetectedRules(TestWindow.new(id: 51, parent: workspace.rootTilingContainer)) { true }
        XCTAssertEqual(scheduled, [51], "Only the window opened after launch moves")
    }
}
