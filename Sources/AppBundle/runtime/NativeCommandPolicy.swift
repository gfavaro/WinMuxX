/// Native navigation and query admission remains separate from the shared command
/// fence so unsupported shortcuts remain available to macOS.
@MainActor
enum NativeCommandPolicy {
    static func accepts(_ command: any Command, tilingEnabled: Bool) -> Bool {
        isNativeDiagnosticOrQuery(command) ||
            (isNativeNavigation(command) && (tilingEnabled || command is WorkspaceCommand || command is WorkspaceBackAndForthCommand)) ||
            (tilingEnabled && NativeTilingCoordinator.supports(command))
    }

    static func acceptsSequence(_ commands: [any Command]) -> Bool {
        commands.allSatisfy(runsOutsideNativeTilingFence) || commands.allSatisfy {
            !runsOutsideNativeTilingFence($0) || $0 is DoctorCommand || $0 is ReloadConfigCommand
        }
    }

    static func runsOutsideNativeTilingFence(_ command: any Command) -> Bool {
        isNativeNavigation(command) || isNativeDiagnosticOrQuery(command)
    }

    /// Read-only commands that answer from config or native snapshots, the palette and
    /// sidebar, whose selections run their own native commands, and pointer moves.
    static func isNativeDiagnosticOrQuery(_ command: any Command) -> Bool {
        switch command {
            case is DoctorCommand, is ReloadConfigCommand, is ListWorkspacesCommand, is ListWindowsCommand,
                 is ListAppsCommand, is ListModesCommand, is ListExecEnvVarsCommand, is ConfigCommand,
                 is PaletteCommand, is OpenSidebarCommand, is ListMonitorsCommand, is MoveMouseCommand,
                 // Starts a process; no window or Space is touched.
                 is ExecAndForgetCommand,
                 // Switches key bindings only; it must work while tiling is paused.
                 is ModeCommand,
                 // Draws an overlay; no window or Space is touched.
                 is NoPeekCommand: true
            default: false
        }
    }

    /// Space navigation and cross-Space window moves: Space-level operations that run
    /// without native tiling, outside its command fence.
    static func isNativeNavigation(_ command: any Command) -> Bool {
        switch command {
            case let command as WorkspaceCommand: NativeSpaceNavigator.supports(command.args)
            case let command as MoveNodeToWorkspaceCommand: NativeWindowSpaceMoves.supports(command.args)
            // Focus may leave the desktop toward another display; it moves no window.
            case let command as FocusCommand:
                command.args.boundaries == .allMonitorsOuterFrame || focusesWindowOnHiddenDesktop(command)
            case is WorkspaceBackAndForthCommand, is MoveNodeToMonitorCommand, is FocusMonitorCommand,
                 is MoveWorkspaceToMonitorCommand, is FocusBackAndForthCommand, is EnableCommand: true
            default: false
        }
    }

    /// `focus --window-id` for a window whose desktop is not showing switches there first,
    /// so it runs as navigation rather than inside the tiling fence.
    static func focusesWindowOnHiddenDesktop(_ command: FocusCommand) -> Bool {
        guard let id = command.args.windowId, let workspace = Window.get(byId: id)?.nodeWorkspace else { return false }
        return !workspace.isVisible
    }

}
