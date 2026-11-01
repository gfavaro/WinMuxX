import AppKit
import Common
import XCTest
@testable import AppBundle
@testable import NativeSpaces

@MainActor
final class NativeQueriesTest: WorkspaceTestCase {
    override func setUp() async throws {
        try await super.setUp()
        runtime.workspaceBackend.selectForStartup(.native)
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

    private func run(_ text: String) async throws -> CmdResult {
        try await parseCommand(text).cmdOrDie.run(.defaultEnv, .emptyStdin)
    }

    func testWorkspacesAreListedAsDesktopNumbersInObservationMode() async throws {
        let all = try await run("list-workspaces --all")
        XCTAssertEqual(all.exitCode, 0, all.stderr.joined())
        XCTAssertEqual(all.stdout, ["1", "2"])
        let visible = try await run("list-workspaces --monitor all --visible --format %{workspace}")
        XCTAssertEqual(visible.stdout, ["2"])
    }

    func testWindowsResolveWorkspacesByDesktopNumber() async throws {
        let desktop2 = try XCTUnwrap(runtime.workspaceBackend.native.layouts.retainedByUUID["desktop-b"])
        TestWindow.new(id: 80, parent: desktop2.rootTilingContainer)
        let listed = try await run("list-windows --workspace 2 --format %{window-id}|%{workspace}")
        XCTAssertEqual(listed.exitCode, 0, listed.stderr.joined())
        XCTAssertEqual(listed.stdout, ["80|2"])
        let empty = try await run("list-windows --workspace 1 --count")
        XCTAssertEqual(empty.stdout, ["0"])
    }

    func testSelectingAWindowOnAHiddenDesktopSwitchesThereFirst() throws {
        let layouts = runtime.workspaceBackend.native.layouts
        let hidden = try XCTUnwrap(layouts.retainedByUUID["desktop-a"])
        let shown = try XCTUnwrap(layouts.retainedByUUID["desktop-b"])
        TestWindow.new(id: 81, parent: hidden.rootTilingContainer)
        TestWindow.new(id: 82, parent: shown.rootTilingContainer)
        XCTAssertEqual(nativeFocusWindowCommands(81), ["workspace 1"], "Observation mode only switches")
        XCTAssertEqual(nativeFocusWindowCommands(82), [])
        for text in ["palette", "open-sidebar"] {
            XCTAssertTrue(runtime.workspaceBackend.accepts(try XCTUnwrap(parseCommand(text).cmdOrNil)), text)
        }
    }

    func testQueriesNeverJoinWindowCommandsInOneBinding() throws {
        let tiling = WinMuxRuntime()
        tiling.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        let query = try XCTUnwrap(parseCommand("list-windows --all").cmdOrNil)
        let balance = try XCTUnwrap(parseCommand("balance-sizes").cmdOrNil)
        XCTAssertTrue(tiling.workspaceBackend.accepts([query]))
        XCTAssertFalse(tiling.workspaceBackend.accepts([balance, query]))
    }
}
