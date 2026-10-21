import AppKit

func workspaceSidebarAllowsLeftEdgeTrap(_ sidebarConfig: WorkspaceSidebarConfig) -> Bool {
    !sidebarConfig.alwaysExpanded
}

func workspaceSidebarRestingWidth(_ sidebarConfig: WorkspaceSidebarConfig) -> CGFloat {
    if sidebarConfig.alwaysExpanded {
        return CGFloat(sidebarConfig.width)
    }
    return sidebarConfig.autoHide ? 0 : CGFloat(sidebarConfig.collapsedWidth)
}

func workspaceSidebarHoverActivationWidth(_ sidebarConfig: WorkspaceSidebarConfig) -> CGFloat {
    if sidebarConfig.alwaysExpanded { return CGFloat(sidebarConfig.width) }
    return sidebarConfig.autoHide ? 2 : CGFloat(sidebarConfig.collapsedWidth)
}

/// Exit tolerance keeps an open sidebar usable; it must not enlarge the hidden
/// opening target or let a collapsed animation reopen over application content.
func workspaceSidebarHoverRegionWidth(
    _ sidebarConfig: WorkspaceSidebarConfig, visibleWidth: CGFloat, isExpanded: Bool
) -> CGFloat {
    let activationWidth = workspaceSidebarHoverActivationWidth(sidebarConfig)
    let hasRevealedContent = visibleWidth > workspaceSidebarRestingWidth(sidebarConfig) + 0.5 ||
        (isExpanded && visibleWidth > 0)
    return hasRevealedContent ? max(visibleWidth, activationWidth) + 20 : activationWidth
}

func workspaceSidebarCollapsedContentWidth(_ sidebarConfig: WorkspaceSidebarConfig) -> CGFloat {
    sidebarConfig.autoHide && !sidebarConfig.alwaysExpanded ? 0 : CGFloat(sidebarConfig.collapsedWidth)
}

func workspaceSidebarPersistentVisibleWidth(
    currentWidth: CGFloat,
    previousExpandedWidth: CGFloat?,
    expandedWidth: CGFloat,
) -> CGFloat {
    let wasShowingSplitBrowse = previousExpandedWidth.map { currentWidth > $0 + 0.5 } ?? false
    return wasShowingSplitBrowse ? expandedWidth * 2 : expandedWidth
}

func isWorkspaceSidebarHoverDeepEnoughToExpand(
    mouseX: CGFloat,
    sidebarMinX: CGFloat,
    collapsedWidth: CGFloat,
    autoHide: Bool = false,
) -> Bool {
    guard collapsedWidth > 0 else { return false }
    let sidebarMaxX = sidebarMinX + collapsedWidth
    guard mouseX >= sidebarMinX, mouseX < sidebarMaxX else { return false }
    return autoHide || sidebarMaxX - mouseX >= collapsedWidth * workspaceSidebarHoverOpenThresholdFraction
}

func shouldDelayWorkspaceSidebarExpansion(
    isExpanded: Bool,
    isExpansionLocked: Bool,
    isMouseWindowDragInProgress: Bool,
) -> Bool {
    !isExpanded && !isExpansionLocked && !isMouseWindowDragInProgress
}

func shouldSuppressWorkspaceSidebarHoverExpansionForDrag(
    isSidebarItemDragActive: Bool,
    isSidebarOriginatedDrag: Bool,
) -> Bool {
    isSidebarItemDragActive || isSidebarOriginatedDrag
}

/// A press begun outside the sidebar may be selecting text or dragging content.
/// Only recognized window/sidebar drags opt into the existing drop interaction.
func shouldSuppressWorkspaceSidebarHoverForPointerPress(
    isExpanded: Bool,
    isLeftMouseButtonDown: Bool,
    pressStartedInsideSidebar: Bool,
    isWindowDrag: Bool,
    isSidebarDrag: Bool,
) -> Bool {
    !isExpanded && isLeftMouseButtonDown && !pressStartedInsideSidebar && !isWindowDrag && !isSidebarDrag
}
