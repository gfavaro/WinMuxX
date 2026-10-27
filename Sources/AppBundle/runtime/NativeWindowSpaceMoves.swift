import Common
import NativeSpaces

/// `move-node-to-workspace` with native Spaces. Targets use the same desktop
/// numbering as `workspace`; next/prev step through the window's display's
/// desktops. The move is confirmed from a fresh membership read, then the window's
/// node joins the destination desktop's layout so neither tree waits for a visit.
@MainActor
final class NativeWindowSpaceMoves {
    var snapshot: ([UInt32]) async throws -> NativeSpacesSnapshot
    var move: (UInt32, UInt64) -> Bool = { NativeWindowSpaceMover.move(windowIDs: [$0], toSpaceID: $1) }
    var isAvailable: () -> Bool = { NativeWindowSpaceMover.isAvailable }
    var arrivalTimeout: Duration = .milliseconds(500)
    var pollInterval: Duration = .milliseconds(20)

    init() {
        let reader = NativeSpacesReader()
        snapshot = { try await reader.snapshot(windowIDs: $0) }
    }

    static func supports(_ args: MoveNodeToWorkspaceCmdArgs) -> Bool {
        guard !args.useStdin else { return false }
        switch args.target.val {
            case .relative: return true
            case .direct(let name): return Int(name.raw) != nil
        }
    }

    func run(_ args: MoveNodeToWorkspaceCmdArgs, env: CmdEnv, io: CmdIo) async -> Bool {
        guard let window = args.resolveTargetOrReportError(env, io)?.windowOrNil else { return io.err(noWindowIsFocused) }
        return await move(window, focusFollowsWindow: args.focusFollowsWindow, failIfNoop: args.failIfNoop, io: io) {
            self.resolve(args, from: $0, on: $1, in: $2, io)
        }
    }

    /// `move-node-to-monitor`: the window joins the desktop that display shows.
    func run(_ args: MoveNodeToMonitorCmdArgs, env: CmdEnv, io: CmdIo) async -> Bool {
        guard let window = args.resolveTargetOrReportError(env, io)?.windowOrNil else { return io.err(noWindowIsFocused) }
        guard let current = window.nodeMonitor else { return io.err(windowIsntPartOfTree(window)) }
        let monitor: Monitor
        switch args.target.val.resolve(current, wrapAround: args.wrapAround) {
            case .success(let target): monitor = target
            case .failure(let message): return io.err(message)
        }
        return await move(window, focusFollowsWindow: args.focusFollowsWindow, failIfNoop: args.failIfNoop, io: io) { _, _, displays in
            guard let display = displays.first(where: { nativeDisplay($0, isShownOn: monitor) }),
                  let space = display.spaces.first(where: { $0.id == display.activeSpaceID }), space.isDesktop else {
                _ = io.err("\(monitor.name) shows no desktop a window can join")
                return nil
            }
            return space
        }
    }

    /// `move-workspace-to-monitor`. macOS cannot move a desktop to another display
    /// without SIP changes, so the desktop's windows join the desktop that display
    /// shows, carrying their layout tree: into an empty desktop it arrives whole with
    /// its arrangement, otherwise as one group. The emptied desktop stays in place.
    func run(_ args: MoveWorkspaceToMonitorCmdArgs, env: CmdEnv, io: CmdIo) async -> Bool {
        guard isAvailable() else { return io.err("Moving windows between native Spaces is unavailable on this macOS version") }
        // Any desktop may be the source, including one not showing: windows move by ID and
        // each arrival is confirmed, so the active-desktop fence of tiling commands is not needed.
        guard let source = args.resolveUncheckedTarget(env, io)?.workspace else { return false }
        guard nativeDesktopNumber(of: source) != nil else { return io.err("Only a native desktop can move to another display") }
        let monitor: Monitor
        switch args.target.val.resolve(source.workspaceMonitor, wrapAround: args.wrapAround) {
            case .success(let target): monitor = target
            case .failure(let message): return io.err(message)
        }
        let destination = monitor.activeWorkspace
        guard destination !== source else { return true }
        let windows = source.allLeafWindowsRecursive
        // Windows of a desktop not visited yet are known only by ID; they move too and are
        // adopted on arrival, since the destination desktop is showing.
        let sourceSpace = runtime.workspaceBackend.nativeLayouts.currentBySpaceID.first { $0.value === source }?.key
        let listed = sourceSpace.map { space in (NativeUnvisitedWindows.shared.bySpaceID[space] ?? []).map(\.windowId) } ?? []
        let ids = windows.map(\.windowId) + listed.filter { id in !windows.contains { $0.windowId == id } }
        guard !ids.isEmpty else { return io.err("\(userFacingDesktopName(source)) has no windows to move") }
        let state: NativeSpacesSnapshot
        do { state = try await snapshot(ids) } catch { return io.err("Native Spaces unavailable: \(error)") }
        guard let display = state.displays.first(where: { nativeDisplay($0, isShownOn: monitor) }),
              let target = display.spaces.first(where: { $0.id == display.activeSpaceID }), target.isDesktop,
              let spaceID = UInt64(target.id) else {
            return io.err("\(monitor.name) shows no desktop windows can join")
        }
        let movable = ids.filter { id in
            guard let space = state.windows.first(where: { $0.windowID == id })?.unambiguousSpaceID else { return false }
            return space != target.id
        }
        let failedToStart = movable.filter { !move($0, spaceID) }
        var arrived = Set<UInt32>()
        let deadline = ContinuousClock.now + arrivalTimeout
        while arrived.count < movable.count - failedToStart.count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
            if let read = try? await snapshot(movable) {
                arrived = Set(read.windows.filter { $0.unambiguousSpaceID == target.id }.map(\.windowID))
            }
        }
        guard !arrived.isEmpty else { return io.err("No window of \(userFacingDesktopName(source)) arrived on \(monitor.name)") }
        if !windows.isEmpty, windows.allSatisfy({ arrived.contains($0.windowId) }) {
            transplant(source, into: destination)
        } else {
            for window in windows where arrived.contains(window.windowId) {
                if window.parent is Workspace { window.bindAsFloatingWindow(to: destination) }
                else { window.bind(to: destination.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST) }
            }
        }
        runtime.workspaceBackend.observation?.requestRead(event: "nativeWindowMoved")
        if let focused = windows.first(where: { $0.windowId == focus.windowOrNil?.windowId && arrived.contains($0.windowId) }) ??
            destination.mostRecentWindowRecursive, focused.focusWindow() {
            focused.nativeFocus()
        }
        NativeUnvisitedWindows.shared.refresh()
        let left = movable.count - arrived.count
        return left == 0 || io.err("\(left) of \(movable.count) windows could not move and stay on \(userFacingDesktopName(source))")
    }

    private func transplant(_ source: Workspace, into destination: Workspace) {
        let root = source.rootTilingContainer
        let floating = source.floatingWindows
        if destination.isEffectivelyEmpty {
            destination.rootTilingContainer.unbindFromParent()
            root.unbindFromParent()
            root.bind(to: destination, adaptiveWeight: 1, index: 0)
            destination.arrangement = source.arrangement
            destination.preservesTopLevelGroups = source.preservesTopLevelGroups
            destination.masterRatio = source.masterRatio
            destination.scrollingOffset = 0
        } else {
            root.unbindFromParent()
            root.bind(to: destination.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
        for window in floating { window.bindAsFloatingWindow(to: destination) }
    }

    private func move(_ window: Window, focusFollowsWindow: Bool, failIfNoop: Bool, io: CmdIo,
                      target resolveTarget: (String, NativeSpaceDisplay, [NativeSpaceDisplay]) -> NativeSpace?) async -> Bool {
        guard isAvailable() else { return io.err("Moving windows between native Spaces is unavailable on this macOS version") }
        let id = window.windowId
        let state: NativeSpacesSnapshot
        do { state = try await snapshot([id]) } catch { return io.err("Native Spaces unavailable: \(error)") }
        guard let source = state.windows.first(where: { $0.windowID == id })?.unambiguousSpaceID,
              let display = state.displays.first(where: { $0.spaces.contains { $0.id == source } }) else {
            return io.err("Window \(id) is not on exactly one native Space")
        }
        guard let target = resolveTarget(source, display, state.displays) else { return false }
        if target.id == source {
            if failIfNoop { return false }
            io.err("Window \(id) is already on that desktop. Tip: use --fail-if-noop to exit with non-zero code")
            return true
        }
        guard let spaceID = UInt64(target.id), move(id, spaceID) else {
            return io.err("Moving window \(id) to Space \(target.id) failed")
        }
        let deadline = ContinuousClock.now + arrivalTimeout
        var arrived = false
        while !arrived, ContinuousClock.now < deadline {
            try? await Task.sleep(for: pollInterval)
            arrived = (try? await snapshot([id]))?.windows.first { $0.windowID == id }?.unambiguousSpaceID == target.id
        }
        guard arrived else { return io.err("Window \(id) did not arrive on Space \(target.id)") }
        if let uuid = target.uuid, let destination = runtime.workspaceBackend.nativeLayouts.retainedByUUID[uuid],
           window.nodeWorkspace !== destination {
            if window.parent is Workspace {
                window.bindAsFloatingWindow(to: destination)
            } else {
                window.bind(to: destination.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            }
        }
        runtime.workspaceBackend.observation?.requestRead(event: "nativeWindowMoved")
        guard focusFollowsWindow, let number = NativeSpaceNavigation.desktopNumber(of: target.id, in: state.displays),
              case .cmd(let follow) = parseCommand("workspace \(number)"), let follow = follow as? WorkspaceCommand else { return true }
        guard await runtime.workspaceBackend.nativeNavigation.run(follow.args, io: io) else { return false }
        window.nativeFocus()
        return true
    }

    private func resolve(_ args: MoveNodeToWorkspaceCmdArgs, from source: String, on display: NativeSpaceDisplay,
                         in displays: [NativeSpaceDisplay], _ io: CmdIo) -> NativeSpace? {
        switch args.target.val {
            case .direct(let name):
                guard let number = Int(name.raw),
                      let plan = NativeSpaceNavigation.desktop(number: number, in: displays),
                      let space = displays.first(where: { $0.identifier == plan.displayIdentifier })?
                          .spaces.first(where: { $0.id == plan.targetSpaceID }) else {
                    _ = io.err("Desktop \(name.raw) doesn't exist; add it in Mission Control")
                    return nil
                }
                return space
            case .relative(let direction):
                // Windows only move to desktops; fullscreen Spaces belong to their app.
                let desktops = display.spaces.filter(\.isDesktop)
                guard let from = desktops.firstIndex(where: { $0.id == source }) else {
                    _ = io.err("The window is on a fullscreen Space")
                    return nil
                }
                var to = from + (direction == .next ? 1 : -1)
                if !desktops.indices.contains(to) {
                    guard args.wrapAround else {
                        _ = io.err("No \(direction == .next ? "next" : "previous") desktop on this display")
                        return nil
                    }
                    to = (to + desktops.count) % desktops.count
                }
                return desktops[to]
        }
    }
}
