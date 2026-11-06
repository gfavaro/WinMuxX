import Common

/// Which workspaces a listing covers.
enum WorkspaceListScope {
    /// `list-workspaces` and menus: user-facing, in presentation order.
    case presentation
    /// `list-windows`: user-facing, in tree order.
    case userFacing
    /// The palette: every workspace that can hold a window.
    case all
}

@MainActor
func listedWorkspaces(_ scope: WorkspaceListScope) -> [Workspace] {
    switch scope {
        case .presentation: userFacingWorkspaces(orderedWorkspacesForPresentation(), focusedWorkspace: focus.workspace)
        case .userFacing: userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace)
        case .all: Workspace.all
    }
}

/// Workspaces menus offer, each with the `workspace` argument that reaches it.
@MainActor
func workspaceCommandTargets() -> [(workspace: Workspace, target: String)] {
    listedWorkspaces(.presentation)
        .filter { $0.projectId == focus.workspace.projectId }
        .map { workspace in
            let target = workspace.usesAutomaticDisplayName
                ? automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: focus.workspace).map(String.init) ?? workspace.name
                : workspace.name
            return (workspace, target)
        }
}

/// Displays currently covered by native fullscreen content. Asked on every refresh;
/// usually nothing is fullscreen, and then WindowServer is not asked.
@MainActor
func fullscreenDisplayIDs() -> Set<String> {
    fullscreenWindowDisplays(onScreen: onScreenWindowFrames(nativeFullscreenWindowIds()))
}

/// Brings a window forward from the palette or minimap.
@MainActor
func bringWindowForward(_ windowId: UInt32) {
    guard let window = Window.get(byId: windowId), let liveFocus = window.toLiveFocusOrNil() else { return }
    window.markAsMostRecentChild()
    _ = setFocus(to: liveFocus)
    window.nativeFocus()
}
