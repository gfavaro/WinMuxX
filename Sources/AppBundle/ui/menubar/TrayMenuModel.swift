import AppKit
import Common
import Observation

/// What the menu bar, sidebars and tab strips show, shared by every display. A sidebar's own
/// state is in its WorkspaceSidebarPanelState.
@Observable
public final class TrayMenuModel {
    @MainActor public static let shared = TrayMenuModel()

    init() {}

    var modePresentation: ModePresentation?
    var menuBarWorkspaceIndicator: String = "1"
    var menuBarDisplayIndicators: [MenuBarDisplayIndicator] = []
    var menuBarWorkspaceName: String = ""
    var menuBarWorkspaceArrangement: WorkspaceLayoutName = .dwindle
    /// Is "layouting" enabled
    var isEnabled: Bool = true
    var shortcutHealth: ShortcutHealth = .available
    var workspaces: [WorkspaceViewModel] = []
    var workspaceSidebarWorkspaces: [WorkspaceSidebarWorkspaceViewModel] = []
    var workspaceSidebarProjects: [WorkspaceSidebarProjectViewModel] = []
    var workspaceSidebarActiveProjectId: WorkspaceProjectId = workspaceProjectDefaultId
    var workspaceSidebarMonitorScopes: [WorkspaceSidebarMonitorScopeViewModel] = []
    var workspaceSidebarFocusedMonitorScopeId: String = ""
    var workspaceSidebarShowsMonitorSelector: Bool = false
    var workspaceSidebarDropPreview: WorkspaceSidebarDropPreviewViewModel? = nil
    var workspaceSidebarReorderPreview: WorkspaceSidebarReorderPreview? = nil
    var windowTabStrips: [WindowTabStripViewModel] = []
    var workspaceSidebarTopPadding: CGFloat = 12
    var workspaceSidebarHoveredWorkspaceName: String? = nil
    var menuBarConfiguration = MenuBarConfig()
    /// Bumped when the wallpaper changes, so whatever samples it samples again.
    var wallpaperRefreshGeneration: UInt64 = 0
}

/// What the menu bar shows for a workspace: its label's initial, else its number.
@MainActor private func menuBarIndicatorText(for workspace: Workspace, focusedWorkspace: Workspace) -> String {
    let number = automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: focusedWorkspace)
        ?? Int(workspace.name)
        ?? userFacingWorkspaces(orderedWorkspacesForPresentation(), focusedWorkspace: focusedWorkspace)
            .filter { $0.projectId == workspace.projectId }.firstIndex(of: workspace).map { $0 + 1 }
        ?? 1
    let persistentLabel = workspace.isConfiguredPersistent && parsePositiveWorkspaceDisplayIndex(workspace.name) == nil ? workspace.name : nil
    return menuBarWorkspaceIndicator(label: config.workspaceSidebar.workspaceLabels[workspace.name] ?? persistentLabel, number: number)
}

@MainActor func updateTrayText() {
    let focus = focus
    let workspace = focus.workspace
    TrayMenuModel.shared.menuBarWorkspaceIndicator = menuBarIndicatorText(for: workspace, focusedWorkspace: workspace)
    let mainPoint = mainMonitor.rect.topLeftCorner
    TrayMenuModel.shared.menuBarDisplayIndicators = mainDisplayFirst(sortedMonitors) { $0.rect.topLeftCorner == mainPoint }.map {
        MenuBarDisplayIndicator(text: menuBarIndicatorText(for: $0.activeWorkspace, focusedWorkspace: workspace),
                                isFocused: $0.activeWorkspace == workspace)
    }
    TrayMenuModel.shared.menuBarWorkspaceName = workspaceDisplayName(workspace.name)
    TrayMenuModel.shared.menuBarWorkspaceArrangement = workspace.arrangement
    let workspaces = userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace).filter {
        $0.projectId == activeWorkspaceProjectId(for: $0.workspaceMonitor)
    }.map {
        let apps = $0.allLeafWindowsRecursive.map { $0.app.name?.takeIf { !$0.isEmpty } }.filterNotNil().toSet()
        let dash = " - "
        let suffix = switch true {
            case !apps.isEmpty: dash + apps.sorted().joinTruncating(separator: ", ", length: 25)
            default: ""
        }
        let hasFullscreenWindows = $0.allLeafWindowsRecursive.contains { $0.isFullscreen }
        return WorkspaceViewModel(
            name: $0.name,
            displayName: workspaceDisplayName($0.name),
            suffix: suffix,
            isFocused: focus.workspace == $0,
            isEffectivelyEmpty: !workspaceHasSidebarVisibleWindows($0),
            isVisible: $0.isVisible,
            hasFullscreenWindows: hasFullscreenWindows,
        )
    }
    TrayMenuModel.shared.workspaces = workspaces
}
