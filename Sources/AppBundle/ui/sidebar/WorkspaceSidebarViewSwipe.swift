import AppKit
import Common
import SwiftUI

extension WorkspaceSidebarView {

    func handleProjectSwipeChanged(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) {
        guard shouldHandleProjectSwipe(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
            expansionProgress: expansionProgress,
        ) else {
            resetProjectSwipe()
            return
        }
        if projectSwipeStartProjectId == nil,
           let selectedProjectIndex {
            projectSwipeStartProjectId = snapshot.projects[selectedProjectIndex].id
        }
        projectSwipeTranslation = horizontalTranslation
        guard let direction = workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
        ) else {
            return
        }
        let activeProjectIndex = projectPagerDisplayIndex
        let shouldCommit = workspaceSidebarProjectSwipeTarget(
            currentIndex: activeProjectIndex,
            projectCount: snapshot.projects.count,
            direction: direction,
            distance: abs(horizontalTranslation)
        ) != nil
        if shouldCommit && !projectSwipeDidCrossBreakPoint {
            projectSwipeDidCrossBreakPoint = true
            performWorkspaceSidebarProjectHaptic(.alignment)
        } else if !shouldCommit {
            projectSwipeDidCrossBreakPoint = false
        }
    }

    func shouldHandleProjectSwipe(
        horizontalTranslation: CGFloat,
        verticalTranslation: CGFloat,
        expansionProgress: CGFloat,
    ) -> Bool {
        guard !snapshot.projects.isEmpty,
              !isWorkspaceSidebarDragInProgress()
        else {
            return false
        }
        return workspaceSidebarProjectSwipeDirection(
            horizontalTranslation: horizontalTranslation,
            verticalTranslation: verticalTranslation,
        ) != nil
    }
}
