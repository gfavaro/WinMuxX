import AppKit
import Common
import XCTest
@testable import AppBundle
@testable import NativeSpaces

@MainActor
final class NativeSpaceLayoutsTest: WorkspaceTestCase {
    override func setUp() async throws {
        try await super.setUp()
        runtime.workspaceBackend.selectForStartup(.native)
    }
    private func display(_ uuid: String, x: CGFloat = 0) -> TestMonitor {
        let rect = Rect(topLeftX: x, topLeftY: 0, width: 1920, height: 1080)
        return TestMonitor(displayUUID: uuid, monitorAppKitNsScreenScreensId: x == 0 ? 1 : 2,
            name: uuid, rect: rect, visibleRect: rect, isMain: x == 0)
    }

    private func inventory(active: String = "1", firstID: String = "1", firstUUID: String? = "desktop-a",
                           firstType: Int = 0, displayID: String = "display-a") -> NativeWorkspaceInventory {
        let snapshot = NativeSpacesSnapshot(displays: [
            NativeSpaceDisplay(identifier: displayID, activeSpaceID: active, spaces: [
                NativeSpace(id: firstID, uuid: firstUUID, type: firstType),
                NativeSpace(id: "2", uuid: "desktop-b", type: 0),
            ]),
        ], windows: [NativeWindowMembership(windowID: 10, spaceIDs: [firstID]),
            NativeWindowMembership(windowID: 20, spaceIDs: ["2"])], readMilliseconds: 0, capturedAt: .now)
        var inventory = NativeWorkspaceInventory()
        XCTAssertTrue(inventory.publish(snapshot, for: inventory.invalidate()))
        return inventory
    }

    func testSpaceSwitchRetainsIndependentNestedTabsFloatingWindowsAndLayout() throws {
        let monitor = display("display-a")
        setMonitorsForTests([monitor])
        let layouts = NativeSpaceLayouts()
        layouts.reconcile(inventory(), displays: [monitor])
        let first = try XCTUnwrap(layouts.currentBySpaceID["1"])
        let second = try XCTUnwrap(layouts.currentBySpaceID["2"])
        let root = first.rootTilingContainer
        let tabs = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tabGroup, index: 0)
        let a = TestWindow.new(id: 10, parent: tabs)
        let b = TestWindow.new(id: 11, parent: tabs)
        let floating = TestWindow.new(id: 12, parent: first)
        first.arrangement = .master
        second.arrangement = .dwindle
        layouts.reconcile(inventory(active: "2"), displays: [monitor])
        XCTAssertTrue(runtime.workspaces.visibleWorkspace(for: monitor) === second)
        XCTAssertNil(layouts.workspace(for: 10, on: "display-a"))
        XCTAssertTrue(layouts.workspace(for: 20, on: "display-a") === second)
        layouts.reconcile(inventory(), displays: [monitor])
        XCTAssertTrue(layouts.currentBySpaceID["1"] === first)
        XCTAssertTrue(first.rootTilingContainer === root)
        XCTAssertTrue(root.children.first === tabs)
        XCTAssertEqual(tabs.layout, .tabGroup)
        XCTAssertEqual(tabs.children.map { ($0 as? Window)?.windowId }, [a.windowId, b.windowId])
        XCTAssertTrue(first.floatingWindows.first === floating)
        XCTAssertEqual(first.arrangement, .master)
        XCTAssertEqual(second.arrangement, .dwindle)
    }

    func testRenumberedSpaceKeepsUUIDLayoutAndRemovedSpaceIsRetainedWithoutVisibility() throws {
        let monitor = display("display-a")
        let layouts = NativeSpaceLayouts()
        layouts.reconcile(inventory(), displays: [monitor])
        let first = try XCTUnwrap(layouts.currentBySpaceID["1"])
        let root = first.rootTilingContainer
        layouts.reconcile(inventory(active: "99", firstID: "99"), displays: [monitor])
        XCTAssertTrue(layouts.currentBySpaceID["99"] === first)
        XCTAssertTrue(first.rootTilingContainer === root)
        XCTAssertNil(layouts.currentBySpaceID["1"])
        layouts.reconcile(inventory(firstUUID: "different-desktop"), displays: [monitor])
        XCTAssertTrue(layouts.retainedByUUID["desktop-a"] === first)
        XCTAssertFalse(first.isVisible)
    }

    func testInvalidationRevokesMembershipBeforeReplacingLastObservedViewport() throws {
        let monitor = display("display-a")
        let layouts = NativeSpaceLayouts()
        var observed = inventory()
        layouts.reconcile(observed, displays: [monitor])
        let first = try XCTUnwrap(layouts.currentBySpaceID["1"])
        observed.invalidate()
        layouts.reconcile(observed, displays: [monitor])
        XCTAssertNil(layouts.snapshot)
        XCTAssertTrue(layouts.currentBySpaceID.isEmpty)
        XCTAssertTrue(first.isVisible) // Last observation only, never write authority.
        XCTAssertTrue(layouts.retainedByUUID["desktop-a"] === first)
        XCTAssertNil(layouts.activeWorkspace(on: "display-a"))
        XCTAssertNil(layouts.workspace(for: 10, on: "display-a"))
        observed.stop()
        layouts.reconcile(observed, displays: [monitor])
        XCTAssertFalse(first.isVisible)
    }

    func testNoGuessedDisplayOrUUIDAndFullscreenIsUnmanaged() {
        let monitor = display("display-a")
        let layouts = NativeSpaceLayouts()
        layouts.reconcile(inventory(displayID: "missing"), displays: [monitor])
        XCTAssertTrue(layouts.currentBySpaceID.isEmpty)
        layouts.reconcile(inventory(firstUUID: nil), displays: [monitor])
        XCTAssertNil(layouts.currentBySpaceID["1"])
        XCTAssertNil(runtime.workspaces.visibleWorkspace(for: monitor))
        layouts.reconcile(inventory(firstType: 4), displays: [monitor])
        XCTAssertNil(layouts.currentBySpaceID["1"])
        XCTAssertNil(layouts.workspace(for: 10, on: "display-a"))
    }

    func testAXRegistrationCannotCommitAfterAnyNewObservationEvenWithSameTimestamp() throws {
        let monitor = display("display-a")
        let layouts = runtime.workspaceBackend.nativeLayouts
        let observed = inventory()
        layouts.reconcile(observed, displays: [monitor])
        let old = try XCTUnwrap(layouts.registration(for: 10))
        XCTAssertTrue(layouts.accepts(old))
        layouts.reconcile(observed, displays: [monitor]) // Identical capturedAt and tree.
        XCTAssertFalse(layouts.accepts(old))
        let current = try XCTUnwrap(layouts.registration(for: 10))
        XCTAssertTrue(current.workspace === old.workspace)
        XCTAssertTrue(layouts.accepts(current))
        var pending = observed
        pending.invalidate()
        layouts.reconcile(pending, displays: [monitor])
        XCTAssertFalse(layouts.accepts(current))
        XCTAssertNil(layouts.registration(for: 10))
    }

    func testSwitchOnOneDisplayPreservesOtherDisplaysHistoryAndTrees() throws {
        let displays = [display("a"), display("b", x: 1920), display("c", x: 3840)]
        setMonitorsForTests(displays)
        let layouts = runtime.workspaceBackend.nativeLayouts
        func observed(a: String, b: String) -> NativeWorkspaceInventory {
            let rows: [(String, String, [String])] = [("a", a, ["1", "4"]), ("b", b, ["2", "5"]), ("c", "3", ["3"])]
            let snapshot = NativeSpacesSnapshot(displays: rows.map { uuid, active, ids in
                NativeSpaceDisplay(identifier: uuid, activeSpaceID: active,
                    spaces: ids.map { NativeSpace(id: $0, uuid: "desktop-\($0)", type: 0) })
            }, windows: [], readMilliseconds: 0, capturedAt: .now)
            var inventory = NativeWorkspaceInventory()
            XCTAssertTrue(inventory.publish(snapshot, for: inventory.invalidate()))
            return inventory
        }
        layouts.reconcile(observed(a: "1", b: "5"), displays: displays)
        layouts.reconcile(observed(a: "1", b: "2"), displays: displays)
        let b = try XCTUnwrap(layouts.activeWorkspace(on: "b"))
        let c = try XCTUnwrap(layouts.activeWorkspace(on: "c"))
        let beforeB = runtime.workspaces.monitorViewportsById[MonitorViewportId(displays[1])]
        let beforeC = runtime.workspaces.monitorViewportsById[MonitorViewportId(displays[2])]
        var latest = observed(a: "4", b: "2")
        latest.invalidate()
        layouts.reconcile(latest, displays: displays)
        XCTAssertNil(layouts.activeWorkspace(on: "b"))
        layouts.reconcile(observed(a: "4", b: "2"), displays: displays)
        XCTAssertTrue(layouts.activeWorkspace(on: "b") === b)
        XCTAssertTrue(layouts.activeWorkspace(on: "c") === c)
        let afterB = runtime.workspaces.monitorViewportsById[MonitorViewportId(displays[1])]
        let afterC = runtime.workspaces.monitorViewportsById[MonitorViewportId(displays[2])]
        XCTAssertEqual(afterB?.activeWorkspaceId, beforeB?.activeWorkspaceId)
        XCTAssertEqual(afterB?.previousWorkspaceId, beforeB?.previousWorkspaceId)
        XCTAssertEqual(afterC?.activeWorkspaceId, beforeC?.activeWorkspaceId)
        XCTAssertEqual(afterC?.previousWorkspaceId, beforeC?.previousWorkspaceId)
        XCTAssertEqual(afterB?.lastActiveWorkspaceByProject, beforeB?.lastActiveWorkspaceByProject)
    }
}
