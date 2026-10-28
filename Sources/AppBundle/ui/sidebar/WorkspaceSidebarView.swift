import AppKit
import Common
import SwiftUI

struct WorkspaceSidebarView: View {
    @Environment(\.colorSchemeContrast) var sidebarContrast
    @Environment(\.workspaceSidebarWallpaperSample) private var wallpaperSample
    @Environment(\.workspaceSidebarPreviewAccessibility) var previewAccessibility
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.colorScheme) var colorScheme
    var solidColorScheme: ColorScheme {
        workspaceSidebarSolidColorScheme(snapshot.configuration.resolvedSolidChromeColor)
    }
    var sidebarColors: WorkspaceSidebarPalette {
        WorkspaceSidebarPalette(appearance: snapshot.configuration.appearance, increasedContrast: sidebarContrast == .increased || previewAccessibility.increasedContrast, colorScheme: snapshot.configuration.appearance == .custom ? solidColorScheme : snapshot.configuration.theme.colorScheme(system: colorScheme))
    }
    let snapshot: WorkspaceSidebarSnapshot
    let actions: WorkspaceSidebarActions
    @State var projectSwipeTranslation: CGFloat = 0
    @State var projectSwipeStartProjectId: WorkspaceProjectId? = nil
    @State var projectSwipeDidCrossBreakPoint = false
    @State var projectPagerWidth: CGFloat = 0
    @State var browseMode: WorkspaceSidebarBrowseMode = .activeProject
    @State var activeInUseOverrideWorkspaceName: String? = nil
    @State var isProjectMenuOpen = false
    @State var isSidebarCollapsing = false
    @State var isSidebarExpanding = false
    @State var renamingProjectId: WorkspaceProjectId? = nil
    @State var renamingProjectText = ""
    @State var renamingWorkspaceName: String? = nil
    @State var renamingWorkspaceText = ""
    @State var searchText = ""
    @State var isSearchEditing = false
    @State var searchUsesNativeEditor = false
    @State var searchEditingPanel: WorkspaceSidebarPanel? = nil
    @State var selectedSearchTarget: WorkspaceSidebarSearchSelection? = nil
    @State var lastProjectEdgeDragDirection: Int? = nil
    @State var lastProjectEdgeDragSwitchAt: Date = .distantPast
    @State var showsPinnedActiveWorkspaceForBrowsedProject = true

    init(snapshot: WorkspaceSidebarSnapshot, actions: WorkspaceSidebarActions = WorkspaceSidebarActions()) {
        self.snapshot = snapshot
        self.actions = actions
    }

    var sidebarAlignment: Alignment { snapshot.configuration.position == .left ? .leading : .trailing }

    var overrideConfirmationState: WorkspaceSidebarOverrideConfirmationState {
        workspaceSidebarOverrideConfirmationState(
            snapshot: snapshot, browseMode: browseMode, query: searchText,
            requestedWorkspaceName: activeInUseOverrideWorkspaceName
        )
    }

    private func synchronizeOverrideConfirmation(_ state: WorkspaceSidebarOverrideConfirmationState) {
        if activeInUseOverrideWorkspaceName != state.workspaceName {
            activeInUseOverrideWorkspaceName = state.workspaceName
        }
        guard let panel = WorkspaceSidebarPanel.panel(for: snapshot.targetMonitorScopeId) else { return }
        panel.overrideConfirmationLocksCollapse = state.locksCollapse
        if state.locksCollapse {
            panel.cancelExpansionWork()
        } else {
            panel.scheduleHoverRecheckSoon()
        }
    }

    var body: some View {
        let collapsedWidth = snapshot.configuration.collapsedWidth
        let expandedWidth = snapshot.configuration.expandedWidth
        let expansionProgress = max(
            0,
            min(1, (snapshot.visibleWidth - collapsedWidth) / max(expandedWidth - collapsedWidth, 1)),
        )
        
        ZStack(alignment: sidebarAlignment) {
            sidebarContent(expansionProgress: expansionProgress)
                .frame(width: max(snapshot.visibleWidth, 0), alignment: .leading)
                .mask(alignment: sidebarAlignment) {
                    Rectangle()
                        .frame(width: max(snapshot.visibleWidth, 0))
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sidebarAlignment)
        .background(Color.clear)
        .background(WorkspaceSidebarMaterialGeometry(configuration: snapshot.configuration, wallpaperTone: wallpaperSample?.tone, contentColorScheme: colorScheme, visibleWidth: snapshot.visibleWidth)
            .allowsHitTesting(false))
        .overlay {
            if snapshot.configuration.heightMode == .centered {
                centeredContentMeasurement
            }
        }
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .environment(\.workspaceSidebarAppearance, snapshot.configuration.appearance)
        .modifier(WorkspaceSidebarColorScheme(appearance: snapshot.configuration.appearance, solidColorScheme: solidColorScheme, theme: snapshot.configuration.theme))
        .onChange(of: snapshot.visibleWidth) { visibleWidth in
            if visibleWidth <= collapsedWidth + 0.5 {
                resetTransientSidebarState()
                finishSidebarSearch(clearText: true)
            } else if visibleWidth >= collapsedWidth + 8 {
                isSidebarCollapsing = false
            }
            if visibleWidth >= expandedWidth - 0.5 {
                isSidebarExpanding = false
                beginSidebarSearchIfNeeded()
            }
        }
        .onChange(of: snapshot.activeProjectId) { projectId in
            debugWorkspaceSidebarProjectLog(
                "snapshotActiveProjectChanged active=\(projectId.rawValue) visibleWidth=\(snapshot.visibleWidth) projects=\(snapshot.projects.map(\.id.rawValue))"
            )
            browseMode = .activeProject
            showsPinnedActiveWorkspaceForBrowsedProject = true
            activeInUseOverrideWorkspaceName = nil
            finishProjectRename(cancelled: true)
            finishSidebarSearch(clearText: true)
            resetProjectSwipeWithoutAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            guard let panel = notification.object as? WorkspaceSidebarPanel,
                  panel.monitorScopeId == snapshot.targetMonitorScopeId else { return }
            activeInUseOverrideWorkspaceName = nil
        }
        .onChange(of: selectedSearchTarget) { target in
            if let name = activeInUseOverrideWorkspaceName, target != .workspace(name) {
                activeInUseOverrideWorkspaceName = nil
            }
        }
        .onChange(of: searchText) { _ in
            selectFirstSearchTarget()
        }
        .onChange(of: overrideConfirmationState) { state in
            synchronizeOverrideConfirmation(state)
        }
        .onAppear {
            synchronizeOverrideConfirmation(overrideConfirmationState)
        }
        .onDisappear {
            WorkspaceSidebarPanel.panel(for: snapshot.targetMonitorScopeId)?.overrideConfirmationLocksCollapse = false
        }
        .onChange(of: browseMode) { mode in
            guard snapshot.visibleWidth > collapsedWidth + 0.5,
                  let panel = WorkspaceSidebarPanel.panel(for: snapshot.targetMonitorScopeId)
            else { return }
            let targetWidth = mode.isSplit ? expandedWidth * 2 : expandedWidth
            debugWorkspaceSidebarHoverLog("browseProjectWidthChange panel=\(snapshot.targetMonitorScopeId) project=\(mode.otherProjectId?.rawValue ?? "nil") snapshotWidth=\(snapshot.visibleWidth) target=\(targetWidth) frame=\(panel.frame) mouse=\(NSEvent.mouseLocation)")
            panel.cancelExpansionWork()
            panel.viewModel.isWorkspaceSidebarExpanded = true
            panel.splitBrowseCollapseSuppressedUntil = mode.isSplit ? Date().addingTimeInterval(0.65) : .distantPast
            isSidebarCollapsing = false
            isSidebarExpanding = false
            panel.animateVisibleSidebarWidth(targetWidth, animation: .easeInOut(duration: panel.animationDuration))
        }
        .onChange(of: snapshot.projects) { _ in
            if let browsedProjectId, !snapshot.projects.contains(where: { $0.id == browsedProjectId }) {
                browseMode = .activeProject
            }
            if let renamingProjectId, !snapshot.projects.contains(where: { $0.id == renamingProjectId }) {
                finishProjectRename(cancelled: true)
            }
            if let renamingWorkspaceName, !snapshot.workspaces.contains(where: { $0.name == renamingWorkspaceName }) {
                finishWorkspaceRename(cancelled: true)
            }
            isProjectMenuOpen = false
            resetProjectSwipeWithoutAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarWillCollapseNotification)) { notification in
            guard notificationPanel(from: notification)?.monitorScopeId == snapshot.targetMonitorScopeId else { return }
            guard snapshot.visibleWidth > collapsedWidth + 0.5 else {
                isSidebarCollapsing = false
                return
            }
            finishSidebarSearch(clearText: true)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.08)) {
                isProjectMenuOpen = false
                isSidebarCollapsing = true
                isSidebarExpanding = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarWillExpandNotification)) { notification in
            guard notificationPanel(from: notification)?.monitorScopeId == snapshot.targetMonitorScopeId else { return }
            isSidebarCollapsing = false
            isSidebarExpanding = true
            let panel = notificationPanel(from: notification)
            let generation = panel?.hoverRevealGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                guard let panel, !panel.isRetired, panel.viewModel.isWorkspaceSidebarExpanded,
                      panel.hoverRevealGeneration == generation else { return }
                beginSidebarSearchIfNeeded(panel: panel)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarCommandSearchKeyNotification)) { notification in
            guard let panel = notificationPanel(from: notification),
                  panel.monitorScopeId == snapshot.targetMonitorScopeId
            else { return }
            adoptCommandSidebarSearchIfNeeded(panel: panel)
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarDismissProjectMenusNotification)) { _ in
            if isProjectMenuOpen {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.10)) {
                    isProjectMenuOpen = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarDragPointerChangedNotification)) { notification in
            guard let pointer = workspaceSidebarDragPointer(from: notification) else { return }
            handleProjectEdgeDrag(pointer: pointer, expansionProgress: expansionProgress)
        }
        .onReceive(NotificationCenter.default.publisher(for: workspaceSidebarDragPointerEndedNotification)) { _ in
            resetProjectEdgeDrag()
        }
    }

}

extension WorkspaceSidebarView {
    var browsedProjectId: WorkspaceProjectId? {
        browseMode.otherProjectId
    }
}

private func workspaceSidebarDragPointer(from notification: Notification) -> CGPoint? {
    (notification.userInfo?[workspaceSidebarDragPointerUserInfoKey] as? NSValue)?.pointValue
}

private func notificationPanel(from notification: Notification) -> WorkspaceSidebarPanel? {
    notification.object as? WorkspaceSidebarPanel
}

struct WorkspaceSidebarContainerView: View {
    @ObservedObject var viewModel: TrayMenuModel
    let actions: WorkspaceSidebarActions

    var body: some View {
        let snapshot = workspaceSidebarSnapshot(from: viewModel)
        Group {
            if viewModel.workspaceSidebarContentLoaded {
                WorkspaceSidebarView(
                    snapshot: snapshot,
                    actions: actions
                )
            } else {
                Color.clear
            }
        }
        .modifier(WorkspaceSidebarWallpaperContrast(
            snapshot: snapshot,
            refreshGeneration: viewModel.workspaceSidebarWallpaperRefreshGeneration
        ))
    }
}
extension WorkspaceSidebarView {
    @ViewBuilder
    func projectPageSlot(
        index: Int,
        project: WorkspaceSidebarProjectViewModel,
        displayIndex: Int,
        pageWidth: CGFloat,
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        visibleWorkspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
        swipeDirection: Int?,
    ) -> some View {
        if shouldRenderWorkspaceSidebarProjectPage(
            index: index,
            displayIndex: displayIndex,
            swipeDirection: swipeDirection,
            projectCount: snapshot.projects.count,
        ) {
            workspacePage(
                projectId: project.id,
                workspaces: visibleWorkspacesByProject[project.id] ?? [],
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: trailingInset,
                topPadding: topPadding,
                isInteractive: index == displayIndex,
                showsPinnedActiveWorkspace: showsPinnedActiveWorkspaceForBrowsedProject,
                showsCreateWorkspace: browsedProjectId == nil,
                allowsActivation: allowsWorkspaceActivation(projectId: project.id),
            )
                    .frame(width: pageWidth, alignment: .topLeading)
                    .allowsHitTesting(index == displayIndex)
        } else {
            Color.clear
                .frame(width: pageWidth, alignment: .topLeading)
                .allowsHitTesting(false)
        }
    }

    func workspacePage(
        projectId: WorkspaceProjectId,
        workspaces: [WorkspaceSidebarWorkspaceViewModel],
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        isInteractive: Bool,
        showsPinnedActiveWorkspace: Bool = true,
        showsCreateWorkspace: Bool = true,
        allowsActivation: Bool? = nil,
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                workspacePageContent(projectId: projectId, workspaces: workspaces, expansionProgress: expansionProgress,
                                 leadingInset: leadingInset, trailingInset: trailingInset, topPadding: topPadding,
                                 showsPinnedActiveWorkspace: showsPinnedActiveWorkspace, showsCreateWorkspace: showsCreateWorkspace,
                                 allowsActivation: allowsActivation)
            }
            .onChange(of: selectedSearchTarget) { target in
                guard isInteractive, let target,
                    workspaceSidebarSearchSelections(workspaces: workspaces, includeWorkspaceHeaders: true).contains(target) else { return }
                proxy.scrollTo(target, anchor: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func workspacePageContent(
        projectId: WorkspaceProjectId, workspaces: [WorkspaceSidebarWorkspaceViewModel], expansionProgress: CGFloat,
        leadingInset: CGFloat, trailingInset: CGFloat, topPadding: CGFloat,
        showsPinnedActiveWorkspace: Bool = true, showsCreateWorkspace: Bool = true,
        allowsActivation: Bool? = nil, measuring: Bool = false
    ) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                let pinned = showsPinnedActiveWorkspace
                    ? pinnedActiveWorkspace(
                    displayedProjectId: projectId,
                    pageWorkspaces: workspaces
                )
                    : nil
                if let pinned {
                    workspaceSection(
                        workspace: pinned,
                        expansionProgress: expansionProgress,
                        emitsDropTarget: !measuring,
                        allowsWorkspaceActivation: false,
                        isPinnedActiveWorkspace: true,
                        projectContextLabel: projectName(snapshot.activeProjectId),
                        projectContextColor: projectColor(snapshot.activeProjectId)
                    )
                }
                ForEach(workspaces.filter { $0.id != pinned?.id }) { workspace in
                    workspaceSection(
                        workspace: workspace,
                        expansionProgress: expansionProgress,
                        emitsDropTarget: !measuring,
                        allowsWorkspaceActivation: allowsActivation ?? allowsWorkspaceActivation(projectId: projectId),
                        isPinnedActiveWorkspace: false,
                        projectContextLabel: browsedProjectId != nil && projectId != snapshot.activeProjectId ? projectName(projectId) : nil,
                        projectContextColor: browsedProjectId != nil && projectId != snapshot.activeProjectId ? projectColor(projectId) : nil
                    )
                }
                if showsCreateWorkspace && workspaceSidebarShowsCreateWorkspace(selectedScopeId: snapshot.selectedMonitorScopeId) {
                    let createMonitorScopeId = workspaceSidebarWorkspaceCreateScope(
                        selectedScopeId: snapshot.selectedMonitorScopeId,
                        targetMonitorScopeId: snapshot.targetMonitorScopeId,
                        focusedScopeId: snapshot.focusedMonitorScopeId,
                    )
                    WorkspaceSidebarCreateWorkspaceSection(
                        projectId: projectId,
                        monitorScopeId: createMonitorScopeId,
                        dragPreview: snapshot.dropPreview,
                        expansionProgress: expansionProgress,
                        layout: snapshot.configuration,
                        emitsDropTarget: !measuring,
                        onCreateWorkspace: {
                            actions.send(.createWorkspace(
                                projectId: projectId,
                                monitorScopeId: createMonitorScopeId
                            ))
                        },
                        onDropPayload: { payload in
                            switch payload {
                                case .window(let windowId):
                                    actions.send(.moveWindowToNewWorkspace(
                                        windowId,
                                        projectId: projectId,
                                        monitorScopeId: createMonitorScopeId,
                                    ))
                                case .tabGroup(let representativeWindowId):
                                    actions.send(.moveTabGroupToNewWorkspace(
                                        representativeWindowId,
                                        projectId: projectId,
                                        monitorScopeId: createMonitorScopeId,
                                    ))
                            }
                        },
                        actions: actions,
                    )
                }
            }
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .padding(.top, topPadding)
            .padding(.bottom, 10)
    }

    func splitWorkspacePage(
        activeProjectId: WorkspaceProjectId,
        browsedProjectId: WorkspaceProjectId,
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
        topPadding: CGFloat,
        visibleWorkspacesByProject: [WorkspaceProjectId: [WorkspaceSidebarWorkspaceViewModel]],
    ) -> some View {
        let sectionWidth = workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration)
        return HStack(alignment: .top, spacing: workspaceSidebarSplitPaneGap) {
            workspacePage(
                projectId: activeProjectId,
                workspaces: visibleWorkspacesByProject[activeProjectId] ?? [],
                expansionProgress: expansionProgress,
                leadingInset: leadingInset,
                trailingInset: 0,
                topPadding: topPadding,
                isInteractive: true,
                showsPinnedActiveWorkspace: false,
                showsCreateWorkspace: true,
                allowsActivation: true,
            )
            .frame(width: sectionWidth + leadingInset, alignment: .topLeading)

            workspacePage(
                projectId: browsedProjectId,
                workspaces: visibleWorkspacesByProject[browsedProjectId] ?? [],
                expansionProgress: expansionProgress,
                leadingInset: 0,
                trailingInset: trailingInset,
                topPadding: topPadding,
                isInteractive: true,
                showsPinnedActiveWorkspace: false,
                showsCreateWorkspace: true,
                allowsActivation: false,
            )
            .frame(width: sectionWidth + trailingInset, alignment: .topLeading)
        }
        .frame(
            width: workspaceSidebarSplitSectionWidth(expansionProgress: expansionProgress) + leadingInset + trailingInset,
            alignment: .topLeading
        )
    }

    @ViewBuilder
    private func workspaceSection(
        workspace: WorkspaceSidebarWorkspaceViewModel,
        expansionProgress: CGFloat,
        emitsDropTarget: Bool,
        allowsWorkspaceActivation: Bool,
        isPinnedActiveWorkspace: Bool,
        projectContextLabel: String? = nil,
        projectContextColor: Color? = nil
    ) -> some View {
        let isFromOtherDisplay = false
        let isInUseOnOtherDisplay = allowsWorkspaceActivation &&
            !isPinnedActiveWorkspace &&
            workspaceSidebarWorkspaceIsOnOtherDisplay(
                workspace,
                selectedScopeId: snapshot.targetMonitorScopeId
            )
        WorkspaceSidebarWorkspaceSection(
            workspace: workspace,
            dragPreview: snapshot.dropPreview,
            expansionProgress: expansionProgress,
            layout: snapshot.configuration,
            emitsDropTarget: emitsDropTarget,
            isFromOtherDisplay: isFromOtherDisplay,
            isInUseOnOtherDisplay: isInUseOnOtherDisplay,
            isOnFocusedMonitor: workspace.monitorScopeId == snapshot.focusedMonitorScopeId,
            allowsWorkspaceActivation: allowsWorkspaceActivation,
            isPinnedActiveWorkspace: isPinnedActiveWorkspace,
            isActiveOnTargetMonitor: workspace.monitorScopeId == snapshot.targetMonitorScopeId && workspace.isVisible,
            projectContextLabel: projectContextLabel,
            projectContextColor: projectContextColor,
            renamingWorkspaceName: $renamingWorkspaceName,
            renamingWorkspaceText: $renamingWorkspaceText,
            onBeginRenameWorkspace: {
                beginWorkspaceRename(workspace)
            },
            onCommitRenameWorkspace: {
                finishWorkspaceRename()
            },
            onCancelRenameWorkspace: {
                finishWorkspaceRename(cancelled: true)
            },
            selectedSearchTarget: isSearchEditing ? selectedSearchTarget : nil,
            isSearchFiltering: !searchText.isEmpty,
            activeInUseOverrideWorkspaceName: $activeInUseOverrideWorkspaceName,
            actions: actions,
        )
    }

    func allowsWorkspaceActivation(projectId: WorkspaceProjectId) -> Bool {
        snapshot.selectedMonitorScopeId == workspaceSidebarDefaultScopeId &&
            browsedProjectId == nil &&
            projectId == snapshot.activeProjectId
    }

    private func projectColorHex(_ projectId: WorkspaceProjectId) -> String? {
        snapshot.projects.first { $0.id == projectId }?.colorHex
    }

    private func projectName(_ projectId: WorkspaceProjectId) -> String {
        snapshot.projects.first { $0.id == projectId }?.displayName ?? "Project"
    }

    private func projectColor(_ projectId: WorkspaceProjectId) -> Color {
        workspaceSidebarProjectColor(projectId: projectId, configuredHex: projectColorHex(projectId))
    }

    private func pinnedActiveWorkspace(
        displayedProjectId: WorkspaceProjectId,
        pageWorkspaces: [WorkspaceSidebarWorkspaceViewModel]
    ) -> WorkspaceSidebarWorkspaceViewModel? {
        guard browsedProjectId != nil,
              displayedProjectId != snapshot.activeProjectId,
              !pageWorkspaces.contains(where: { workspaceIsActiveOnTargetMonitor($0) }),
              let focusedWorkspace = snapshot.workspaces.first(where: { workspaceIsActiveOnTargetMonitor($0) }),
              workspaceSidebarWorkspaceMatchesScope(
                focusedWorkspace,
                selectedScopeId: snapshot.selectedMonitorScopeId,
                focusedMonitorScopeId: snapshot.focusedMonitorScopeId
              )
        else {
            return nil
        }
        return focusedWorkspace
    }

    private func workspaceIsActiveOnTargetMonitor(_ workspace: WorkspaceSidebarWorkspaceViewModel) -> Bool {
        workspace.isVisible && workspace.monitorScopeId == snapshot.targetMonitorScopeId
    }
}
