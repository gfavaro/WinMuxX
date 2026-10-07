import AppKit
import Common
import CoreGraphics
import SwiftUI

extension WorkspaceSidebarPanel {
    func animateVisibleSidebarWidth(_ width: CGFloat, animation: Animation) {
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
        debugWorkspaceSidebarHoverLog("expandSidebar panel=\(monitorScopeId) target=\(expandedWidth) visible=\(viewModel.workspaceSidebarVisibleWidth) frame=\(frame) mouse=\(NSEvent.mouseLocation)")
        pendingExpand?.cancel()
        pendingExpand = nil
        NotificationCenter.default.post(name: workspaceSidebarWillExpandNotification, object: self)
        viewModel.isWorkspaceSidebarExpanded = true
        if !isVisible {
            refresh()
        }
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
        pendingExpand?.cancel()
        pendingExpand = nil
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
    }
}
