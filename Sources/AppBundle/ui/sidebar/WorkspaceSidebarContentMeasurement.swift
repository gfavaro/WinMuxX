import SwiftUI

private struct WorkspaceSidebarNaturalHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension WorkspaceSidebarView {
    /// Independent of panel height and hover width, so resizing cannot feed back into measurement.
    var centeredContentMeasurement: some View {
        let groups = workspaceSidebarVisibleWorkspacesByProject(
            workspaces: snapshot.workspaces, selectedScopeId: snapshot.selectedMonitorScopeId,
            focusedMonitorScopeId: snapshot.focusedMonitorScopeId, browsedProjectId: browsedProjectId
        )
        let projectIds = [snapshot.activeProjectId] + (browsedProjectId.map { [$0] } ?? [])
        return ZStack {
            ForEach(projectIds, id: \.self) { projectId in
                ForEach([CGFloat(0), CGFloat(1)], id: \.self) { progress in
                    let compact = progress == 0
                    let inset = workspaceSidebarOuterLeadingPadding(isCompact: compact)
                    VStack(spacing: 0) {
                        if !compact && shouldShowTopFilterBar {
                            monitorSelectorSection(expansionProgress: progress, leadingInset: inset, trailingInset: inset)
                        }
                        workspacePageContent(
                            projectId: projectId, workspaces: groups[projectId] ?? [], expansionProgress: progress,
                            leadingInset: inset, trailingInset: inset,
                            topPadding: !compact && shouldShowTopFilterBar ? 0 : snapshot.configuration.topPadding,
                            measuring: true
                        )
                        projectPagerSection(expansionProgress: progress, leadingInset: inset, trailingInset: inset,
                                            swipeDirection: nil, switchProgress: 0, edgeProgress: 0)
                        if snapshot.configuration.showsClock {
                            statusSection(expansionProgress: progress, isCompact: compact, leadingInset: inset, trailingInset: inset)
                        }
                        Color.clear.frame(height: workspaceSidebarFooterBottomPadding(showsClock: snapshot.configuration.showsClock))
                    }
                    .frame(width: compact ? snapshot.configuration.collapsedWidth : snapshot.configuration.expandedWidth)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: WorkspaceSidebarNaturalHeightKey.self, value: proxy.size.height)
                    })
                }
            }
        }
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onPreferenceChange(WorkspaceSidebarNaturalHeightKey.self) { height in
            WorkspaceSidebarPanel.panel(for: snapshot.targetMonitorScopeId)?.updateMeasuredContentHeight(height)
        }
    }
}
