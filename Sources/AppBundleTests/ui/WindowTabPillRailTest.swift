@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WindowTabPillRailTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func tabs(active: UInt32) -> [WindowTabItemViewModel] {
        [1, 2, 3].map { windowId in
            WindowTabItemViewModel(windowId: UInt32(windowId), workspaceName: "a", appName: "App", appBundleId: nil,
                appBundlePath: nil, title: windowId == 2 ? "" : "Window \(windowId)", isActive: UInt32(windowId) == active)
        }
    }

    func testPillsStraddleTheGroupsTopEdgeAtItsCentre() {
        let group = CGRect(x: 100, y: 200, width: 600, height: 300)
        let frame = windowTabPillPanelFrame(groupFrame: group, tabs: tabs(active: 1), shownWindowIds: [1, 2])
        XCTAssertEqual(frame.midX, group.midX, accuracy: 1)
        XCTAssertLessThan(frame.minY, group.maxY, "Half lies over the window's top edge")
        XCTAssertGreaterThan(frame.maxY, group.maxY, "and half in the gap above it")
        let pills = windowTabPillWidth(isActive: true, isShown: true) + windowTabPillWidth(isActive: false, isShown: true)
            + windowTabPillWidth(isActive: false, isShown: false) + 2 * windowTabPillSpacing
        XCTAssertEqual(frame.width, pills + 4, accuracy: 1)
        XCTAssertGreaterThan(windowTabPillWidth(isActive: true, isShown: true), windowTabPillWidth(isActive: false, isShown: true))
        XCTAssertGreaterThan(windowTabPillWidth(isActive: false, isShown: true), windowTabPillWidth(isActive: false, isShown: false))
    }

    func testPillsStayAboveWindowsButBelowOverlays() {
        let pills = WinMuxPanelLayer.windowIndicator.level.rawValue
        XCTAssertGreaterThan(pills, NSWindow.Level.normal.rawValue, "A window coming to the front must not hide its pills")
        XCTAssertLessThan(pills, WinMuxPanelLayer.overlay.level.rawValue)
        XCTAssertLessThan(pills, WinMuxPanelLayer.workspaceSidebar.level.rawValue)
    }

    func testHoverBarListsTheGroupsTabsForATabbedWindow() {
        config.windowTabs.enabled = true
        let workspace = Workspace.get(byName: name)
        let group = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        let first = TestWindow.new(id: 1, parent: group)
        _ = TestWindow.new(id: 2, parent: group)
        let lone = TestWindow.new(id: 9, parent: workspace.rootTilingContainer)
        let previous = TrayMenuModel.shared.windowTabStrips
        defer { TrayMenuModel.shared.windowTabStrips = previous }
        TrayMenuModel.shared.windowTabStrips = [WindowTabStripViewModel(id: ObjectIdentifier(group), workspaceName: workspace.name,
            frame: .zero, groupFrame: .zero, activeWindowId: 1, activeWindowCornerRadius: 10, tabs: tabs(active: 1),
            occludingFloatingWindowFrames: [], shownWindowIds: [1])]

        let barTabs = WindowHoverBar.tabs(for: first)
        XCTAssertEqual(barTabs.map(\.windowId), [1, 2, 3])
        XCTAssertEqual(barTabs.map(\.title), ["Window 1", "App", "Window 3"], "An untitled window shows its app's name")
        XCTAssertEqual(barTabs.filter(\.isActive).map(\.windowId), [1])
        XCTAssertTrue(WindowHoverBar.tabs(for: lone).isEmpty, "A window outside a tab group gets only its actions")
    }

    func testTabStyleChoosesPillsOrAStripThatTakesItsHeight() async throws {
        let previous = config.windowTabs
        defer { config.windowTabs = previous }
        XCTAssertEqual(parseConfig("[window-tabs]\nstyle = 'tabs'").config.windowTabs.style, .tabs)
        XCTAssertEqual(WindowTabsConfig().style, .pills, "Pills are the default")
        XCTAssertFalse(parseConfig("[window-tabs]\nstyle = 'ribbon'").errors.isEmpty)

        config.windowTabs.enabled = true
        let workspace = Workspace.get(byName: name)
        let group = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        let first = TestWindow.new(id: 1, parent: group)
        _ = TestWindow.new(id: 2, parent: group)
        first.markAsMostRecentChild()

        config.windowTabs.style = .pills
        try await workspace.layoutWorkspace()
        let groupTop = try XCTUnwrap(group.lastAppliedLayoutPhysicalRect).minY
        XCTAssertEqual(try XCTUnwrap(first.lastAppliedLayoutPhysicalRect).minY, groupTop, "Pills take no space")

        config.windowTabs.style = .tabs
        try await workspace.layoutWorkspace()
        XCTAssertEqual(try XCTUnwrap(first.lastAppliedLayoutPhysicalRect).minY, groupTop + resolvedWindowTabBarHeight(),
            "A tab strip takes its height above the windows")

        let previousStrips = TrayMenuModel.shared.windowTabStrips
        defer { TrayMenuModel.shared.windowTabStrips = previousStrips }
        TrayMenuModel.shared.windowTabStrips = [WindowTabStripViewModel(id: ObjectIdentifier(group), workspaceName: workspace.name,
            frame: .zero, groupFrame: .zero, activeWindowId: 1, activeWindowCornerRadius: 10, tabs: tabs(active: 1),
            occludingFloatingWindowFrames: [], shownWindowIds: [1])]
        XCTAssertTrue(WindowHoverBar.tabs(for: first).isEmpty, "With a strip on screen the hover bar shows only actions")
        config.windowTabs.style = .pills
        XCTAssertFalse(WindowHoverBar.tabs(for: first).isEmpty)
    }

    func testShortcutHintsUseMenuSymbols() throws {
        let previousMode = activeMode
        defer { activeMode = previousMode }
        activeMode = mainModeId
        config.modes[mainModeId] = parseConfig("""
        shortcuts-preset = 'none'
        [mode.main.binding]
        ctrl-alt-z = 'fullscreen'
        ctrl-alt-shift-left = 'swap-with-master'
        """).config.modes[mainModeId]
        let focusAction = HoverBarAction(title: "Focus", symbol: "", command: "fullscreen --window-id 1", shortcut: "fullscreen")
        let mainAction = HoverBarAction(title: "Main", symbol: "", command: "swap-with-master --window-id 1", shortcut: "swap-with-master")
        let floatAction = HoverBarAction(title: "Float", symbol: "", command: "layout floating tiling --window-id 1", shortcut: "layout floating tiling")
        XCTAssertEqual(WindowHoverBar.shortcutHint(for: focusAction), "⌃⌥Z")
        XCTAssertEqual(WindowHoverBar.shortcutHint(for: mainAction), "⌃⌥⇧←")
        XCTAssertNil(WindowHoverBar.shortcutHint(for: floatAction), "An unbound action shows no hint")
    }

    func testStripLayoutRecordsItsVisibleColumnsForThePills() async throws {
        let workspace = Workspace.get(byName: name)
        let strip = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tabGroup, index: 0)
        strip.presentsAsStrip = true
        let first = TestWindow.new(id: 8201, parent: strip)
        _ = TestWindow.new(id: 8202, parent: strip)
        _ = TestWindow.new(id: 8203, parent: strip)
        first.markAsMostRecentChild()
        try await workspace.layoutWorkspace()
        XCTAssertEqual(strip.stripVisibleColumns, 0 ..< 2)
    }
}
