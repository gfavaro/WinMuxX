import AppKit
import Common
import CoreGraphics
import SwiftUI

extension WorkspaceSidebarPanel {
    func refresh() {
        refresh(on: workspaceSidebarResolvedPanelMonitor())
    }

    func refresh(on monitor: Monitor) {
        guard let layout = currentSidebarPanelLayout(on: monitor) else {
            cancelExpansionWork()
            resetHiddenSidebarState()
            return
        }

        if frame != layout.frame {
            setFrame(layout.frame, display: true, animate: false)
        }
        if config.workspaceSidebar.alwaysExpanded {
            cancelExpansionWork()
            let targetWidth = workspaceSidebarPersistentVisibleWidth(
                currentWidth: viewModel.workspaceSidebarVisibleWidth,
                previousExpandedWidth: persistentExpansionWidth,
                expandedWidth: layout.expandedWidth,
            )
            persistentExpansionWidth = layout.expandedWidth
            viewModel.isWorkspaceSidebarExpanded = true
            if viewModel.workspaceSidebarVisibleWidth != targetWidth {
                viewModel.workspaceSidebarVisibleWidth = targetWidth
            }
        } else if persistentExpansionWidth != nil {
            cancelExpansionWork()
            persistentExpansionWidth = nil
            viewModel.isWorkspaceSidebarExpanded = false
            viewModel.workspaceSidebarVisibleWidth = layout.collapsedWidth
        } else if viewModel.workspaceSidebarVisibleWidth == 0 {
            viewModel.workspaceSidebarVisibleWidth = viewModel.isWorkspaceSidebarExpanded
                ? layout.expandedWidth
                : layout.collapsedWidth
        } else if !viewModel.isWorkspaceSidebarExpanded,
                  pendingExpand == nil,
                  pendingCollapse == nil,
                  viewModel.workspaceSidebarVisibleWidth != layout.collapsedWidth
        {
            // Apply auto-hide/collapsed-width changes immediately on config reload.
            viewModel.workspaceSidebarVisibleWidth = layout.collapsedWidth
        } else if viewModel.isWorkspaceSidebarExpanded,
                  pendingExpand == nil,
                  pendingCollapse == nil,
                  viewModel.workspaceSidebarVisibleWidth != layout.expandedWidth
        {
            viewModel.workspaceSidebarVisibleWidth = layout.expandedWidth
        }
        updateMousePassthrough()
        orderFrontRegardless()
        // Panel geometry may have just changed under a stationary cursor; hover is otherwise
        // event-driven from the pointer monitors.
        scheduleHoverRecheckSoon()
    }

    func refreshForCurrentDragIfNeeded() {
        guard isMouseWindowDragInProgress() else { return }
        WorkspaceSidebarPanel.refreshAll()
    }

    func resetHiddenSidebarState() {
        // Runs for every inactive panel on every refreshAll — guard the shared-model writes so
        // they don't invalidate every observer each session.
        workspaceSidebarDropTargets = []
        setWorkspaceSidebarDropPreviewIfChanged(nil)
        TrayMenuModel.shared.setIfChanged(\.workspaceSidebarHoveredWorkspaceName, nil)
        viewModel.setIfChanged(\.workspaceSidebarVisibleWidth, 0)
        if isVisible {
            orderOut(nil)
        }
    }
}

extension WorkspaceSidebarPanel {
    func updateMeasuredContentHeight(_ height: CGFloat) {
        guard config.workspaceSidebar.heightMode == .centered, height.isFinite, height > 0,
              abs(measuredContentHeight - height) > 1 else { return }
        measuredContentHeight = ceil(height)
        // Preference delivery occurs during layout; defer AppKit resizing to avoid reentry.
        DispatchQueue.main.async { [weak self] in
            guard let self, let monitor = sortedMonitors.first(where: { workspaceSidebarMonitorScopeId(for: $0) == self.monitorScopeId }) else { return }
            self.refresh(on: monitor)
        }
    }
}
