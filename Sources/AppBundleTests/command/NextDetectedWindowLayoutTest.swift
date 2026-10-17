@testable import AppBundle
import Common
import XCTest

@MainActor
final class NextDetectedWindowLayoutTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func schedule(_ layout: String) async throws {
        let command = try XCTUnwrap(parseCommand("layout \(layout) --for-next-detected-window").cmdOrNil as? LayoutCommand)
        XCTAssertFalse(command.shouldResetClosedWindowsCache)
        let result = try await command.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
    }

    func testParserAcceptsOnlyOneFloatingOrTilingLayoutAndNoWindowTarget() {
        for layout in ["floating", "tiling"] {
            XCTAssertNil(parseCommand("layout --for-next-detected-window \(layout)").errorOrNil)
        }
        for layout in ["tiles", "dwindle", "tab-group", "horizontal", "auto", "floating tiling"] {
            XCTAssertNotNil(parseCommand("layout \(layout) --for-next-detected-window").errorOrNil)
        }
        XCTAssertNotNil(parseCommand("layout floating --for-next-detected-window --window-id 1").errorOrNil)
    }

    func testScheduleWithoutFocusedWindowOnlyAffectsNextWindow() async throws {
        XCTAssertNil(focus.windowOrNil)
        try await schedule("floating")
        let parent = focus.workspace.rootTilingContainer
        let existing = TestWindow.new(id: 1, parent: parent)
        XCTAssertFalse(existing.isFloating)
        let next = TestWindow.new(id: 2, parent: parent)
        try await tryOnWindowDetected(next)
        XCTAssertTrue(next.isFloating)
        XCTAssertFalse(existing.isFloating)
        XCTAssertNil(layoutForNextDetectedWindow)
        let later = TestWindow.new(id: 3, parent: parent)
        try await tryOnWindowDetected(later)
        XCTAssertFalse(later.isFloating)
    }

    func testSecondScheduleReplacesFirst() async throws {
        try await schedule("floating")
        try await schedule("tiling")
        let window = TestWindow.new(id: 1, parent: focus.workspace)
        try await tryOnWindowDetected(window)
        XCTAssertFalse(window.isFloating)
        XCTAssertNil(layoutForNextDetectedWindow)
    }

    func testPopupsAndMinimizedWindowsDoNotConsumePendingLayout() async throws {
        try await schedule("floating")
        let popup = TestWindow.new(id: 1, parent: macosPopupWindowsContainer)
        let minimized = TestWindow.new(id: 2, parent: macosMinimizedWindowsContainer)
        try await tryOnWindowDetected(popup)
        try await tryOnWindowDetected(minimized)
        XCTAssertEqual(layoutForNextDetectedWindow, .floating)
        XCTAssertTrue(popup.parent === macosPopupWindowsContainer)
        XCTAssertTrue(minimized.parent === macosMinimizedWindowsContainer)
        let normal = TestWindow.new(id: 3, parent: focus.workspace.rootTilingContainer)
        try await tryOnWindowDetected(normal)
        XCTAssertTrue(normal.isFloating)
    }

    func testExplicitLayoutSurvivesCallbackMovingAndRetilingWindow() async throws {
        let wasEnabled = TrayMenuModel.shared.isEnabled
        defer { TrayMenuModel.shared.isEnabled = wasEnabled }
        TrayMenuModel.shared.isEnabled = true
        let parsed = parseConfig("""
        config-version = 2
        [[on-window-detected]]
        if.app-id = 'bobko.WinMux.test-app'
        run = ['layout tiling', 'move-node-to-workspace W']
        """)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        config.onWindowDetected = parsed.config.onWindowDetected
        try await schedule("floating")
        let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        try await tryOnWindowDetected(window)
        XCTAssertEqual(window.nodeWorkspace?.name, "W")
        XCTAssertTrue(window.isFloating)
    }
}
