import AppKit
import Common
import NativeSpaces

/// Which workspaces a listing covers.
enum WorkspaceListScope {
    /// `list-workspaces` and menus: user-facing, in presentation order.
    case presentation
    /// `list-windows`: user-facing, in tree order.
    case userFacing
    /// The palette: every workspace that can hold a window.
    case all
}

/// What differs between virtual workspaces and native Spaces. Shared code asks the
/// current backend instead of checking which one runs.
@MainActor
protocol WorkspaceBackend: AnyObject {
    /// The backend's own implementation of a command, or nil to run the shared one.
    func run(_ command: any Command, env: CmdEnv, io: CmdIo) async throws -> Bool?

    func listedWorkspaces(_ scope: WorkspaceListScope) -> [Workspace]
    /// Workspaces menus offer, each with the `workspace` argument that reaches it.
    func commandTargets() -> [(workspace: Workspace, target: String)]
    /// The name scripts and queries see.
    func scriptName(of workspace: Workspace) -> String
    /// Resolves a name a user typed.
    func workspace(named name: String) -> Workspace?
    /// The title menus and the palette show.
    func title(ofWorkspaceNamed name: String) -> String
    /// Whether projects group this backend's workspaces.
    var hasProjects: Bool { get }
    /// A workspace user-facing regardless of its windows (a native desktop).
    func isAlwaysUserFacing(_ workspace: Workspace) -> Bool

    func sidebarWorkspaces(currentFocus: LiveFocus, labels: [String: String],
                           monitors: [Monitor]) async -> [WorkspaceSidebarWorkspaceViewModel]
    /// Handles a sidebar action itself; false leaves it to the shared handler.
    func handleSidebarAction(_ action: WorkspaceSidebarAction, viewModel: TrayMenuModel, targetMonitorScopeId: String?) -> Bool

    /// Brings a window forward from the palette or minimap; returns an error to show.
    func bringForward(_ windowId: UInt32) async throws -> String?
    /// Palette entries beyond the workspace trees.
    func extraPaletteItems() -> [SwitcherPaletteItem]
    /// The workspace a display shows; native desktops never fall back to virtual rearrangement.
    func shownWorkspace(on monitor: Monitor) -> Workspace?
    /// After a command outside native tiling's fence moved focus.
    func focusDidMove(to window: Window?)

    /// The `doctor` report, or nil for the shared one.
    func diagnosticsReport() async -> String?
    /// Fills the tray's workspace indicator; false leaves it to the shared code.
    func updateTray() -> Bool
    /// A window's geometry changed (a move when `moved`); false leaves it to the shared mouse handling.
    func windowGeometryChanged(_ windowId: UInt32?, moved: Bool) -> Bool
}

@MainActor
final class VirtualWorkspaceBackend: WorkspaceBackend {
    func run(_ command: any Command, env: CmdEnv, io: CmdIo) async throws -> Bool? { nil }

    func listedWorkspaces(_ scope: WorkspaceListScope) -> [Workspace] {
        switch scope {
            case .presentation: userFacingWorkspaces(orderedWorkspacesForPresentation(), focusedWorkspace: focus.workspace)
            case .userFacing: userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace)
            case .all: Workspace.all
        }
    }

    func commandTargets() -> [(workspace: Workspace, target: String)] {
        listedWorkspaces(.presentation)
            .filter { $0.projectId == focus.workspace.projectId }
            .map { workspace in
                let target = workspace.usesAutomaticDisplayName
                    ? automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: focus.workspace).map(String.init) ?? workspace.name
                    : workspace.name
                return (workspace, target)
            }
    }

    func scriptName(of workspace: Workspace) -> String { workspace.name }
    func workspace(named name: String) -> Workspace? { Workspace.existing(byName: name) }
    func title(ofWorkspaceNamed name: String) -> String { workspaceDisplayName(name) }
    var hasProjects: Bool { true }
    func isAlwaysUserFacing(_ workspace: Workspace) -> Bool { false }

    func sidebarWorkspaces(currentFocus: LiveFocus, labels: [String: String],
                           monitors: [Monitor]) async -> [WorkspaceSidebarWorkspaceViewModel] {
        await buildWorkspaceSidebarWorkspaceViewModels(currentFocus: currentFocus, workspaceLabels: labels, availableMonitors: monitors)
    }

    func handleSidebarAction(_ action: WorkspaceSidebarAction, viewModel: TrayMenuModel, targetMonitorScopeId: String?) -> Bool { false }

    func bringForward(_ windowId: UInt32) async throws -> String? {
        guard let window = Window.get(byId: windowId), let liveFocus = window.toLiveFocusOrNil() else { return nil }
        window.markAsMostRecentChild()
        _ = setFocus(to: liveFocus)
        window.nativeFocus()
        return nil
    }

    func extraPaletteItems() -> [SwitcherPaletteItem] { [] }
    func shownWorkspace(on monitor: Monitor) -> Workspace? { monitor.activeWorkspace }
    func focusDidMove(to window: Window?) {}
    func diagnosticsReport() async -> String? { nil }
    func updateTray() -> Bool { false }
    func windowGeometryChanged(_ windowId: UInt32?, moved: Bool) -> Bool { false }
}

/// Native Spaces: macOS owns desktops, so they are numbered in Control-N order, and
/// navigation and cross-Space moves run outside native tiling's command fence.
@MainActor
final class NativeWorkspaceBackend: WorkspaceBackend {
    private unowned let state: WorkspaceBackendState
    init(_ state: WorkspaceBackendState) { self.state = state }

    func run(_ command: any Command, env: CmdEnv, io: CmdIo) async throws -> Bool? {
        switch command {
            case let command as WorkspaceCommand: await state.nativeNavigation.run(command.args, io: io)
            case is WorkspaceBackAndForthCommand: await state.nativeNavigation.runBackAndForth(io: io)
            case let command as MoveNodeToWorkspaceCommand: await state.nativeWindowMoves.run(command.args, env: env, io: io)
            case let command as MoveNodeToMonitorCommand: await state.nativeWindowMoves.run(command.args, env: env, io: io)
            case let command as MoveWorkspaceToMonitorCommand: await state.nativeWindowMoves.run(command.args, env: env, io: io)
            case let command as FocusMonitorCommand: nativeFocusMonitor(command.args, env: env, io: io)
            case is FocusBackAndForthCommand: try await focusPreviousWindow(io)
            // Classified as navigation before waiting for the read in flight, which can show the
            // desktop meanwhile; re-checking here would fall through to an unfenced plain focus.
            case let command as FocusCommand where command.args.windowId != nil && state.nativeTilingEnabled &&
                !NativeTilingCommandScope.active:
                try await focusWindowOnHiddenDesktop(command.args.windowId, io)
            case let command as EnableCommand: try await setEnabled(command.args, io)
            default: nil
        }
    }

    func listedWorkspaces(_ scope: WorkspaceListScope) -> [Workspace] { nativeDesktopWorkspaces().map(\.workspace) }
    func commandTargets() -> [(workspace: Workspace, target: String)] {
        nativeDesktopWorkspaces().map { ($0.workspace, String($0.number)) }
    }
    func scriptName(of workspace: Workspace) -> String { nativeDesktopNumber(of: workspace).map(String.init) ?? workspace.name }
    func workspace(named name: String) -> Workspace? {
        Int(name).flatMap { number in nativeDesktopWorkspaces().first { $0.number == number }?.workspace }
    }
    func title(ofWorkspaceNamed name: String) -> String {
        nativeDesktopNumber(forSidebarWorkspace: name).map { nativeDesktopDisplayName($0) } ?? workspaceDisplayName(name)
    }
    var hasProjects: Bool { false }
    func isAlwaysUserFacing(_ workspace: Workspace) -> Bool { nativeDesktopNumber(of: workspace) != nil }

    func sidebarWorkspaces(currentFocus: LiveFocus, labels: [String: String],
                           monitors: [Monitor]) async -> [WorkspaceSidebarWorkspaceViewModel] {
        await buildNativeWorkspaceSidebarWorkspaceViewModels(currentFocus: currentFocus, workspaceLabels: labels, availableMonitors: monitors)
    }

    func handleSidebarAction(_ action: WorkspaceSidebarAction, viewModel: TrayMenuModel, targetMonitorScopeId: String?) -> Bool {
        handleNativeWorkspaceSidebarAction(action, viewModel: viewModel, targetMonitorScopeId: targetMonitorScopeId)
        return true
    }

    func bringForward(_ windowId: UInt32) async throws -> String? { try await focusNativeWindow(windowId) }
    func extraPaletteItems() -> [SwitcherPaletteItem] { nativeListedPaletteItems() }
    func shownWorkspace(on monitor: Monitor) -> Workspace? { nativeActiveDesktop(on: monitor) }

    func focusDidMove(to window: Window?) {
        // Inside the fence the coordinator brings the result forward itself.
        guard !NativeTilingCommandScope.active else { return }
        window?.nativeFocus()
    }

    /// Switches to the window's desktop unless it already shows, waits for it to show and for
    /// tiling to be ready, then focuses the window directly. Never re-dispatches `focus`.
    private func focusWindowOnHiddenDesktop(_ id: UInt32?, _ io: CmdIo) async throws -> Bool {
        guard let id, let window = Window.get(byId: id), let desktop = window.nodeWorkspace,
              let number = nativeDesktopNumber(of: desktop) else { return io.err("Window \(id ?? 0) is not on a native desktop") }
        if !desktop.isVisible {
            guard case .cmd(let command) = parseCommand("workspace \(number)"), let switchTo = command as? WorkspaceCommand,
                  await state.nativeNavigation.run(switchTo.args, io: io) else { return false }
        }
        _ = await state.nativeStateChanges.wait(timeout: .seconds(2)) { desktop.isVisible && state.nativeTiling.ready }
        try Task.checkCancellation()
        guard desktop.isVisible, window.focusWindow() else { return io.err("Desktop \(number) did not show in time; try again") }
        window.nativeFocus()
        return true
    }

    /// Brings back the window focused before, switching to its desktop first when needed.
    private func focusPreviousWindow(_ io: CmdIo) async throws -> Bool {
        guard let id = state.nativeActivity.previousFocusedWindow, Window.get(byId: id) != nil else {
            return io.err("Prev window has been closed")
        }
        if let error = try await focusNativeWindow(id) { return io.err(error) }
        return true
    }

    /// `enable`: native windows were never parked, so disabling only stops tiling and
    /// shortcuts, and enabling resumes them with a fresh observation.
    private func setEnabled(_ args: EnableCmdArgs, _ io: CmdIo) async throws -> Bool {
        let model = TrayMenuModel.shared
        let newState: Bool = switch args.targetState.val {
            case .on: true
            case .off: false
            case .toggle: !model.isEnabled
        }
        if newState == model.isEnabled {
            if !args.failIfNoop {
                io.out((newState ? "Already enabled" : "Already disabled") + "Tip: use --fail-if-noop to exit with non-zero code")
            }
            return !args.failIfNoop
        }
        // Turning off keeps tiling's grants until the restore has taken its leases.
        if newState { model.isEnabled = true }
        WindowBorderController.shared.setEnabled(newState)
        if newState {
            try await activateMode(mainModeId)
            state.observation?.requestRead(event: "enabled")
        } else {
            MacApp.cancelPendingFocus()
            clearPendingWindowDragIntent()
            cancelManipulatedWithMouseState()
            model.isWorkspaceSidebarExpanded = false
            await stopNativeTilingAndRestoreFrames()
            try await activateMode(nil)
        }
        WorkspaceSidebarPanel.refreshAll()
        WindowTabStripPanelController.shared.refresh()
        updateTrayText()
        return true
    }

    func diagnosticsReport() async -> String? { nativeSpacesDiagnosticReport() }
    func updateTray() -> Bool { updateNativeTrayText(); return true }

    /// Native mode has no live drag driver: geometry is re-read on demand, a moving tiled
    /// window shows the drop overlays, and one its app moved by itself is put back.
    func windowGeometryChanged(_ windowId: UInt32?, moved: Bool) -> Bool {
        guard let windowId, let window = Window.get(byId: windowId) else { return true }
        window.invalidateLastKnownNativeState()
        if moved { updateNativeDragOverlay(window) }
        if NSEvent.pressedMouseButtons == 0 { NativeFrameRecovery.shared.windowChanged(window) }
        return true
    }
}

/// Stops tiling before the writes, so no layout moves a window back while it is being restored.
@MainActor
func stopNativeTilingAndRestoreFrames() async {
    await NativeOriginalFrames.shared.restore {
        TrayMenuModel.shared.isEnabled = false
        runtime.workspaceBackend.nativeTiling.invalidate("disabled")
    }
}
