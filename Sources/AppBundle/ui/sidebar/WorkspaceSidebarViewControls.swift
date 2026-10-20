import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarView {
    func monitorSelectorSection(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        measuring: Bool = false,
    ) -> some View {
        WorkspaceSidebarMonitorSelector(
            scopes: snapshot.monitorScopes,
            projects: snapshot.projects,
            selectedScopeId: snapshot.selectedMonitorScopeId,
            activeProjectId: snapshot.activeProjectId,
            browsedProjectId: browsedProjectId,
            expansionProgress: expansionProgress,
            sectionWidth: workspaceSidebarTopSectionWidth(expansionProgress: expansionProgress),
            onSelectScope: { scopeId in
                if scopeId == workspaceSidebarDefaultScopeId {
                    browseMode = .activeProject
                }
                actions.send(.selectMonitorScope(scopeId))
            },
            onSelectProject: { projectId in
                WorkspaceSidebarPanel.panel(for: snapshot.targetMonitorScopeId)?.cancelExpansionWork()
                browseMode = projectId.map { .split(otherProjectId: $0) } ?? .activeProject
                showsPinnedActiveWorkspaceForBrowsedProject = false
            },
            onRenameProject: { project in
                beginProjectRename(project)
            },
            renamingProjectId: $renamingProjectId,
            renamingProjectText: $renamingProjectText,
            onCommitRenameProject: {
                finishProjectRename()
            },
            onCancelRenameProject: {
                finishProjectRename(cancelled: true)
            },
            onSetProjectColor: { project, colorHex in
                actions.send(.setProjectColor(project.id, colorHex: colorHex))
            },
            onDeleteProject: { project in
                actions.send(.deleteProject(project.id))
            },
            measuring: measuring,
        )
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, snapshot.configuration.topPadding)
        .padding(.bottom, workspaceSidebarSectionGap)
        .zIndex(100)
    }

    func workspaceSidebarTopSectionWidth(expansionProgress: CGFloat) -> CGFloat {
        if browsedProjectId != nil {
            return workspaceSidebarSplitSectionWidth(expansionProgress: expansionProgress)
        }
        return workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration)
    }

    func statusSection(
        expansionProgress: CGFloat,
        isCompact: Bool,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
    ) -> some View {
        WorkspaceSidebarStatusView(
            sectionWidth: workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration),
            isCompact: isCompact,
            showsSeconds: snapshot.configuration.showsSeconds,
            showsDate: snapshot.configuration.showsDate,
            showsWeekday: snapshot.configuration.showsWeekday,
        )
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, 4)
        .padding(.bottom, workspaceSidebarStatusBottomPadding(isCompact: isCompact) + 4)
    }

    func sidebarSearchSection(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
    ) -> some View {
        WorkspaceSidebarSearchField(
            text: $searchText,
            requestsFocus: searchUsesNativeEditor,
            onEditorReady: sidebarSearchEditorReady,
            onCommand: handleSidebarSearchKey
        )
        .frame(width: workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration), height: workspaceSidebarSearchHeight)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.bottom, workspaceSidebarSectionGap)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
