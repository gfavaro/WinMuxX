import Common

@MainActor
final class VirtualWorkspaceBackend: WorkspaceBackend {
    func run(_ command: any Command, env: CmdEnv, io: CmdIo) async throws -> Bool? { nil }

    func listedWorkspaces(_ scope: WorkspaceListScope) -> [Workspace] {
        switch scope {
            case .presentation: userFacingWorkspaces(orderedWorkspacesForPresentation(), focusedWorkspace: focus.workspace)
            case .userFacing: userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace)
            case .all: Workspace.all
        }
    }

    func commandTargets() -> [(workspace: Workspace, target: String)] {
        listedWorkspaces(.presentation)
            .filter { $0.projectId == focus.workspace.projectId }
            .map { workspace in
                let target = workspace.usesAutomaticDisplayName
                    ? automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: focus.workspace).map(String.init) ?? workspace.name
                    : workspace.name
                return (workspace, target)
            }
    }

    func scriptName(of workspace: Workspace) -> String { workspace.name }
    func workspace(named name: String) -> Workspace? { Workspace.existing(byName: name) }
    func title(ofWorkspaceNamed name: String) -> String { workspaceDisplayName(name) }
    func isAlwaysUserFacing(_ workspace: Workspace) -> Bool { false }

    func bringForward(_ windowId: UInt32) async throws -> String? {
        guard let window = Window.get(byId: windowId), let liveFocus = window.toLiveFocusOrNil() else { return nil }
        window.markAsMostRecentChild()
        _ = setFocus(to: liveFocus)
        window.nativeFocus()
        return nil
    }

    func shownWorkspace(on monitor: Monitor) -> Workspace? { monitor.activeWorkspace }
    func focusDidMove(to window: Window?) {}
    func diagnosticsReport() async -> String? { nil }
    func windowGeometryChanged(_ windowId: UInt32?, moved: Bool) -> Bool { false }
}

