import AppKit
import Common
import XCTest
@testable import AppBundle
@testable import NativeSpaces

@MainActor
final class WorkspaceSidebarNativeSpacesTest: WorkspaceTestCase {
    override func setUp() async throws {
        try await super.setUp()
        runtime.workspaceBackend.selectForStartup(.native)
    }

    private func observe(active: String) -> TestMonitor {
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let monitor = TestMonitor(displayUUID: "display-a", monitorAppKitNsScreenScreensId: 1,
            name: "display-a", rect: rect, visibleRect: rect, isMain: true)
        setMonitorsForTests([monitor])
        let snapshot = NativeSpacesSnapshot(displays: [
            NativeSpaceDisplay(identifier: "display-a", activeSpaceID: active, spaces: [
                NativeSpace(id: "1", uuid: "desktop-a", type: 0), NativeSpace(id: "9", uuid: "full", type: 4),
                NativeSpace(id: "2", uuid: "desktop-b", type: 0),
            ]),
        ], windows: [], readMilliseconds: 0, capturedAt: .now)
        var inventory = NativeWorkspaceInventory()
        XCTAssertTrue(inventory.publish(snapshot, for: inventory.invalidate()))
        runtime.workspaceBackend.native.layouts.reconcile(inventory, displays: [monitor])
        return monitor
    }

    func testRowsListDesktopsInControlNumberOrderWithLabelsAndActiveState() async throws {
        let monitor = observe(active: "2")
        let rows = await runtime.workspaceBackend.ui.sidebarWorkspaces(
            currentFocus: focus, labels: ["2": "Mail"], monitors: [monitor])
        XCTAssertEqual(rows.map(\.displayName), ["Desktop 1", "Mail"], "Fullscreen Spaces are not desktops")
        XCTAssertEqual(rows.map(\.isVisible), [false, true])
        XCTAssertEqual(nativeDesktopNumber(forSidebarWorkspace: rows[1].name), 2)
        XCTAssertNil(nativeDesktopNumber(forSidebarWorkspace: "1"), "Virtual names are not native rows")
    }

    func testWindowsOnDesktopsNotShowingAreListedUnderTheirDesktop() async {
        let monitor = observe(active: "1")
        NativeUnvisitedWindows.shared.set([NativeListedWindow(windowId: 4242, spaceID: "2", pid: getpid(), title: "Report")])
        defer { NativeUnvisitedWindows.shared.set([]) }
        let rows = await buildNativeWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus, workspaceLabels: [:], availableMonitors: [monitor])
        XCTAssertEqual(rows.map { $0.items.map(\.id) }, [[], ["window:4242"]])
        XCTAssertEqual(NativeUnvisitedWindows.shared.spaceID(of: 4242), "2")
    }

    func testVirtualOnlyEditsExplainInsteadOfMutating() throws {
        _ = observe(active: "1")
        let before = Workspace.all.map(\.name)
        MessageModel.shared.message = nil
        handleWorkspaceSidebarAction(.deleteWorkspace("__native_space_desktop-a"))
        XCTAssertTrue(try XCTUnwrap(MessageModel.shared.message).body.contains("Mission Control"))
        XCTAssertEqual(Workspace.all.map(\.name), before)
    }

    func testRenamingADesktopLabelsItsNumber() async throws {
        let monitor = observe(active: "1")
        let rows = await buildNativeWorkspaceSidebarWorkspaceViewModels(
            currentFocus: focus, workspaceLabels: [:], availableMonitors: [monitor])
        renameNativeDesktop(try XCTUnwrap(nativeDesktopNumber(forSidebarWorkspace: rows[0].name)), to: "  Mail ")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(nativeDesktopDisplayName(1), "Mail")
        renameNativeDesktop(1, to: "")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(nativeDesktopDisplayName(1), "Desktop 1", "An empty name restores the default")
    }
}
