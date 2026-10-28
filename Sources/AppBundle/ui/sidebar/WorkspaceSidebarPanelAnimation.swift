import AppKit
import Common
import CoreGraphics
import SwiftUI

extension WorkspaceSidebarPanel {
    func animateVisibleSidebarWidth(_ width: CGFloat, animation: Animation) {
        guard !isRetired else { return }
        loadContent()
        debugWorkspaceSidebarHoverLog("animateWidth panel=\(monitorScopeId) from=\(viewModel.workspaceSidebarVisibleWidth) to=\(width) frame=\(frame) mouse=\(NSEvent.mouseLocation) ignores=\(ignoresMouseEvents) expanded=\(viewModel.isWorkspaceSidebarExpanded)")
        pendingBackingResize?.cancel()
        let resize = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingBackingResize = nil
            guard let monitor = workspaceSidebarMonitor(forScopeId: self.monitorScopeId),
                  let layout = self.currentSidebarPanelLayout(on: monitor) else { return }
            if self.frame != layout.frame {
                self.setFrame(layout.frame, display: true, animate: false)
                self.updateMousePassthrough()
            }
        }
        pendingBackingResize = resize
        // Grow before SwiftUI starts revealing content. Shrink only after the
        // spring cue and collapse animation have settled.
        if let monitor = workspaceSidebarMonitor(forScopeId: monitorScopeId),
           let layout = currentSidebarPanelLayout(on: monitor), frame != layout.frame {
            setFrame(layout.frame, display: true, animate: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(animationDuration, hoverCueAnimationResponse) + 0.1, execute: resize)
        withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : animation) {
            viewModel.workspaceSidebarVisibleWidth = width
        }
        updateMousePassthrough()
        // The hover region just changed size under a possibly stationary cursor.
        scheduleHoverRecheckSoon()
    }

    func expandSidebar(to expandedWidth: CGFloat) {
        guard !isRetired else { return }
        debugWorkspaceSidebarHoverLog("expandSidebar panel=\(monitorScopeId) target=\(expandedWidth) visible=\(viewModel.workspaceSidebarVisibleWidth) frame=\(frame) mouse=\(NSEvent.mouseLocation)")
        // Search focus and hover updates may request the same reveal again.
        // Keep its notification and animation intact instead of restarting them.
        if viewModel.isWorkspaceSidebarExpanded, viewModel.workspaceSidebarVisibleWidth == expandedWidth,
           pendingCollapse == nil, pendingCollapseFinalize == nil {
            updateMousePassthrough()
            return
        }
        cancelHoverReveal()
        NotificationCenter.default.post(name: workspaceSidebarWillExpandNotification, object: self)
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
        // Restore the collapsed panel before setting the expansion target. Otherwise
        // refresh() installs the full width before SwiftUI can animate its reveal.
        if !isVisible {
            refresh()
        }
        viewModel.isWorkspaceSidebarExpanded = true
        guard viewModel.workspaceSidebarVisibleWidth != expandedWidth else {
            updateMousePassthrough()
            return
        }
        animateVisibleSidebarWidth(expandedWidth, animation: .easeInOut(duration: animationDuration))
    }

    func cancelExpansionWork() {
        debugWorkspaceSidebarHoverLog("cancelExpansionWork panel=\(monitorScopeId) pendingExpand=\(pendingExpand != nil) pendingCollapse=\(pendingCollapse != nil) pendingFinalize=\(pendingCollapseFinalize != nil)")
        pendingBackingResize?.cancel()
        pendingBackingResize = nil
        cancelHoverReveal()
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
    }
}
