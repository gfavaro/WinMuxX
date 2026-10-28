import Foundation
import AppKit

@MainActor
func openWorkspaceSidebarFromCommand() {
    guard TrayMenuModel.shared.isEnabled, config.workspaceSidebar.enabled else { return }
    WorkspaceSidebarPanel.refreshAll()
    let focusedScopeId = TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId
    let panel = WorkspaceSidebarPanel.panel(for: focusedScopeId)
        ?? WorkspaceSidebarPanel.visiblePanels.first
        ?? WorkspaceSidebarPanel.shared
    if panel.inlineTextEditingActive ||
        (panel.viewModel.isWorkspaceSidebarExpanded && !config.workspaceSidebar.alwaysExpanded)
    {
        closeWorkspaceSidebarFromCommand(panel)
        return
    }
    panel.loadContent()
    panel.commandExpansionLocksCollapse = true
    panel.shouldLockNextSidebarSearchExpansion = true
    panel.bufferedCommandSidebarSearchKeys = []
    installWorkspaceSidebarCommandMouseUnlockMonitor(panel)
    panel.beginInlineTextEditing(
        locksExpansion: true,
        cancelsOnPointerExit: false,
        onCancel: {
            closeWorkspaceSidebarFromCommand(panel)
        },
        onKeyDown: { key in
            switch key {
                case .cancel:
                    closeWorkspaceSidebarFromCommand(panel)
                case .ignored:
                    break
                default:
                    panel.bufferedCommandSidebarSearchKeys.append(key)
                    NotificationCenter.default.post(
                        name: workspaceSidebarCommandSearchKeyNotification,
                        object: panel,
                        userInfo: [
                            workspaceSidebarCommandSearchPanelUserInfoKey: panel,
                            workspaceSidebarCommandSearchKeyUserInfoKey: key,
                        ]
                    )
            }
        },
    )
}

@MainActor
func closeWorkspaceSidebarFromCommand(_ panel: WorkspaceSidebarPanel) {
    panel.endInlineTextEditing()
    panel.cancelHoverReveal()
    panel.pendingCollapse?.cancel()
    panel.pendingCollapse = nil
    panel.pendingCollapseFinalize?.cancel()
    panel.pendingCollapseFinalize = nil
    if !config.workspaceSidebar.alwaysExpanded {
        NotificationCenter.default.post(name: workspaceSidebarWillCollapseNotification, object: panel)
    }
    panel.commandExpansionLocksCollapse = false
    panel.shouldLockNextSidebarSearchExpansion = false
    panel.bufferedCommandSidebarSearchKeys = []
    panel.removeCommandMouseUnlockMonitors()
    panel.animateVisibleSidebarWidth(workspaceSidebarRestingWidth(config.workspaceSidebar), animation: .easeInOut(duration: panel.animationDuration))
    panel.viewModel.isWorkspaceSidebarExpanded = config.workspaceSidebar.alwaysExpanded
    panel.updateMousePassthrough()
}

@MainActor
private func installWorkspaceSidebarCommandMouseUnlockMonitor(_ panel: WorkspaceSidebarPanel) {
    panel.removeCommandMouseUnlockMonitors()
    panel.commandMouseUnlockPoint = mouseLocation
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak panel] in
        guard let panel, panel.commandExpansionLocksCollapse else { return }
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak panel] event in
            Task { @MainActor in
                panel?.unlockCommandSidebarExpansionIfMouseMoved()
            }
            return event
        }
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak panel] _ in
            Task { @MainActor in
                panel?.unlockCommandSidebarExpansionIfMouseMoved()
            }
        }
        panel.commandMouseUnlockMonitors = [localMonitor, globalMonitor].compactMap { $0 }
    }
}

private let workspaceSidebarCommandMouseUnlockDistance: CGFloat = 1

extension WorkspaceSidebarPanel {
    func removeCommandMouseUnlockMonitors() {
        for monitor in commandMouseUnlockMonitors { NSEvent.removeMonitor(monitor) }
        commandMouseUnlockMonitors = []
        commandMouseUnlockPoint = nil
    }

    @MainActor
    func unlockCommandSidebarExpansionIfMouseMoved() {
        guard commandExpansionLocksCollapse,
              let origin = commandMouseUnlockPoint
        else { return }
        let current = mouseLocation
        guard hypot(current.x - origin.x, current.y - origin.y) > workspaceSidebarCommandMouseUnlockDistance else { return }
        commandExpansionLocksCollapse = false
        shouldLockNextSidebarSearchExpansion = false
        inlineTextEditingLocksExpansion = false
        removeCommandMouseUnlockMonitors()
        updateHoverStateFromMousePosition()
    }
}
