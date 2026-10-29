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
        for title in ["Workspaces", "Focus", "Move Window", "Join With", "Resize", "Layout", "Fullscreen", "Balance Sizes",
                      "Workspace Controls…", "Refresh Desktops", "Reload Config", "Settings…", "Enabled", "Quit WinMuxX"] {
            XCTAssertTrue(titles.contains(title), title)
        }
        let workspaces = try XCTUnwrap(menu.items.first { $0.title == "Workspaces" }?.submenu)
        let mail = try XCTUnwrap(workspaces.items.first { $0.title == "Mail" })
        XCTAssertEqual(mail.state, .on)
        XCTAssertEqual(mail.keyEquivalent, "2")
        XCTAssertTrue(workspaces.items.contains { $0.title == "Desktop 1" })
        let layout = try XCTUnwrap(menu.items.first { $0.title == "Layout" }?.submenu)
        XCTAssertEqual(layout.items.first { $0.title == "Accordion" }?.toolTip, "layout accordion", "Accordion overlaps natively")
        XCTAssertNil(menu.items.first { $0.title == "Enabled" }?.toolTip.flatMap { $0 == "Not available with native Spaces" ? $0 : nil },
            "enable pauses and resumes native tiling")
        XCTAssertEqual(menu.items.first { $0.title == "Workspace Controls…" }?.isEnabled, false)
        for title in ["No Peek", "Clean Space"] {
            XCTAssertNotEqual(menu.items.first { $0.title.hasPrefix(title) }?.toolTip, "Not available with native Spaces", title)
        }
        let present = try XCTUnwrap(parseCommand("presentation toggle").cmdOrNil)
        XCTAssertTrue(runtime.workspaceBackend.accepts(present))
        XCTAssertTrue(NativeCommandPolicy.runsOutsideNativeTilingFence(present),
                      "Clean Space focuses first, which revokes permits inside the fence")
        XCTAssertTrue(NativeCommandPolicy.runsOutsideNativeTilingFence(try XCTUnwrap(parseCommand("no-peek").cmdOrNil)))
        XCTAssertTrue(runtime.workspaceBackend.accepts(try XCTUnwrap(parseCommand("no-peek").cmdOrNil)))
        XCTAssertTrue(runtime.workspaceBackend.accepts(try XCTUnwrap(parseCommand("retile").cmdOrNil)))
    }
}
