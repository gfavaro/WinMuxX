import Common
import NativeSpaces

// Native desktops as users and scripts see them: numbered in macOS Control-N order,
// never by the internal `__native_space_<uuid>` workspace names.

/// The last observation stays listed during a read, so lists don't flicker away.
@MainActor
func nativeObservedDisplays() -> [NativeSpaceDisplay]? {
    let backend = runtime.workspaceBackend
    return (backend.observation?.inventory.lastSnapshot ?? backend.nativeLayouts.snapshot)?.displays
}

/// Desktops in Control-N order with the workspace holding each one's layout.
@MainActor
func nativeDesktopWorkspaces() -> [(number: Int, workspace: Workspace)] {
    let layouts = runtime.workspaceBackend.nativeLayouts
    var result: [(number: Int, workspace: Workspace)] = []
    var number = 0
    for display in nativeObservedDisplays() ?? [] {
        for space in display.spaces where space.isDesktop {
            number += 1
            if let uuid = space.uuid, let workspace = layouts.retainedByUUID[uuid] { result.append((number, workspace)) }
        }
    }
    return result
}

@MainActor
func nativeDesktopNumber(of workspace: Workspace) -> Int? {
    nativeDesktopWorkspaces().first { $0.workspace === workspace }?.number
}

/// The Control-N number of the desktop a native sidebar row stands for.
@MainActor
func nativeDesktopNumber(forSidebarWorkspace name: String) -> Int? {
    nativeDesktopWorkspaces().first { $0.workspace.name == name }?.number
}

/// The name scripts and queries see: the desktop number in native mode.
@MainActor
func userFacingWorkspaceName(_ workspace: Workspace) -> String {
    guard runtime.workspaceBackend.kind == .native else { return workspace.name }
    return nativeDesktopNumber(of: workspace).map(String.init) ?? workspace.name
}

/// Resolves a workspace name typed by a user; native mode accepts desktop numbers.
@MainActor
func userWorkspace(named name: String) -> Workspace? {
    guard runtime.workspaceBackend.kind == .native else { return Workspace.existing(byName: name) }
    return Int(name).flatMap { number in nativeDesktopWorkspaces().first { $0.number == number }?.workspace }
}

/// Native snapshots name the main display "Main" when it has no UUID of its own.
@MainActor
func nativeDisplay(_ display: NativeSpaceDisplay, isShownOn monitor: Monitor) -> Bool {
    display.identifier == "Main" ? monitor.rect.topLeftCorner == mainMonitor.rect.topLeftCorner : display.identifier == monitor.displayUUID
}

/// `focus-monitor`: focuses the most recent window of the desktop that display shows.
@MainActor
func nativeFocusMonitor(_ args: FocusMonitorCmdArgs, env: CmdEnv, io: CmdIo) -> Bool {
    guard let target = args.resolveTargetOrReportError(env, io) else { return false }
    switch args.target.val.resolve(target.workspace.workspaceMonitor, wrapAround: args.wrapAround) {
        case .success(let monitor):
            let desktop = monitor.activeWorkspace
            guard let window = desktop.mostRecentWindowRecursive else {
                return io.err("\(nativeDesktopNumber(of: desktop).map { nativeDesktopDisplayName($0) } ?? "The desktop") on \(monitor.name) has no window to focus")
            }
            guard window.focusWindow() else { return io.err("Window \(window.windowId) could not take focus") }
            window.nativeFocus()
            return true
        case .failure(let message):
            return io.err(message)
    }
}

/// A `workspace-labels` entry keyed by desktop number names that desktop.
func nativeDesktopLabel(_ number: Int, labels: [String: String]) -> String {
    labels[String(number)]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

@MainActor
func nativeDesktopDisplayName(_ number: Int, labels: [String: String]? = nil) -> String {
    let label = nativeDesktopLabel(number, labels: labels ?? config.workspaceSidebar.workspaceLabels)
    return label.isEmpty ? "Desktop \(number)" : label
}

/// Commands that bring a window forward: switch to its desktop when that desktop
/// isn't showing, then focus it when native tiling can.
@MainActor
func nativeFocusWindowCommands(_ windowId: UInt32) -> [String] {
    var commands: [String] = []
    if let workspace = Window.get(byId: windowId)?.nodeWorkspace, !workspace.isVisible,
       let number = nativeDesktopNumber(of: workspace) {
        commands.append("workspace \(number)")
    }
    if runtime.workspaceBackend.nativeTilingEnabled { commands.append("focus --window-id \(windowId)") }
    return commands
}

/// Runs commands in order, stopping at the first failure; a Space switch must land
/// before focusing. Returns the failure's message.
@MainActor
func runNativeCommands(_ commands: [String]) async throws -> String? {
    for text in commands {
        guard case .cmd(let command) = parseCommand(text) else { continue }
        let io = CmdIo(stdin: .emptyStdin)
        guard try await [command].runCmdSeq(.defaultEnv, io) else { return io.stderr.last ?? "\(text) failed" }
    }
    return nil
}
