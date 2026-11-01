import AppKit
import Common

struct UndoLayoutCommand: Command {
    let args: UndoLayoutCmdArgs
    let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard try await LayoutUndoHistory.shared.undo(target.workspace) else {
            return io.err("Nothing to undo on this workspace")
        }
        return true
    }
}

/// The focused workspace's tree before each layout command that changed it, newest
/// last, so `undo-layout` can put it back. Undo only rearranges windows still on the
/// workspace: one closed or moved away since is left where it is, and one that
/// arrived since is tiled into the restored tree.
@MainActor
final class LayoutUndoHistory {
    static let shared = LayoutUndoHistory()
    private static let limit = 20
    /// By workspace name, which outlives a workspace object recreated for the same desktop.
    private var entries: [String: [FrozenWorkspace]] = [:]

    static func records(_ command: any Command) -> Bool {
        switch command {
            case is LayoutCommand, is WorkspaceLayoutCommand, is MoveCommand, is SwapCommand, is SwapWithMasterCommand,
                 is JoinWithCommand, is SplitCommand, is StackWithCommand, is FlattenWorkspaceTreeCommand,
                 is BalanceSizesCommand, is ResizeCommand, is ScrollingWidthCommand, is ScrollingMoveCommand,
                 is ScrollingPinCommand:
                true
            default:
                false
        }
    }

    /// The state to compare with after `command`, when it is one undo covers.
    func before(_ command: any Command) -> (Workspace, FrozenWorkspace)? {
        Self.records(command) ? (focus.workspace, FrozenWorkspace(focus.workspace)) : nil
    }

    func commandFinished(_ before: (Workspace, FrozenWorkspace)) {
        let (workspace, frozen) = before
        guard FrozenWorkspace(workspace) != frozen else { return }
        entries[workspace.name, default: []].append(frozen)
        if entries[workspace.name]!.count > Self.limit { entries[workspace.name]!.removeFirst() }
    }

    func undo(_ workspace: Workspace) async throws -> Bool {
        guard let frozen = entries[workspace.name]?.popLast() else { return false }
        let windows = workspace.allLeafWindowsRecursive + workspace.floatingWindows
        guard let any = windows.first else { return true }
        let world = FrozenWorld(workspaces: [frozen], monitors: [], windowIds: [])
        _ = try await restoreFrozenWorldIfNeeded(world, newlyDetectedWindow: any,
                                                 matchedWindows: Dictionary(windows.map { ($0.windowId, $0) }, uniquingKeysWith: { a, _ in a }),
                                                 restoreVisibleWorkspaces: false)
        return true
    }

    func reset() { entries = [:] }
}
