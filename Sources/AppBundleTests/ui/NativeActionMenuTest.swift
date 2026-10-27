@testable import AppBundle
import AppKit
import Common
@testable import NativeSpaces
import XCTest

@MainActor
final class NativeActionMenuTest: WorkspaceTestCase {
    override func setUp() async throws {
        try await super.setUp()
        runtime.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let monitor = TestMonitor(displayUUID: "display-a", monitorAppKitNsScreenScreensId: 1,
            name: "display-a", rect: rect, visibleRect: rect, isMain: true)
        setMonitorsForTests([monitor])
        let snapshot = NativeSpacesSnapshot(displays: [
            NativeSpaceDisplay(identifier: "display-a", activeSpaceID: "2", spaces: [
                NativeSpace(id: "1", uuid: "desktop-a", type: 0), NativeSpace(id: "9", uuid: "full", type: 4),
                NativeSpace(id: "2", uuid: "desktop-b", type: 0),
            ]),
        ], windows: [], readMilliseconds: 0, capturedAt: .now)
        var inventory = NativeWorkspaceInventory()
        XCTAssertTrue(inventory.publish(snapshot, for: inventory.invalidate()))
        runtime.workspaceBackend.nativeLayouts.reconcile(inventory, displays: [monitor])
    }

    func testMenuListsDesktopsAndOnlyCommandsTheNativeBackendRuns() throws {
        let previousMode = activeMode
        defer { activeMode = previousMode }
        activeMode = mainModeId
        config.workspaceSidebar.workspaceLabels = ["2": "Mail"]
        config.modes[mainModeId] = parseConfig("""
        [mode.main.binding]
        alt-2 = 'workspace 2'
        alt-shift-2 = 'move-node-to-workspace 2'
        """).config.modes[mainModeId]
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        let titles = menu.items.map(\.title)
        XCTAssertEqual(titles.first, "WinMuxX · Mail")
        let desktop = try XCTUnwrap(menu.items.first { $0.title == "Mail" })
        XCTAssertEqual(desktop.state, .on)
        XCTAssertEqual(desktop.keyEquivalent, "2", "Registered navigation shortcuts are shown")
        XCTAssertEqual(menu.items.first { $0.title == "Desktop 1" }?.state, .off)
        XCTAssertEqual(menu.items.first { $0.title == "Fullscreen App" }?.isEnabled, false)
        for title in ["Previous Desktop", "Next Desktop", "Focus", "Move Window", "Resize", "Layout", "Fullscreen", "Balance Sizes", "Reload Config", "Quit WinMuxX"] {
            XCTAssertTrue(titles.contains(title), title)
        }
        for title in ["Workspaces", "Join With", "Settings…", "Enabled", "Workspace Controls…"] {
            XCTAssertFalse(titles.contains(title), title)
        }
        let layout = try XCTUnwrap(menu.items.first { $0.title == "Layout" }?.submenu).items.map(\.title)
        XCTAssertFalse(layout.contains("Tabbed") || layout.contains("Accordion") || layout.contains("Scrolling"))
    }
}
