import SwiftUI

struct WorkspaceSidebarCompactMetrics {
    let width: CGFloat

    var scale: CGFloat { min(max(width / 44, 0.75), 1.3) }
    var sectionWidth: CGFloat { max(0, width - workspaceSidebarCompactRailHorizontalInset * 2) }
    var badgeSize: CGFloat { min(workspaceSidebarBadgeWidth * scale, max(0, sectionWidth - 4)) }
    var fontSize: CGFloat { 18 * scale }
    var headerHeight: CGFloat { workspaceSidebarWorkspaceSectionHeaderHeight * scale }
    var innerInset: CGFloat { min(workspaceSidebarSectionInnerHorizontalInset, max(0, (sectionWidth - badgeSize) / 2)) }
}

@MainActor
func workspaceSidebarCompactSectionWidth(layout: WorkspaceSidebarConfiguration) -> CGFloat {
    WorkspaceSidebarCompactMetrics(width: layout.collapsedWidth).sectionWidth
}

@MainActor
func workspaceSidebarExpandedSectionWidth(layout: WorkspaceSidebarConfiguration) -> CGFloat {
    max(
        layout.expandedWidth -
            workspaceSidebarContentLeadingInset -
            workspaceSidebarContentTrailingInset,
        workspaceSidebarCompactSectionWidth(layout: layout),
    )
}

@MainActor
func workspaceSidebarSectionWidth(_ expansionProgress: CGFloat, layout: WorkspaceSidebarConfiguration) -> CGFloat {
    let compact = workspaceSidebarCompactSectionWidth(layout: layout)
    let expanded = workspaceSidebarExpandedSectionWidth(layout: layout)
    return compact + (expanded - compact) * expansionProgress
}

@MainActor
func workspaceSidebarContentWidth(_ expansionProgress: CGFloat, layout: WorkspaceSidebarConfiguration) -> CGFloat {
    max(
        workspaceSidebarSectionWidth(expansionProgress, layout: layout) -
            (workspaceSidebarSectionInnerHorizontalInset * 2) -
            workspaceSidebarBadgeWidth -
            workspaceSidebarHeaderSpacing,
        0,
    )
}
