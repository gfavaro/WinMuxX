import Common

struct WorkspaceLayoutCommand: Command {
    let args: WorkspaceLayoutCmdArgs
    let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let workspace = target.workspace
        let window = target.windowOrNil
        if let window, !(window.parent is TilingContainer) {
            return io.err("The window is non-tiling")
        }
        let current = workspace.arrangement
        let layout = nextLayout(in: args.layouts.val, matching: { $0 == current })
        // Arrangement transitions retain the live nested tree. In particular, an
        // empty workspace can opt in before its first window is detected.
        workspace.transitionArrangement(to: layout, focused: window)
        WorkspaceGestureCoordinator.shared.overviewPresentationChanged()
        return true
    }
}

extension Workspace {
    @MainActor
    var layoutName: String {
        arrangement.rawValue
    }
}
