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
        runtime.workspaceBackend.native.layouts.reconcile(inventory, displays: [monitor])
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
        let ok = await mover.transferWindow(args, env: .defaultEnv.copy(\.windowId, 70), io: io)
        return CmdResult(stdout: io.stdout, stderr: io.stderr, exitCode: ok ? 0 : 1)
    }

    func testConfirmedMoveRehomesTheWindowIntoTheDestinationLayout() async throws {
        let layouts = runtime.workspaceBackend.native.layouts
        let source = try XCTUnwrap(layouts.retainedByUUID["desktop-a"])
        let destination = try XCTUnwrap(layouts.retainedByUUID["desktop-b"])
        let window = TestWindow.new(id: 70, parent: source.rootTilingContainer)
        let result = try await run(mover(arrives: true), "move-node-to-workspace next")
        XCTAssertEqual(result.exitCode, 0, result.stderr.joined())
        XCTAssertEqual(moves.map(\.1), [2], "next skips the fullscreen Space")
        XCTAssertTrue(window.nodeWorkspace === destination)
        XCTAssertTrue(window.parent === destination.rootTilingContainer)
    }

    func testAWindowOnADesktopNotShowingCanBeMovedBack() async throws {
        let layouts = runtime.workspaceBackend.native.layouts
        let hidden = try XCTUnwrap(layouts.retainedByUUID["desktop-b"])
        let showing = try XCTUnwrap(layouts.retainedByUUID["desktop-a"])
        let window = TestWindow.new(id: 70, parent: hidden.rootTilingContainer)
        window.nativeLayoutEligible = false // Never eligible while its desktop is not showing.
        membership = "2"
        let result = try await run(mover(arrives: true), "move-node-to-workspace 1")
        XCTAssertEqual(result.exitCode, 0, result.stderr.joined())
        XCTAssertTrue(window.nodeWorkspace === showing)
    }

    func testAListedWindowMovesByIdToADesktopNumber() async throws {
        membership = "1"
        let io = CmdIo(stdin: .emptyStdin)
        let mover = mover(arrives: true)
        let ok = await mover.moveListed(70, toDesktop: 2, io: io)
        XCTAssertTrue(ok, io.stderr.joined())
        XCTAssertEqual(moves.map(\.1), [2], "Desktop 2 skips the fullscreen Space")
        let bad = await mover.moveListed(70, toDesktop: 9, io: io)
        XCTAssertFalse(bad)
    }

    func testUnconfirmedMoveIsReportedAndLeavesTheTree() async throws {
        let source = try XCTUnwrap(runtime.workspaceBackend.native.layouts.retainedByUUID["desktop-a"])
        let window = TestWindow.new(id: 70, parent: source.rootTilingContainer)
        let result = try await run(mover(arrives: false), "move-node-to-workspace 2")
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.joined().contains("did not arrive"))
        XCTAssertTrue(window.nodeWorkspace === source)
    }

    func testNoopAndMissingDesktopDoNotMove() async throws {
        let source = try XCTUnwrap(runtime.workspaceBackend.native.layouts.retainedByUUID["desktop-a"])
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

@MainActor
final class NativeMonitorCommandsTest: WorkspaceTestCase {
    private var membership = "1"
    private var moves: [UInt64] = []
    private var monitors: [Monitor] = []

    override func setUp() async throws {
        try await super.setUp()
        runtime.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        let left = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let right = Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080)
        monitors = [
            TestMonitor(displayUUID: "display-a", monitorAppKitNsScreenScreensId: 1, name: "left", rect: left, visibleRect: left, isMain: true),
            TestMonitor(displayUUID: "display-b", monitorAppKitNsScreenScreensId: 2, name: "right", rect: right, visibleRect: right, isMain: false),
        ]
        setMonitorsForTests(monitors)
        var inventory = NativeWorkspaceInventory()
        XCTAssertTrue(inventory.publish(snapshot(), for: inventory.invalidate()))
        runtime.workspaceBackend.native.layouts.reconcile(inventory, displays: monitors)
    }

    private var memberships: [UInt32: String] = [:]

    private func snapshot() -> NativeSpacesSnapshot {
        NativeSpacesSnapshot(displays: [
            NativeSpaceDisplay(identifier: "display-a", activeSpaceID: "1", spaces: [
                NativeSpace(id: "1", uuid: "desktop-a", type: 0), NativeSpace(id: "2", uuid: "desktop-b", type: 0)]),
            NativeSpaceDisplay(identifier: "display-b", activeSpaceID: "6", spaces: [NativeSpace(id: "6", uuid: "desktop-c", type: 0)]),
        ], windows: [NativeWindowMembership(windowID: 70, spaceIDs: [membership])] +
            memberships.map { NativeWindowMembership(windowID: $0.key, spaceIDs: [$0.value]) },
        readMilliseconds: 0, capturedAt: .now)
    }

    func testMoveWorkspaceToMonitorCarriesTheLayoutIntoTheOtherDisplaysDesktop() async throws {
        let layouts = runtime.workspaceBackend.native.layouts
        let source = try XCTUnwrap(layouts.retainedByUUID["desktop-a"])
        let destination = try XCTUnwrap(layouts.retainedByUUID["desktop-c"])
        source.rootTilingContainer.layout = .tiles
        let split = TilingContainer(parent: source.rootTilingContainer, adaptiveWeight: 1, .v, .tiles, index: 0)
        let a = TestWindow.new(id: 81, parent: split)
        let b = TestWindow.new(id: 82, parent: split)
        let c = TestWindow.new(id: 83, parent: source.rootTilingContainer)
        let floating = TestWindow.new(id: 84, parent: source)
        source.transitionArrangement(to: .scrolling)
        for id in [81, 82, 83, 84] as [UInt32] { memberships[id] = "1" }
        let mover = NativeWindowSpaceMoves()
        mover.isAvailable = { true }
        mover.arrivalTimeout = .milliseconds(100)
        mover.pollInterval = .milliseconds(5)
        mover.snapshot = { [unowned self] _ in snapshot() }
        mover.move = { [unowned self] id, space in memberships[id] = String(space); return true }
        let args = try XCTUnwrap(parseCommand("move-workspace-to-monitor right").cmdOrDie as? MoveWorkspaceToMonitorCommand).args
        let io = CmdIo(stdin: .emptyStdin)
        let ok = await mover.transferDesktopContents(args, env: .defaultEnv.copy(\.workspaceName, source.name), io: io)
        XCTAssertTrue(ok, io.stderr.joined())
        XCTAssertEqual(Set(memberships.values), ["6"])
        XCTAssertTrue([a, b, c, floating].allSatisfy { $0.nodeWorkspace === destination })
        XCTAssertTrue(a.parent === b.parent && a.parent !== destination.rootTilingContainer, "The split arrives intact")
        XCTAssertTrue(floating.parent === destination, "Floating windows stay floating")
        XCTAssertEqual(destination.arrangement, .scrolling)
        XCTAssertTrue(source.isEffectivelyEmpty, "The macOS desktop stays, emptied")
    }

    func testMoveNodeToMonitorJoinsTheDesktopThatDisplayShows() async throws {
        let layouts = runtime.workspaceBackend.native.layouts
        let source = try XCTUnwrap(layouts.retainedByUUID["desktop-a"])
        let destination = try XCTUnwrap(layouts.retainedByUUID["desktop-c"])
        let window = TestWindow.new(id: 70, parent: source.rootTilingContainer)
        let mover = NativeWindowSpaceMoves()
        mover.isAvailable = { true }
        mover.arrivalTimeout = .milliseconds(100)
        mover.pollInterval = .milliseconds(5)
        mover.snapshot = { [unowned self] _ in snapshot() }
        mover.move = { [unowned self] _, space in moves.append(space); membership = String(space); return true }
        let args = try XCTUnwrap(parseCommand("move-node-to-monitor right").cmdOrDie as? MoveNodeToMonitorCommand).args
        let io = CmdIo(stdin: .emptyStdin)
        let ok = await mover.transferWindow(args, env: .defaultEnv.copy(\.windowId, 70), io: io)
        XCTAssertTrue(ok, io.stderr.joined())
        XCTAssertEqual(moves, [6], "The right display shows desktop 3 (Space 6)")
        XCTAssertTrue(window.nodeWorkspace === destination)
    }

    func testMoveWorkspaceToMonitorAlsoMovesWindowsOnlyListedForAnUnvisitedDesktop() async throws {
        let source = try XCTUnwrap(runtime.workspaceBackend.native.layouts.retainedByUUID["desktop-b"])
        memberships[90] = "2"
        NativeUnvisitedWindows.shared.set([NativeListedWindow(windowId: 90, spaceID: "2", pid: getpid(), title: nil)])
        defer { NativeUnvisitedWindows.shared.set([]) }
        let mover = NativeWindowSpaceMoves()
        mover.isAvailable = { true }
        mover.arrivalTimeout = .milliseconds(100)
        mover.pollInterval = .milliseconds(5)
        mover.snapshot = { [unowned self] _ in snapshot() }
        mover.move = { [unowned self] id, space in memberships[id] = String(space); return true }
        let args = try XCTUnwrap(parseCommand("move-workspace-to-monitor right").cmdOrDie as? MoveWorkspaceToMonitorCommand).args
        let io = CmdIo(stdin: .emptyStdin)
        let ok = await mover.transferDesktopContents(args, env: .defaultEnv.copy(\.workspaceName, source.name), io: io)
        XCTAssertTrue(ok, io.stderr.joined())
        XCTAssertEqual(memberships[90], "6", "Moved by ID; adopted once it arrives on the showing desktop")
    }

    func testBringHereFromASidebarMovesTheDesktopToThatSidebarsDisplay() throws {
        let source = try XCTUnwrap(runtime.workspaceBackend.native.layouts.retainedByUUID["desktop-c"])
        let left = workspaceSidebarMonitorScopeId(for: monitors[0])
        let (args, env) = try XCTUnwrap(nativeBringHere(source.name, targetMonitorScopeId: left))
        XCTAssertEqual(args.resolveTargetOrReportError(env, CmdIo(stdin: .emptyStdin))?.workspace, source)
        guard case .success(let monitor) = args.target.val.resolve(monitors[1], wrapAround: false) else { return XCTFail() }
        XCTAssertEqual(monitor.name, "left", "The sidebar's own display")
        XCTAssertNil(nativeBringHere(source.name, targetMonitorScopeId: workspaceSidebarMonitorScopeId(for: monitors[1])),
            "A desktop already on that display stays")
    }

    func testDirectionalFocusAndMoveCrossToTheNextDisplay() async throws {
        let layouts = runtime.workspaceBackend.native.layouts
        let left = try XCTUnwrap(layouts.retainedByUUID["desktop-a"])
        let right = try XCTUnwrap(layouts.retainedByUUID["desktop-c"])
        let here = TestWindow.new(id: 71, parent: left.rootTilingContainer)
        let there = TestWindow.new(id: 72, parent: right.rootTilingContainer)
        _ = here.focusWindow()
        let focusRight = try XCTUnwrap(parseCommand("focus --boundaries all-monitors-outer-frame right").cmdOrDie as? FocusCommand)
        let io = CmdIo(stdin: .emptyStdin)
        let focused = try await focusRight.run(.defaultEnv, io)
        XCTAssertTrue(focused, io.stderr.joined())
        XCTAssertEqual(focus.windowOrNil?.windowId, there.windowId)

        _ = here.focusWindow()
        let moveRight = try XCTUnwrap(parseCommand("move --boundaries all-monitors-outer-frame right").cmdOrDie as? MoveCommand)
        let sink = NativeTilingCommandScope.MonitorMoveSink()
        let moved = NativeTilingCommandScope.$monitorMoveSink.withValue(sink) { moveRight.run(.defaultEnv, io) }
        XCTAssertTrue(moved, io.stderr.joined())
        let pending = try XCTUnwrap(sink.pending, "Deferred until the fenced command ends")
        XCTAssertEqual(pending.windowId, here.windowId)
        XCTAssertTrue(here.nodeWorkspace === left, "The tree waits for the confirmed native move")
    }

    func testFocusingAWindowOnAHiddenDesktopRunsAsNavigation() throws {
        let layouts = runtime.workspaceBackend.native.layouts
        let hidden = try XCTUnwrap(layouts.retainedByUUID["desktop-b"])
        let shown = try XCTUnwrap(layouts.retainedByUUID["desktop-a"])
        _ = TestWindow.new(id: 75, parent: hidden.rootTilingContainer)
        _ = TestWindow.new(id: 76, parent: shown.rootTilingContainer)
        let away = try XCTUnwrap(parseCommand("focus --window-id 75").cmdOrDie as? FocusCommand)
        let here = try XCTUnwrap(parseCommand("focus --window-id 76").cmdOrDie as? FocusCommand)
        XCTAssertTrue(NativeCommandPolicy.isNativeNavigation(away), "Switches to its desktop first, outside the fence")
        XCTAssertFalse(NativeCommandPolicy.isNativeNavigation(here), "A showing desktop's window stays a fenced tiling command")
    }

    func testWorkspaceNShowingOnTheOtherDisplayFocusesItThere() async throws {
        let layouts = runtime.workspaceBackend.native.layouts
        let here = TestWindow.new(id: 77, parent: try XCTUnwrap(layouts.retainedByUUID["desktop-a"]).rootTilingContainer)
        let there = TestWindow.new(id: 78, parent: try XCTUnwrap(layouts.retainedByUUID["desktop-c"]).rootTilingContainer)
        _ = here.focusWindow()
        let navigator = NativeSpaceNavigator()
        navigator.isSupported = { true }
        navigator.canPostEvents = { true }
        navigator.topology = { [unowned self] in snapshot().displays }
        var posted = 0
        navigator.post = { _ in posted += 1; return true }
        let args = try XCTUnwrap(parseCommand("workspace --auto-back-and-forth 3").cmdOrDie as? WorkspaceCommand).args
        let io = CmdIo(stdin: .emptyStdin)
        let ok = await navigator.selectDesktop(args, io: io)
        XCTAssertTrue(ok, io.stderr.joined())
        XCTAssertEqual(posted, 0, "Nothing switches: desktop 3 is already showing")
        XCTAssertEqual(focus.windowOrNil?.windowId, there.windowId, "Focus moves to it on the other display")
    }

    func testTheTilingFenceAcceptsADesktopNumber() throws {
        let layouts = runtime.workspaceBackend.native.layouts
        _ = Workspace.get(byName: "1") // A leftover virtual workspace named like desktop 1 must not shadow it.
        let command = try XCTUnwrap(parseCommand("balance-sizes --workspace 1").unwrap().0)
        XCTAssertNotNil(NativeCommandTargetFence([command], env: .defaultEnv, defaultFocus: nil, layouts: layouts))
        let env = CmdEnv.defaultEnv.copy(\.workspaceName, "3")
        let balance = try XCTUnwrap(parseCommand("balance-sizes").unwrap().0)
        XCTAssertNotNil(NativeCommandTargetFence([balance], env: env, defaultFocus: nil, layouts: layouts), "Desktop 3 on the other display")
    }

    func testFocusMonitorFocusesTheOtherDisplaysRecentWindow() throws {
        let layouts = runtime.workspaceBackend.native.layouts
        let left = try XCTUnwrap(layouts.retainedByUUID["desktop-a"])
        let right = try XCTUnwrap(layouts.retainedByUUID["desktop-c"])
        let here = TestWindow.new(id: 71, parent: left.rootTilingContainer)
        let there = TestWindow.new(id: 72, parent: right.rootTilingContainer)
        _ = here.focusWindow()
        let args = try XCTUnwrap(parseCommand("focus-monitor right").cmdOrDie as? FocusMonitorCommand).args
        let io = CmdIo(stdin: .emptyStdin)
        XCTAssertTrue(nativeFocusMonitor(args, env: .defaultEnv, io: io), io.stderr.joined())
        XCTAssertEqual(focus.windowOrNil?.windowId, there.windowId)
        XCTAssertTrue(runtime.workspaceBackend.accepts(try XCTUnwrap(parseCommand("list-monitors").unwrap().0)))
    }
}
