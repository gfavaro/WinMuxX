import AppKit
import Common

struct WorkspaceBackAndForthCommand: Command {
    let args: WorkspaceBackAndForthCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> Bool {
        if runtime.workspaceBackend.kind == .native {
            return await runtime.workspaceBackend.nativeNavigation.runBackAndForth(io: io)
        }
        return activatePreviousWorkspace(on: focus.workspace.workspaceMonitor)
    }
}

@MainActor
func activatePreviousWorkspace(on monitor: Monitor) -> Bool {
    guard let previousId = runtime.workspaces.monitorViewportsById[MonitorViewportId(monitor)]?.previousWorkspaceId,
          let workspace = runtime.workspaces.workspaceById[previousId], !workspace.isArchived,
          workspace != monitor.activeWorkspace else { return false }
    return activateWorkspaceForUser(workspace, on: monitor)
}
