import AppKit
import Common
import Observation

/// What one display's sidebar keeps for itself. Everything shared across displays it reads
/// from `TrayMenuModel.shared`.
@MainActor
@Observable
final class WorkspaceSidebarPanelState {
    /// The display this panel belongs to.
    let targetMonitorScopeId: String
    /// The display filter chosen in this panel's monitor selector.
    var selectedMonitorScopeId: String = workspaceSidebarDefaultScopeId
    var isExpanded = false {
        didSet { if oldValue != isExpanded { requestPublicStateUpdate() } }
    }
    var visibleWidth: CGFloat = 0
    /// Whether the pointer is over this display's sidebar; hover is shared, so only this panel shows it.
    var pointerIsInside = false
    /// Whether the sidebar's view tree exists. See WorkspaceSidebarPanel.loadContent.
    var contentLoaded = true
    /// The configuration as this display shows it (frosted over a Scrolling workspace).
    var configuration: WorkspaceSidebarConfiguration = .empty
    /// The project of the workspace this display shows.
    var activeProjectId: WorkspaceProjectId = workspaceProjectDefaultId

    init(targetMonitorScopeId: String) {
        self.targetMonitorScopeId = targetMonitorScopeId
    }
}
