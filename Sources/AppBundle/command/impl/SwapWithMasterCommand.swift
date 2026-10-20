import Common

struct SwapWithMasterCommand: Command {
    let args: SwapWithMasterCmdArgs
    let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io), let window = target.windowOrNil else { return io.err(noWindowIsFocused) }
        let workspace = target.workspace
        guard window.parent is TilingContainer, workspace.rootTilingContainer.layout == .master else {
            return io.err("swap-with-master requires a tiled window in a master workspace")
        }
        workspace.normalizeMasterLayout()
        if workspace.promoteToMaster(window) { return true }
        guard let stack = workspace.rootTilingContainer.children.compactMap({ $0 as? TilingContainer }).first(where: \.isMasterStack),
              let next = stack.children.first?.mostRecentWindowRecursive else { return false }
        return workspace.promoteToMaster(next)
    }
}
