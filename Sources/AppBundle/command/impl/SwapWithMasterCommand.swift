import Common

struct SwapWithMasterCommand: Command {
    let args: SwapWithMasterCmdArgs
    let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io), let window = target.windowOrNil else { return io.err(noWindowIsFocused) }
        let workspace = target.workspace
        guard window.parent is TilingContainer, workspace.arrangement == .master else {
            return io.err("swap-with-master requires a tiled window in a master workspace")
        }
        workspace.normalizeMasterLayout()
        let current = workspace.masterGroupIndex
        guard let index = workspace.workspaceLayoutUnits.firstIndex(where: { $0 === window.topLevelWorkspaceGroup }) else { return false }
        if index != current { return workspace.promoteToMaster(window) }
        guard let next = workspace.workspaceLayoutUnits.enumerated().first(where: { $0.offset != current })?.element.mostRecentWindowRecursive else { return false }
        return workspace.promoteToMaster(next)
    }
}
