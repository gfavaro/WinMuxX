import AppKit

extension Monitor {
    @MainActor
    var workspaceSidebarInset: CGFloat {
        guard config.workspaceSidebar.enabled else { return 0 }
        return workspaceSidebarResolvedPanelMonitors().contains { $0.rect.topLeftCorner == rect.topLeftCorner }
            ? workspaceSidebarRestingWidth(config.workspaceSidebar)
            : 0
    }

    /// The edge of the area the workspace sidebar keeps for itself, if it keeps one.
    @MainActor
    var workspaceSidebarEdge: WorkspaceSidebarEdge? {
        guard workspaceSidebarInset > 0 else { return nil }
        return config.workspaceSidebar.position == .right
            ? .right(visibleRect.maxX - workspaceSidebarInset)
            : .left(visibleRect.minX + workspaceSidebarInset)
    }

    @MainActor
    var visibleRectPaddedByOuterGaps: Rect {
        let topLeft = visibleRect.topLeftCorner
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: self)
        let leftInset = gaps.outer.left.toDouble() + (config.workspaceSidebar.position == .left ? workspaceSidebarInset : 0)
        let rightInset = gaps.outer.right.toDouble() + (config.workspaceSidebar.position == .right ? workspaceSidebarInset : 0)
        return Rect(
            topLeftX: topLeft.x + leftInset,
            topLeftY: topLeft.y + gaps.outer.top.toDouble(),
            width: visibleRect.width - leftInset - rightInset,
            height: visibleRect.height - gaps.outer.top.toDouble() - gaps.outer.bottom.toDouble(),
        )
    }

    @MainActor
    var monitorId_oneBased: Int? {
        sortedMonitors.firstIndex { $0.rect.topLeftCorner == rect.topLeftCorner }.map { $0 + 1 }
    }
}

enum WorkspaceSidebarEdge: Equatable {
    case left(CGFloat), right(CGFloat)

    /// Whether all of `rect` that is on the display lies under the sidebar.
    func covers(_ rect: Rect) -> Bool {
        switch self {
            case .left(let edge): rect.maxX <= edge + 1
            case .right(let edge): rect.minX >= edge - 1
        }
    }
}
