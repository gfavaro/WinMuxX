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
        runtime.workspaceBackend.native.layouts.reconcile(inventory, displays: [monitor])
    }

    func testNativeUsesTheVirtualMenuWithDesktopsAndUnavailableItemsDisabled() throws {
        let previousMode = activeMode
        defer { activeMode = previousMode }
        activeMode = mainModeId
        config.workspaceSidebar.workspaceLabels = ["2": "Mail"]
        config.modes[mainModeId] = parseConfig("""
        [mode.main.binding]
        alt-2 = 'workspace 2'
        """).config.modes[mainModeId]
        _ = try XCTUnwrap(runtime.workspaceBackend.native.layouts.retainedByUUID["desktop-b"]).focusWorkspace()
        let menu = NSMenu()
        NativeActionMenu().menuNeedsUpdate(menu)
        let titles = menu.items.map(\.title)
        XCTAssertEqual(titles.first, "WinMuxX · Mail")
        for title in ["Dwindle", "Fullscreen", "Balance Sizes", "Commands", "Settings…", "Enabled", "Quit WinMuxX"] {
            XCTAssertTrue(titles.contains(title), title)
        }
        let commands = try XCTUnwrap(menu.items.first { $0.title == "Commands" }?.submenu)
        for title in ["Workspaces", "Focus", "Move Window", "Join With", "Resize", "Container Layout", "Refresh Desktops", "Reload Config"] {
            XCTAssertTrue(commands.items.contains { $0.title == title }, title)
        }
        let workspaces = try XCTUnwrap(commands.items.first { $0.title == "Workspaces" }?.submenu)
        let mail = try XCTUnwrap(workspaces.items.first { $0.title == "Mail" })
        XCTAssertEqual(mail.state, .on)
        XCTAssertEqual(mail.keyEquivalent, "2")
        XCTAssertTrue(workspaces.items.contains { $0.title == "Desktop 1" })
        let layout = try XCTUnwrap(commands.items.first { $0.title == "Container Layout" }?.submenu)
        XCTAssertEqual(layout.items.first { $0.title == "Accordion" }?.toolTip, "layout accordion", "Accordion overlaps natively")
        XCTAssertNil(menu.items.first { $0.title == "Enabled" }?.toolTip.flatMap { $0 == "Not available with native Spaces" ? $0 : nil },
            "enable pauses and resumes native tiling")
        XCTAssertNotEqual(menu.items.first { $0.title.hasPrefix("No Peek") }?.toolTip, "Not available with native Spaces")
        XCTAssertTrue(NativeCommandPolicy.runsOutsideNativeTilingFence(try XCTUnwrap(parseCommand("no-peek").cmdOrNil)))
        XCTAssertTrue(runtime.workspaceBackend.accepts(try XCTUnwrap(parseCommand("no-peek").cmdOrNil)))
        XCTAssertTrue(runtime.workspaceBackend.accepts(try XCTUnwrap(parseCommand("retile").cmdOrNil)))
    }
}
