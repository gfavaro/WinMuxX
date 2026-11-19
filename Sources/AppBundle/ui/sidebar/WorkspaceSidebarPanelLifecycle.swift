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
        defer { requestPublicStateUpdate() }
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
                currentWidth: state.visibleWidth,
                previousExpandedWidth: persistentExpansionWidth,
                expandedWidth: layout.expandedWidth,
            )
            persistentExpansionWidth = layout.expandedWidth
            state.isExpanded = true
            if state.visibleWidth != targetWidth {
                state.visibleWidth = targetWidth
            }
        } else if persistentExpansionWidth != nil {
            cancelExpansionWork()
            persistentExpansionWidth = nil
            state.isExpanded = false
            state.visibleWidth = layout.collapsedWidth
        } else if state.visibleWidth == 0 {
            state.visibleWidth = state.isExpanded
                ? layout.expandedWidth
                : layout.collapsedWidth
        } else if !state.isExpanded,
                  pendingExpand == nil,
                  pendingCollapse == nil,
                  state.visibleWidth != layout.collapsedWidth
        {
            // Apply auto-hide/collapsed-width changes immediately on config reload.
            state.visibleWidth = layout.collapsedWidth
        } else if state.isExpanded,
                  pendingExpand == nil,
                  pendingCollapse == nil,
                  state.visibleWidth != layout.expandedWidth
        {
            state.visibleWidth = layout.expandedWidth
        }
        updateMousePassthrough()
        orderFrontRegardless()
        updateCornerBacking()
        // Panel geometry may have just changed under a stationary cursor; hover is otherwise
        // event-driven from the pointer monitors.
        scheduleHoverRecheckSoon()
    }

    func resetHiddenSidebarState() {
        defer { requestPublicStateUpdate() }
        // Runs for every inactive panel on every refreshAll — guard the shared-model writes so
        // they don't invalidate every observer each session.
        workspaceSidebarDropTargets = []
        setWorkspaceSidebarDropPreviewIfChanged(nil)
        TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName = nil
        state.visibleWidth = 0
        cornerBacking.orderOut(nil)
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
        state.contentLoaded = true
        scheduleContentUnload()
    }

    func syncContentLoading() {
        if workspaceSidebarUnloadsWhenResting(config.workspaceSidebar) {
            if state.contentLoaded, pendingContentUnload == nil { scheduleContentUnload() }
        } else {
            pendingContentUnload?.cancel()
            pendingContentUnload = nil
            state.contentLoaded = true
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
                self.state.contentLoaded = false
            } else {
                self.scheduleContentUnload()
            }
        }
        pendingContentUnload = unload
        DispatchQueue.main.asyncAfter(deadline: .now() + workspaceSidebarContentUnloadDelay, execute: unload)
    }

    private var isRestingHidden: Bool {
        state.visibleWidth <= 0.5 && !state.isExpanded &&
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
