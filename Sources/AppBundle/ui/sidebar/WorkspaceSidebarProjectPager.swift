import AppKit
import Common
import SwiftUI

struct WorkspaceSidebarProjectPager: View {
    @SidebarColors var sidebarColors: WorkspaceSidebarPalette
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId
    let expansionProgress: CGFloat
    let layout: WorkspaceSidebarConfiguration
    @Binding var isProjectMenuOpen: Bool
    @Binding var renamingProjectId: WorkspaceProjectId?
    @Binding var renamingProjectText: String
    let onSelectProject: (WorkspaceProjectId) -> Void
    let onCreateProject: () -> Void
    let onBeginRenameProject: (WorkspaceSidebarProjectViewModel) -> Void
    let onCommitRenameProject: @MainActor @Sendable () -> Void
    let onCancelRenameProject: @MainActor @Sendable () -> Void
    let onSetProjectColor: (WorkspaceSidebarProjectViewModel, String?) -> Void
    let onDeleteProject: (WorkspaceSidebarProjectViewModel) -> Void
    var measuring = false

    @State var isHovered = false
    @State var hoveredProjectDotId: WorkspaceProjectId? = nil
    @State var projectTrackScrollTargetId: WorkspaceProjectId? = nil
    @State var projectTrackContentMinX: CGFloat = 0
    @State var projectTrackContentWidth: CGFloat = 0
    @State var projectTrackViewportWidth: CGFloat = 0

    var sectionWidth: CGFloat { workspaceSidebarSectionWidth(expansionProgress, layout: layout) }
    var isCompact: Bool { expansionProgress < workspaceSidebarRowsRevealProgress }
    var currentIndex: Int? {
        projects.firstIndex { $0.id == selectedProjectId }
            ?? projects.indices.first
    }
    var selectedProject: WorkspaceSidebarProjectViewModel? {
        return projects.first { $0.id == selectedProjectId }
            ?? projects.first
    }
    var showsProjectIndicator: Bool { projects.count > 1 }
    var expandedProjectControlsHeight: CGFloat {
        showsProjectIndicator ? (workspaceSidebarPagerHeight * 2) + 4 : workspaceSidebarPagerHeight
    }
    var pagerHeight: CGFloat {
        if isCompact, !showsProjectIndicator {
            return 0
        }
        return isCompact ? compactProjectControlsHeight : expandedProjectControlsHeight
    }

    var footerSpacing: CGFloat { isCompact ? 2 : 8 }
    var projectCreateButtonWidth: CGFloat { workspaceSidebarDropdownHeight }
    var projectMenuWidth: CGFloat {
        let selectedProjectName = selectedProject?.displayName ?? "Project"
        let textWidth = (selectedProjectName as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .medium)],
        ).width
        return min(max(ceil(textWidth) + 46, 92), 136)
    }
    var projectTrackWidth: CGFloat {
        if isCompact {
            return max(sectionWidth - 4, 12)
        }
        return max(sectionWidth, 24)
    }
    var compactProjectControlsHeight: CGFloat {
        let contentHeight = CGFloat(projects.count) * workspaceSidebarProjectDotFrameHeight
        let maxVisibleHeight = workspaceSidebarProjectDotFrameHeight * 5
        return min(max(contentHeight, workspaceSidebarPagerHeight), maxVisibleHeight)
    }

    var body: some View {
        if !projects.isEmpty, !isCompact || showsProjectIndicator {
            pagerContent
                .frame(width: sectionWidth, height: pagerHeight, alignment: .bottom)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovered = hovering
                }
                .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.86), value: isHovered)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
        }
    }

    var pagerContent: some View {
        Group {
            if isCompact {
                compactProjectIndicator
            } else {
                projectControls
                .frame(width: sectionWidth, height: pagerHeight, alignment: layout.position == .left ? .bottomTrailing : .bottomLeading)
                .transaction { $0.animation = nil }
            }
        }
        .padding(.horizontal, isCompact ? 2 : 0)
        .frame(width: sectionWidth, height: pagerHeight, alignment: .bottom)
        .contextMenu {
            Button("New Project") {
                onCreateProject()
            }
        }
        .transaction { $0.animation = nil }
    }
}
