import AppKit
import Common

struct FlattenWorkspaceTreeCommand: Command {
    let args: FlattenWorkspaceTreeCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let workspace = target.workspace
        let focusedWindow = focus.windowOrNil
        let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
        for window in windows {
            window.bind(to: workspace.rootTilingContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
        }
        workspace.normalizeContainers()
        workspace.rootTilingContainer.dwindleSplitRatios = []
        if workspace.rootTilingContainer.isExplicitDwindle {
            workspace.rootTilingContainer.dwindleChildRatios = Array(repeating: 1, count: windows.count)
        }
        workspace.rootTilingContainer.dwindleOrientation = switch config.defaultRootContainerOrientation {
            case .auto: nil
            case .horizontal: .h
            case .vertical: .v
        }
        if let focusedWindow { focusedWindow.markAsMostRecentChild() }
        return true
    }
}
