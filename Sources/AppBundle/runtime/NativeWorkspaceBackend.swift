import AppKit
import Common

/// Native Spaces: macOS owns desktops, so they are numbered in Control-N order, and
/// navigation and cross-Space moves run outside native tiling's command fence.
@MainActor
final class NativeWorkspaceBackend: WorkspaceBackend {
    private unowned let state: NativeWorkspaceLifecycle
    init(_ state: NativeWorkspaceLifecycle) { self.state = state }

    func run(_ command: any Command, env: CmdEnv, io: CmdIo) async throws -> Bool? {
        switch command {
            case let command as WorkspaceCommand:
                if let id = command.nativeSpaceUUID { await state.navigation.selectDesktop(spaceUUID: id, io: io) }
                else { await state.navigation.selectDesktop(command.args, io: io) }
            case is WorkspaceBackAndForthCommand: await state.navigation.selectPreviousDesktop(io: io)
            case let command as MoveNodeToWorkspaceCommand: await state.windowMoves.transferWindow(command.args, env: env, io: io)
            case let command as MoveNodeToMonitorCommand: await state.windowMoves.transferWindow(command.args, env: env, io: io)
            case let command as MoveWorkspaceToMonitorCommand: await state.windowMoves.transferDesktopContents(command.args, env: env, io: io)
            case let command as FocusMonitorCommand: nativeFocusMonitor(command.args, env: env, io: io)
            case is FocusBackAndForthCommand: try await focusPreviousWindow(io)
            // Classified as navigation before waiting for the read in flight, which can show the
            // desktop meanwhile; re-checking here would fall through to an unfenced plain focus.
            case let command as FocusCommand where command.args.windowId != nil && state.tilingEnabled &&
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
    func isAlwaysUserFacing(_ workspace: Workspace) -> Bool { nativeDesktopNumber(of: workspace) != nil }

    func bringForward(_ windowId: UInt32) async throws -> String? { try await focusNativeWindow(windowId) }
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
                  await state.navigation.selectDesktop(switchTo.args, io: io) else { return false }
        }
        _ = await state.stateChanges.wait(timeout: .seconds(2)) { desktop.isVisible && state.tiling.ready }
        try Task.checkCancellation()
        guard desktop.isVisible, window.focusWindow() else { return io.err("Desktop \(number) did not show in time; try again") }
        window.nativeFocus()
        return true
    }

    /// Brings back the window focused before, switching to its desktop first when needed.
    private func focusPreviousWindow(_ io: CmdIo) async throws -> Bool {
        guard let id = state.activity.previousFocusedWindow, Window.get(byId: id) != nil else {
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
        if newState { model.isEnabled = true; state.setTopUpEnabled(true) }
        WindowBorderController.shared.setEnabled(newState)
        if newState {
            try await activateMode(mainModeId)
            state.observation?.requestRead(event: "enabled")
        } else {
            state.setTopUpEnabled(false)
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
        runtime.workspaceBackend.native.tiling.invalidate("disabled")
    }
}
