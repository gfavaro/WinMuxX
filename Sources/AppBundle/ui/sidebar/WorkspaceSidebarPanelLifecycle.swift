import AppKit
import Common
import CoreGraphics
import SwiftUI

extension WorkspaceSidebarPanel {
    func refresh() {
        refresh(on: workspaceSidebarResolvedPanelMonitor())
    }

    func refresh(on monitor: Monitor) {
        guard !isRetired else { return }
        syncContentLoading()
        if WorkspacePresentationController.shared.suppressesChrome(on: monitor) {
            orderOut(nil)
            return
        }
        defer { requestPublicStateUpdate() }
        if appliedHoverOpenDelayMs != config.workspaceSidebar.hoverOpenDelayMs {
            appliedHoverOpenDelayMs = config.workspaceSidebar.hoverOpenDelayMs
            cancelHoverReveal()
        }
        guard !WorkspaceOverviewController.shared.isOpen else {
            cancelExpansionWork()
            resetHiddenSidebarState()
            return
        }
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
        defer { requestPublicStateUpdate() }
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

/// A resting auto-hide sidebar draws nothing, yet its view tree held several megabytes
/// per display. It is built from the hover dwell, before the sidebar opens, and dropped
/// once the sidebar has rested hidden for a while. Centered sidebars size the panel from
/// their content, so they keep it.
func workspaceSidebarUnloadsWhenResting(_ sidebarConfig: WorkspaceSidebarConfig) -> Bool {
    sidebarConfig.autoHide && !sidebarConfig.alwaysExpanded && sidebarConfig.heightMode != .centered
}

let workspaceSidebarContentUnloadDelay: TimeInterval = 10

extension WorkspaceSidebarPanel {
    /// Call before anything reveals the sidebar, outside an animation, so the tree is not
    /// inserted with a transition.
    func loadContent() {
        guard !isRetired else { return }
        _ = viewModel.setIfChanged(\.workspaceSidebarContentLoaded, true)
        scheduleContentUnload()
    }

    func syncContentLoading() {
        if workspaceSidebarUnloadsWhenResting(config.workspaceSidebar) {
            if viewModel.workspaceSidebarContentLoaded, pendingContentUnload == nil { scheduleContentUnload() }
        } else {
            pendingContentUnload?.cancel()
            pendingContentUnload = nil
            _ = viewModel.setIfChanged(\.workspaceSidebarContentLoaded, true)
        }
    }

    private func scheduleContentUnload() {
        pendingContentUnload?.cancel()
        pendingContentUnload = nil
        guard workspaceSidebarUnloadsWhenResting(config.workspaceSidebar) else { return }
        let unload = DispatchWorkItem { [weak self] in
            guard let self, !self.isRetired else { return }
            self.pendingContentUnload = nil
            if self.isRestingHidden {
                _ = self.viewModel.setIfChanged(\.workspaceSidebarContentLoaded, false)
            } else {
                self.scheduleContentUnload()
            }
        }
        pendingContentUnload = unload
        DispatchQueue.main.asyncAfter(deadline: .now() + workspaceSidebarContentUnloadDelay, execute: unload)
    }

    private var isRestingHidden: Bool {
        viewModel.workspaceSidebarVisibleWidth <= 0.5 && !viewModel.isWorkspaceSidebarExpanded &&
            pendingExpand == nil && pendingCollapse == nil && pendingCollapseFinalize == nil &&
            !inlineTextEditingActive && !commandExpansionLocksCollapse && menuTrackingDepth == 0 &&
            !isMouseInsideHoverRegion() && !shouldLockExpansionForSidebarDrag()
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
