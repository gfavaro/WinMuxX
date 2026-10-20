import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarView {
    @ViewBuilder
    func projectPagerContent(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        visibleWorkspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
        swipeDirection: Int?,
    ) -> some View {
        if let browsedProjectId,
           browsedProjectId != snapshot.activeProjectId
        {
            splitWorkspacePage(
                activeProjectId: snapshot.activeProjectId,
                browsedProjectId: browsedProjectId,
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                visibleWorkspacesByProject: visibleWorkspacesByProject
            )
        } else if snapshot.projects.isEmpty {
            workspacePage(
                projectId: snapshot.activeProjectId,
                workspaces: visibleWorkspacesByProject[snapshot.activeProjectId] ?? [],
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                isInteractive: true,
                showsPinnedActiveWorkspace: true,
                showsCreateWorkspace: true,
                allowsActivation: allowsWorkspaceActivation(projectId: snapshot.activeProjectId),
            )
        } else {
            projectPagerPages(
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                visibleWorkspacesByProject: visibleWorkspacesByProject,
                swipeDirection: swipeDirection,
            )
        }
    }

    func projectPagerPages(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        visibleWorkspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
        swipeDirection: Int?,
    ) -> some View {
        GeometryReader { geometry in
            let pageWidth = max(geometry.size.width, 1)
            let displayIndex = projectPagerDisplayIndex ?? 0
            let dragOffset = workspaceSidebarProjectPagerDragOffset(
                horizontalTranslation: projectSwipeTranslation,
                currentIndex: displayIndex,
                projectCount: snapshot.projects.count,
                pageWidth: pageWidth,
            )

            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(snapshot.projects.enumerated()), id: \.element.id) { index, project in
                    projectPageSlot(
                        index: index,
                        project: project,
                        displayIndex: displayIndex,
                        pageWidth: pageWidth,
                        expansionProgress: expansionProgress,
                        leadingInset: leadingInset,
                        trailingInset: trailingInset,
                        topPadding: topPadding,
                        visibleWorkspacesByProject: visibleWorkspacesByProject,
                        swipeDirection: swipeDirection,
                    )
                }
            }
            .offset(x: -CGFloat(displayIndex) * pageWidth + dragOffset)
            .onAppear { projectPagerWidth = pageWidth }
            .onChange(of: pageWidth) { projectPagerWidth = $0 }
        }
        .clipped()
    }
}
extension WorkspaceSidebarView {
    func projectPagerSection(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        swipeDirection: Int?,
        switchProgress: CGFloat,
        measuring: Bool = false,
    ) -> some View {
        WorkspaceSidebarProjectPager(
            projects: snapshot.projects,
            selectedProjectId: snapshot.activeProjectId,
            expansionProgress: expansionProgress,
            layout: snapshot.configuration,
            isProjectMenuOpen: $isProjectMenuOpen,
            renamingProjectId: $renamingProjectId,
            renamingProjectText: $renamingProjectText,
            onSelectProject: { projectId in
                debugWorkspaceSidebarProjectLog(
                    "pagerSectionSelect project=\(projectId.rawValue) active=\(snapshot.activeProjectId.rawValue) browsed=\(browsedProjectId?.rawValue ?? "nil")"
                )
                browseMode = .activeProject
                actions.send(.selectProject(projectId))
            },
            onCreateProject: { actions.send(.createProject) },
            onBeginRenameProject: { project in
                beginProjectRename(project)
            },
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
        .zIndex(2)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
extension WorkspaceSidebarView {
    func validProjectSwipeEndDirection(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) -> Int? {
        guard shouldHandleProjectSwipe(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
            expansionProgress: expansionProgress,
        ) else {
            return nil
        }
        return workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
        )
    }

    func finishProjectSwipeNavigation(to projectId: WorkspaceProjectId, direction: Int) {
        let startProjectId = projectSwipeStartProjectId
        let fullPageOffset = -CGFloat(direction) * max(projectPagerWidth, snapshot.configuration.expandedWidth, 1)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
            projectSwipeTranslation = fullPageOffset
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard projectSwipeStartProjectId == startProjectId else { return }
            actions.send(.selectProject(projectId))
            resetProjectSwipeWithoutAnimation()
        }
    }


}
extension WorkspaceSidebarView {
    func handleProjectSwipeEnded(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) {
        guard let direction = validProjectSwipeEndDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
            expansionProgress: expansionProgress,
        ) else {
            finishProjectSwipeSnapBack()
            return
        }
        if projectSwipeStartProjectId == nil,
           let selectedProjectIndex {
            projectSwipeStartProjectId = snapshot.projects[selectedProjectIndex].id
        }
        finishProjectSwipeNavigationIfNeeded(direction: direction, distance: abs(horizontalTranslation))
    }

    func finishProjectSwipeSnapBack() {
        withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.18, dampingFraction: 0.9)) {
            resetProjectSwipe()
        }
    }

    func finishProjectSwipeNavigationIfNeeded(direction: Int, distance: CGFloat) {
        guard let nextIndex = workspaceSidebarProjectSwipeTarget(
            currentIndex: projectPagerDisplayIndex,
            projectCount: snapshot.projects.count,
            direction: direction,
            distance: distance
        ) else {
            performWorkspaceSidebarProjectHaptic(.alignment)
            finishProjectSwipeSnapBack()
            return
        }
        finishProjectSwipeNavigation(to: snapshot.projects[nextIndex].id, direction: direction)
    }
}
extension WorkspaceSidebarView {
    var selectedProjectIndex: Int? {
        let projectId = browsedProjectId ?? snapshot.activeProjectId
        return snapshot.projects.firstIndex { $0.id == projectId }
            ?? snapshot.projects.indices.first
    }

    var projectPagerDisplayIndex: Int? {
        if let projectSwipeStartProjectId,
           let index = snapshot.projects.firstIndex(where: { $0.id == projectSwipeStartProjectId }) {
            return index
        }
        return selectedProjectIndex
    }

    func resetProjectSwipe() {
        projectSwipeTranslation = 0
        projectSwipeStartProjectId = nil
        projectSwipeDidCrossBreakPoint = false
    }

    func resetProjectSwipeWithoutAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            resetProjectSwipe()
        }
    }

    func resetTransientSidebarState() {
        browseMode = .activeProject
        showsPinnedActiveWorkspaceForBrowsedProject = true
        activeInUseOverrideWorkspaceName = nil
        isProjectMenuOpen = false
        isSidebarCollapsing = false
        isSidebarExpanding = false
        finishWorkspaceRename(cancelled: true)
        resetProjectEdgeDrag()
        resetProjectSwipeWithoutAnimation()
    }

    func performWorkspaceSidebarProjectHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    func handleProjectEdgeDrag(pointer: CGPoint, expansionProgress: CGFloat) {
        resetProjectEdgeDrag()
    }

    func resetProjectEdgeDrag() {
        lastProjectEdgeDragDirection = nil
        lastProjectEdgeDragSwitchAt = .distantPast
    }

}
