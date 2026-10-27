import AppKit
import Common
import XCTest
@testable import AppBundle
@testable import NativeSpaces

@MainActor
final class NativeWindowSpaceMovesTest: WorkspaceTestCase {
    private var membership = "1"
    private var moves: [(UInt32, UInt64)] = []
    private let spaces = [
        NativeSpace(id: "1", uuid: "desktop-a", type: 0), NativeSpace(id: "9", uuid: "full", type: 4),
        NativeSpace(id: "2", uuid: "desktop-b", type: 0),
    ]

    override func setUp() async throws {
        try await super.setUp()
        runtime.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let monitor = TestMonitor(displayUUID: "display-a", monitorAppKitNsScreenScreensId: 1,
            name: "display-a", rect: rect, visibleRect: rect, isMain: true)
        setMonitorsForTests([monitor])
        var inventory = NativeWorkspaceInventory()
        XCTAssertTrue(inventory.publish(snapshot(), for: inventory.invalidate()))
        runtime.workspaceBackend.nativeLayouts.reconcile(inventory, displays: [monitor])
    }

    private func snapshot() -> NativeSpacesSnapshot {
        NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "display-a", activeSpaceID: "1", spaces: spaces)],
            windows: [NativeWindowMembership(windowID: 70, spaceIDs: [membership])], readMilliseconds: 0, capturedAt: .now)
    }

    private func mover(arrives: Bool) -> NativeWindowSpaceMoves {
        let mover = NativeWindowSpaceMoves()
        mover.isAvailable = { true }
        mover.arrivalTimeout = .milliseconds(100)
        mover.pollInterval = .milliseconds(5)
        mover.snapshot = { [unowned self] _ in snapshot() }
        mover.move = { [unowned self] id, space in
            moves.append((id, space))
            if arrives { membership = String(space) }
            return true
        }
        return mover
    }

    private func run(_ mover: NativeWindowSpaceMoves, _ command: String) async throws -> CmdResult {
        let args = try XCTUnwrap(parseCommand(command).cmdOrDie as? MoveNodeToWorkspaceCommand).args
        let io = CmdIo(stdin: .emptyStdin)
        let ok = await mover.run(args, env: .defaultEnv.copy(\.windowId, 70), io: io)
        return CmdResult(stdout: io.stdout, stderr: io.stderr, exitCode: ok ? 0 : 1)
    }

    func testConfirmedMoveRehomesTheWindowIntoTheDestinationLayout() async throws {
        let layouts = runtime.workspaceBackend.nativeLayouts
        let source = try XCTUnwrap(layouts.retainedByUUID["desktop-a"])
        let destination = try XCTUnwrap(layouts.retainedByUUID["desktop-b"])
        let window = TestWindow.new(id: 70, parent: source.rootTilingContainer)
        let result = try await run(mover(arrives: true), "move-node-to-workspace next")
        XCTAssertEqual(result.exitCode, 0, result.stderr.joined())
        XCTAssertEqual(moves.map(\.1), [2], "next skips the fullscreen Space")
        XCTAssertTrue(window.nodeWorkspace === destination)
        XCTAssertTrue(window.parent === destination.rootTilingContainer)
    }

    func testUnconfirmedMoveIsReportedAndLeavesTheTree() async throws {
        let source = try XCTUnwrap(runtime.workspaceBackend.nativeLayouts.retainedByUUID["desktop-a"])
        let window = TestWindow.new(id: 70, parent: source.rootTilingContainer)
        let result = try await run(mover(arrives: false), "move-node-to-workspace 2")
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.joined().contains("did not arrive"))
        XCTAssertTrue(window.nodeWorkspace === source)
    }

    func testNoopAndMissingDesktopDoNotMove() async throws {
        let source = try XCTUnwrap(runtime.workspaceBackend.nativeLayouts.retainedByUUID["desktop-a"])
        _ = TestWindow.new(id: 70, parent: source.rootTilingContainer)
        let mover = mover(arrives: true)
        var codes: [Int32] = []
        for command in ["move-node-to-workspace 1", "move-node-to-workspace --fail-if-noop 1", "move-node-to-workspace 5"] {
            codes.append(try await run(mover, command).exitCode)
        }
        XCTAssertEqual(codes, [0, 1, 1])
        XCTAssertTrue(moves.isEmpty)
    }

    func testObservationOnlyModeNeverAcceptsMoves() throws {
        let readOnly = WinMuxRuntime()
        readOnly.workspaceBackend.selectForStartup(.native)
        let move = try XCTUnwrap(parseCommand("move-node-to-workspace 2").cmdOrNil)
        let navigate = try XCTUnwrap(parseCommand("workspace 2").cmdOrNil)
        XCTAssertFalse(readOnly.workspaceBackend.accepts(move))
        XCTAssertTrue(readOnly.workspaceBackend.accepts(navigate))
        XCTAssertTrue(runtime.workspaceBackend.accepts(move))
    }
}
