import AppKit
import Common
import CoreGraphics
import SwiftUI

let workspaceSidebarPanelId = "WinMux.workspaceSidebar"
let workspaceSidebarContentLeadingInset: CGFloat = 12
let workspaceSidebarContentTrailingInset: CGFloat = 12
let workspaceSidebarCompactRailHorizontalInset: CGFloat = 7
let workspaceSidebarSectionInnerHorizontalInset: CGFloat = 5
let workspaceSidebarSectionGap: CGFloat = 5
let workspaceSidebarBadgeWidth: CGFloat = 22
let workspaceSidebarHeaderSpacing: CGFloat = 10
let workspaceSidebarHeaderRowLeadingPadding: CGFloat = 6
let workspaceSidebarRowsRevealProgress: CGFloat = 0.58
let workspaceSidebarPanelRightCornerRadius: CGFloat = RadiusToken.panel
let workspaceSidebarPlateCornerRadius: CGFloat = RadiusToken.section
let workspaceSidebarSectionCornerRadius: CGFloat = workspaceSidebarPlateCornerRadius
let workspaceSidebarRowCornerRadius: CGFloat = RadiusToken.row
let workspaceSidebarRowHorizontalPadding: CGFloat = 4
let workspaceSidebarWindowRowsLeadingIndent: CGFloat = 8
let workspaceSidebarAppIconSize: CGFloat = 14
let workspaceSidebarAppIconTextSpacing: CGFloat = 6
let workspaceSidebarTabGroupChildLeadingIndent: CGFloat = workspaceSidebarAppIconSize + workspaceSidebarAppIconTextSpacing - 2
let workspaceSidebarControlHeight: CGFloat = 30
let workspaceSidebarDropdownHeight: CGFloat = 28
let workspaceSidebarSearchHeight: CGFloat = 28
let workspaceSidebarDropdownCornerRadius: CGFloat = RadiusToken.card
let workspaceSidebarDropdownPadding: CGFloat = 7
let workspaceSidebarDropdownLabelSize: CGFloat = 11.5
let workspaceSidebarDropdownSymbolSize: CGFloat = 10.5
let workspaceSidebarPagerHeight: CGFloat = 32
let workspaceSidebarWorkspaceSectionHeaderHeight: CGFloat = 32
let workspaceSidebarWorkspaceRowHeight: CGFloat = 24
let workspaceSidebarWorkspaceSectionHeightCompact: CGFloat = 32
let workspaceSidebarWorkspaceSectionHeightExpanded: CGFloat = 32
let workspaceSidebarInUseOverrideEmptySectionMinHeight: CGFloat = 76
let workspaceSidebarProjectDotFrameHeight: CGFloat = 32
let workspaceSidebarMenuRowHeight: CGFloat = 28
let workspaceSidebarMenuRowSpacing: CGFloat = 3
let workspaceSidebarMenuRowHorizontalPadding: CGFloat = 10
let workspaceSidebarHoverAnimation: Animation = MotionToken.hover
let workspaceSidebarReducedMotionHoverAnimation: Animation? = nil
let workspaceSidebarProjectSwipeIntentThreshold: CGFloat = 5
let workspaceSidebarProjectSwipeNavigateThreshold: CGFloat = 44
let workspaceSidebarHoverOpenThresholdFraction: CGFloat = 0.75
let workspaceSidebarDisplayEdgeCompactionMargin: CGFloat = 12
