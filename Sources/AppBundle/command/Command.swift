import AppKit
import Common

protocol Command: WinMuxAny, Equatable, Sendable {
    associatedtype T where T: CmdArgs
    var args: T { get }
    @MainActor
    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool

    /// We should refresh closedWindowsCache when the command can change the tree or visible workspace assignment
    var shouldResetClosedWindowsCache: Bool { get }

    /// Some commands fully update the in-memory model and only need the light-session layout/UI pass.
    /// Native macOS state transitions or arbitrary side effects should keep the follow-up full refresh.
    var canSkipPostCommandRefresh: Bool { get }
    /// Queries read the established model and do not run layout/UI/persistence passes.
    var isQuery: Bool { get }
    /// UI-only actions do not mutate the workspace model or require a layout pass.
    var isPresentation: Bool { get }
}

extension Command {
    var isQuery: Bool { false }
    var isPresentation: Bool { false }

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.args.equals(rhs.args)
    }

    nonisolated func equals(_ other: any Command) -> Bool {
        (other as? Self).flatMap { self == $0 } ?? false
    }
}

extension Command {
    var info: CmdStaticInfo { T.info }
}

extension Command {
    var canSkipPostCommandRefresh: Bool {
        switch self {
            case is BalanceSizesCommand,
                 is ConfigCommand,
                 is DebugWindowsCommand,
                 is FlattenWorkspaceTreeCommand,
                 is FocusBackAndForthCommand,
                 is FocusCommand,
                 is FocusMonitorCommand,
                 is FullscreenCommand,
                 is JoinWithCommand,
                 is LayoutCommand,
                 is ListAppsCommand,
                 is ListExecEnvVarsCommand,
                 is ListModesCommand,
                 is ListMonitorsCommand,
                 is ListWindowsCommand,
                 is ListWorkspacesCommand,
                 is ModeCommand,
                 is MoveCommand,
                 is MoveMouseCommand,
                 is MoveNodeToMonitorCommand,
                 is MoveNodeToProjectCommand,
                 is MoveNodeToWorkspaceCommand,
                 is MoveWorkspaceToMonitorCommand,
                 is OpenSidebarCommand,
                 is ProjectCommand,
                 is ResizeCommand,
                 is SplitCommand,
                 is StackWithCommand,
                 is SummonWorkspaceCommand,
                 is SwapCommand,
                 is SwapWithMasterCommand,
                 is WorkspaceBackAndForthCommand,
                 is WorkspaceCommand,
                 is WorkspaceLayoutCommand:
                true
            default:
                false
        }
    }

    @MainActor
    @discardableResult
    func run(_ env: CmdEnv, _ stdin: consuming CmdStdin) async throws -> CmdResult {
        return try await [self].runCmdSeq(env, stdin)
    }

    var isExec: Bool { self is ExecAndForgetCommand }
}

// There are 4 entry points for running commands:
// 1. config keybindings
// 2. CLI requests to server
// 3. on-window-detected callback
// 4. Tray icon buttons
extension [Command] {
    var canSkipPostCommandRefresh: Bool {
        allSatisfy(\.canSkipPostCommandRefresh)
    }

    @MainActor
    func runCmdSeq(_ env: CmdEnv, _ io: sending CmdIo) async throws -> Bool {
        if runtime.workspaceBackend.kind == .native, runtime.workspaceBackend.nativeTilingEnabled,
           !NativeTilingCommandScope.active, contains(where: {
               !WorkspaceBackendState.runsOutsideNativeTilingFence($0)
           }) {
            return try await runtime.workspaceBackend.nativeTiling.run(self, env: env, io: io)
        }
        var isSucc = true
        for command in self {
            if !runtime.workspaceBackend.accepts(command) {
                io.err("Command '\(command.args)' is unsupported by the experimental native backend. Use doctor for native Space diagnostics; native gestures remain owned by macOS.")
                return false
            }
            try WindowDetectionOperations.current?.check()
            if NativeTilingCommandScope.validateTarget?() == false {
                return io.err("Native command target changed during execution")
            }
            await WorkspacePresentationController.shared.cancelForCommand(command)
            if NativeTilingCommandScope.validateTarget?() == false {
                return io.err("Native command target changed during execution")
            }
            if WorkspaceBackendState.isNativeNavigation(command), !NativeTilingCommandScope.active {
                await runtime.workspaceBackend.awaitCurrentObservation()
            }
            let commandSucc: Bool
            if let handled = try await runtime.workspaceBackend.current.run(command, env: env, io: io) {
                commandSucc = handled
            } else {
                commandSucc = try await command.run(env, io)
            }
            isSucc = commandSucc && isSucc
            if !command.isQuery && !command.isPresentation {
                refreshModel()
                let focusOnly = command is FocusMonitorCommand || command is ModeCommand || command is ExecAndForgetCommand
                requestPublicStateUpdate(structural: !focusOnly)
            }
            if commandSucc && command.shouldResetClosedWindowsCache {
                syncClosedWindowsCacheToCurrentWorld()
            }
        }
        return isSucc
    }

    @MainActor
    func runCmdSeq(_ env: CmdEnv, _ stdin: consuming CmdStdin) async throws -> CmdResult {
        let io: CmdIo = CmdIo(stdin: stdin)
        let isSucc = try await runCmdSeq(env, io)
        return CmdResult(stdout: io.stdout, stderr: io.stderr, exitCode: isSucc ? 0 : 1)
    }
}
