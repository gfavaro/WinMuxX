import AppKit
import Common

struct EnableCommand: Command {
    let args: EnableCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let prevState = TrayMenuModel.shared.isEnabled
        let newState: Bool = switch args.targetState.val {
            case .on: true
            case .off: false
            case .toggle: !TrayMenuModel.shared.isEnabled
        }
        if newState && WindowRecoveryController.shared.isRecovering {
            return io.err("Window recovery is running. Wait for it to finish before enabling tiling.")
        }
        if newState == prevState {
            if !newState { await restoreWindowsReportingFailures(io) }
            if !args.failIfNoop {
                io.out((newState ? "Already enabled" : "Already disabled") +
                    "Tip: use --fail-if-noop to exit with non-zero code")
            }
            return !args.failIfNoop
        }
        if !newState { await WorkspacePresentationController.shared.end(reason: .invalidated) }
        if !newState { persistFrozenWorldForRestartIfPossible() }
        TrayMenuModel.shared.isEnabled = newState
        WindowBorderController.shared.setEnabled(newState)
        if newState { WindowRecoveryController.shared.resumeTiling() }
        if !newState {
            MacApp.cancelPendingFocus()
            runtime.displays.displayChangeTask?.cancel()
            WindowMotion.shared.cancelAll()
            DoubleSidedWindowController.shared.cancelPreparation()
            MacApp.registrationRetries.cancelAll()
            WindowDetectionOperations.shared.cancelAll()
            WorkspaceGestureCoordinator.shared.reset()
            GlobalObserver.cancelFocusFollowsMouse()
            TrayMenuModel.shared.isWorkspaceSidebarExpanded = false
            clearPendingWindowDragIntent()
            cancelManipulatedWithMouseState()
        }
        WorkspaceSidebarPanel.refreshAll()
        WindowTabStripPanelController.shared.refresh()
        if newState {
            for workspace in Workspace.all {
                for window in workspace.allLeafWindowsRecursive where window.isFloating {
                    window.lastFloatingSize = try await window.getAxSize() ?? window.lastFloatingSize
                }
            }
            try await activateMode(mainModeId)
            WorkspaceGestureCoordinator.shared.syncConfiguration()
        } else {
            try await activateMode(nil)
            await restoreWindowsReportingFailures(io)
        }
        return true
    }
}

@MainActor
private func restoreWindowsReportingFailures(_ io: CmdIo) async {
    let failed = await WindowRecoveryController.shared.restoreManagedWindows()
    if !failed.isEmpty {
        _ = io.err("Tiling is disabled. Original frames could not be restored for \(failed.count) windows; recovery entries were preserved. Run 'enable off' to retry.")
    }
}
