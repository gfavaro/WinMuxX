import Common
import NativeSpaces

/// `move-node-to-workspace` with native Spaces. Targets use the same desktop
/// numbering as `workspace`; next/prev step through the window's display's
/// desktops. The move is confirmed from a fresh membership read, then the window's
/// node joins the destination desktop's layout so neither tree waits for a visit.
@MainActor
final class NativeWindowSpaceMoves {
    var snapshot: (UInt32) async throws -> NativeSpacesSnapshot
    var move: (UInt32, UInt64) -> Bool = { NativeWindowSpaceMover.move(windowIDs: [$0], toSpaceID: $1) }
    var isAvailable: () -> Bool = { NativeWindowSpaceMover.isAvailable }
    var arrivalTimeout: Duration = .milliseconds(500)
    var pollInterval: Duration = .milliseconds(20)

    init() {
        let reader = NativeSpacesReader()
        snapshot = { try await reader.snapshot(windowIDs: [$0]) }
    }

    static func supports(_ args: MoveNodeToWorkspaceCmdArgs) -> Bool {
        guard !args.useStdin else { return false }
        switch args.target.val {
            case .relative: return true
            case .direct(let name): return Int(name.raw) != nil
        }
    }

    func run(_ args: MoveNodeToWorkspaceCmdArgs, env: CmdEnv, io: CmdIo) async -> Bool {
        guard isAvailable() else { return io.err("Moving windows between native Spaces is unavailable on this macOS version") }
        guard let window = args.resolveTargetOrReportError(env, io)?.windowOrNil else { return io.err(noWindowIsFocused) }
        let id = window.windowId
        let state: NativeSpacesSnapshot
        do { state = try await snapshot(id) } catch { return io.err("Native Spaces unavailable: \(error)") }
        guard let source = state.windows.first(where: { $0.windowID == id })?.unambiguousSpaceID,
              let display = state.displays.first(where: { $0.spaces.contains { $0.id == source } }) else {
            return io.err("Window \(id) is not on exactly one native Space")
        }
        guard let target = resolve(args, from: source, on: display, in: state.displays, io) else { return false }
        if target.id == source {
            if args.failIfNoop { return false }
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
            arrived = (try? await snapshot(id))?.windows.first { $0.windowID == id }?.unambiguousSpaceID == target.id
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
        guard args.focusFollowsWindow, let number = NativeSpaceNavigation.desktopNumber(of: target.id, in: state.displays),
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
