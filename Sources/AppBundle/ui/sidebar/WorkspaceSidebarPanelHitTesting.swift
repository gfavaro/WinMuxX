import AppKit
import Common
import CoreGraphics
import SwiftUI

extension WorkspaceSidebarPanel {
    func updateDropTargets(_ targets: [WorkspaceSidebarDropTargetFrame]) {
        workspaceSidebarDropTargets = convertDropTargets(targets)
    }

    func convertDropTargets(_ targets: [WorkspaceSidebarDropTargetFrame]) -> [WorkspaceSidebarDropTarget] {
        targets.compactMap { target in
            let windowRect = hostingView.convert(target.frame, to: nil)
            let screenRect = convertToScreen(windowRect)
            return WorkspaceSidebarDropTarget(kind: target.kind, rect: screenRect.monitorFrameNormalized())
        }
    }

    func visibleScreenRectNormalized() -> Rect? {
        guard isVisible, viewModel.workspaceSidebarVisibleWidth > 0 else { return nil }
        return workspaceSidebarVisibleFrame(panel: frame, width: viewModel.workspaceSidebarVisibleWidth, position: config.workspaceSidebar.position).monitorFrameNormalized()
    }
}

extension WorkspaceSidebarPanel {
    func updateMousePassthrough() {
        let inside = isMouseInsideVisibleRegion()
        let shouldIgnoreMouseEvents = !inside
        if ignoresMouseEvents != shouldIgnoreMouseEvents {
            debugWorkspaceSidebarHoverLog("mousePassthrough panel=\(monitorScopeId) ignores \(ignoresMouseEvents)->\(shouldIgnoreMouseEvents) insideVisible=\(inside) visibleWidth=\(viewModel.workspaceSidebarVisibleWidth) frame=\(frame) mouse=\(NSEvent.mouseLocation)")
            ignoresMouseEvents = shouldIgnoreMouseEvents
        }
    }

    func isMouseInsideHoverRegion() -> Bool {
        guard isVisible else { return false }
        let hoverWidth = max(
            viewModel.workspaceSidebarVisibleWidth,
            workspaceSidebarHoverActivationWidth(config.workspaceSidebar),
        ) + hoverExitTolerance
        let hoverRegion = workspaceSidebarVisibleFrame(panel: frame, width: hoverWidth, position: config.workspaceSidebar.position)
        let inside = hoverRegion.contains(NSEvent.mouseLocation)
        if viewModel.workspaceSidebarVisibleWidth > workspaceSidebarRestingWidth(config.workspaceSidebar) + 0.5 || pendingCollapse != nil {
            debugWorkspaceSidebarHoverLog("hoverRegion panel=\(monitorScopeId) inside=\(inside) hoverWidth=\(hoverWidth) visibleWidth=\(viewModel.workspaceSidebarVisibleWidth) frame=\(frame) mouse=\(NSEvent.mouseLocation) suppressUntil=\(splitBrowseCollapseSuppressedUntil)")
        }
        return inside
    }

    func isMouseInsideVisibleRegion() -> Bool {
        guard isVisible else { return false }
        let visibleRegion = workspaceSidebarVisibleFrame(panel: frame, width: viewModel.workspaceSidebarVisibleWidth, position: config.workspaceSidebar.position)
        return visibleRegion.contains(NSEvent.mouseLocation)
    }

    func isMouseDeepEnoughToExpand() -> Bool {
        guard isVisible else { return false }
        return isWorkspaceSidebarHoverDeepEnoughToExpand(
            mouseX: config.workspaceSidebar.position == .left ? NSEvent.mouseLocation.x : -NSEvent.mouseLocation.x,
            sidebarMinX: config.workspaceSidebar.position == .left ? frame.minX : -frame.maxX,
            collapsedWidth: workspaceSidebarHoverActivationWidth(config.workspaceSidebar),
        )
    }
}
