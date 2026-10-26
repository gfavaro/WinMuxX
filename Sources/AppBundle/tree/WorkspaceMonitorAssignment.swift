import AppKit
import Common

extension Monitor {
    @MainActor
    var activeWorkspace: Workspace {
        if let existing = runtime.workspaces.visibleWorkspace(for: self) {
            return existing
        }
        rearrangeWorkspacesOnMonitors()
        return self.activeWorkspace
    }

    @MainActor
    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        rect.topLeftCorner.setActiveWorkspace(workspace)
    }
}

// Selection preserves ownership; only explicit moves replace a secondary display's slot.
// Startup/restoration may seed ownership, but never choose the destination for user input.
@MainActor
func workspaceIsAvailableForMonitor(_ workspace: Workspace, monitor: Monitor) -> Bool {
    isValidAssignment(workspace: workspace, screen: monitor.rect.topLeftCorner) &&
        workspaceMonitorForUserActivation(workspace, on: monitor).rect.topLeftCorner == monitor.rect.topLeftCorner
}

/// Existing workspaces keep their display; only unassigned/new slots use the request.
@MainActor
func workspaceMonitorForUserActivation(_ workspace: Workspace, on requested: Monitor) -> Monitor {
    workspace.assignedMonitor ?? requested
}

@MainActor
@discardableResult
func activateWorkspaceForUser(
    _ workspace: Workspace,
    on targetMonitor: Monitor,
) -> Bool {
    // Ordinary selection never relocates an owned workspace, visible or hidden.
    if workspace.isVisible {
        guard workspace.visibleMonitor != nil else { return false }
        let focused = workspace.focusWorkspace()
        if focused { recordUserWorkspaceSelectionForRestoration() }
        return focused
    }
    let monitor = workspaceMonitorForUserActivation(workspace, on: targetMonitor)
    guard isValidAssignment(workspace: workspace, screen: monitor.rect.topLeftCorner) else {
        return false
    }

    guard monitor.setActiveWorkspace(workspace) else { return false }
    WorkspaceMotionDiagnostics.selected(workspace)
    let focused = workspace.focusWorkspace()
    if focused { recordUserWorkspaceSelectionForRestoration() }
    return focused
}

@MainActor
func activateWorkspaceOnMonitorPreservingSourceViewport(_ workspace: Workspace, targetMonitor: Monitor) -> Bool {
    guard isValidAssignment(workspace: workspace, screen: targetMonitor.rect.topLeftCorner) else { return false }
    // A later AX recovery must not undo an explicit display move from any entry point.
    resetClosedWindowsCache()
    let sourceMonitor = workspace.isVisible ? workspace.workspaceMonitor : nil
    let sourceProjectId = workspace.projectId
    if let sourceMonitor,
       sourceMonitor.rect.topLeftCorner != targetMonitor.rect.topLeftCorner
    {
        let fallbackWorkspace = getOrCreateMonitorViewportFallbackWorkspace(
            projectId: sourceProjectId,
            for: sourceMonitor,
            excluding: workspace,
        )
        check(
            sourceMonitor.setActiveWorkspace(fallbackWorkspace),
            "Generated incompatible fallback workspace (\(fallbackWorkspace)) for the monitor (\(sourceMonitor))",
        )
    }
    guard targetMonitor.setActiveWorkspace(workspace) else { return false }
    reconcileSecondaryWorkspaceAssignments()
    return true
}

/// Secondary displays retain only their visible slot. Restoration, new slots and
/// topology changes must follow the same rule as explicit monitor moves.
@MainActor
func reconcileSecondaryWorkspaceAssignments() {
    let mainPoint = mainMonitor.rect.topLeftCorner
    for workspace in Workspace.all where !workspace.isVisible {
        guard let assigned = workspace.assignedMonitor,
              assigned.rect.topLeftCorner != mainPoint,
              isValidAssignment(workspace: workspace, screen: mainPoint) else { continue }
        workspace.preferredMonitorPoint = mainPoint
    }
}

@MainActor
func gcMonitors() {
    rearrangeWorkspacesOnMonitors()
}

extension CGPoint {
    @MainActor
    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        if !isValidAssignment(workspace: workspace, screen: self) {
            return false
        }
        let viewportId = MonitorViewportId(topLeftCorner: self)
        guard !runtime.workspaces.isWorkspaceActive(workspace.id, outside: viewportId) else {
            return false
        }
        if let monitor = sortedMonitors.first(where: { $0.rect.topLeftCorner == self }),
           runtime.workspaces.visibleWorkspace(for: monitor) !== workspace {
            WorkspaceScrollingGestureController.shared.cancelForMonitorOwnershipChange(self)
            ScrollingWindowOrdering.shared.cancel()
        }
        _ = runtime.workspaces.setActiveWorkspace(workspace, on: viewportId)
        checkWorkspaceHierarchyInvariants()
        if isWinMuxRuntimeReady { WorkspaceGestureCoordinator.shared.overviewPresentationChanged() }
        return true
    }
}

@MainActor
func checkWorkspaceHierarchyInvariants(requireActiveMonitorViewports: Bool = false) {
    for workspace in Workspace.all {
        check(runtime.workspaces.projectsById[workspace.projectId] != nil, "Workspace '\(workspace.name)' references missing project '\(workspace.projectId)'")
    }

    for (viewportId, viewport) in runtime.workspaces.monitorViewportsById {
        if let activeWorkspaceId = viewport.activeWorkspaceId {
            check(runtime.workspaces.workspaceById[activeWorkspaceId] != nil, "Display viewport '\(viewportId)' references missing workspace '\(activeWorkspaceId)'")
            check(!runtime.workspaces.isWorkspaceActive(activeWorkspaceId, outside: viewportId), "Workspace '\(activeWorkspaceId)' is active on more than one display viewport")
            if let workspace = runtime.workspaces.workspaceById[activeWorkspaceId] {
                check(isValidAssignment(workspace: workspace, screen: viewportId.topLeftCorner), "Display viewport '\(viewportId)' has incompatible active workspace '\(workspace.name)'")
            }
        }
    }

    guard requireActiveMonitorViewports else { return }
    for monitor in monitors {
        let viewportId = MonitorViewportId(monitor)
        guard let viewport = runtime.workspaces.monitorViewportsById[viewportId],
              let activeWorkspaceId = viewport.activeWorkspaceId,
              let workspace = runtime.workspaces.workspaceById[activeWorkspaceId]
        else {
            check(false, "Current monitor viewport '\(viewportId)' has no active workspace after reconciliation")
            continue
        }
        check(isValidAssignment(workspace: workspace, screen: viewportId.topLeftCorner), "Current monitor viewport '\(viewportId)' has incompatible active workspace '\(workspace.name)'")
    }
}

@MainActor
func rearrangeWorkspacesOnMonitors() {
    let oldViewportsById = runtime.workspaces.monitorViewportsById
    let currentMonitorIds = Set(monitors.map(MonitorViewportId.init))
    let activeViewportIds = Set(oldViewportsById.compactMap { viewportId, viewport -> MonitorViewportId? in
        guard let workspaceId = viewport.activeWorkspaceId,
              let workspace = runtime.workspaces.workspaceById[workspaceId],
              isValidAssignment(workspace: workspace, screen: viewportId.topLeftCorner)
        else { return nil }
        return viewportId
    })
    if activeViewportIds == currentMonitorIds {
        return
    }

    var oldVisibleMonitors: Set<MonitorViewportId> = oldViewportsById.compactMap { viewportId, viewport in
        guard let activeWorkspaceId = viewport.activeWorkspaceId,
              runtime.workspaces.workspaceById[activeWorkspaceId] != nil
        else { return nil }
        return viewportId
    }.toSet()

    let newMonitors = monitors.map(MonitorViewportId.init)
    var newMonitorToOldMonitorMapping: [MonitorViewportId: MonitorViewportId] = [:]
    for newMonitor in newMonitors where oldVisibleMonitors.contains(newMonitor) {
        check(oldVisibleMonitors.remove(newMonitor) != nil)
        newMonitorToOldMonitorMapping[newMonitor] = newMonitor
    }
    for newMonitor in newMonitors {
        if newMonitorToOldMonitorMapping[newMonitor] != nil { continue }
        if let oldMonitor = oldVisibleMonitors.minBy({ ($0.topLeftCorner - newMonitor.topLeftCorner).vectorLength }) {
            check(oldVisibleMonitors.remove(oldMonitor) != nil)
            newMonitorToOldMonitorMapping[newMonitor] = oldMonitor
        }
    }

    runtime.workspaces.monitorViewportsById = [:]

    for newMonitor in newMonitors {
        let newScreen = newMonitor.topLeftCorner
        let mappedOldMonitor = newMonitorToOldMonitorMapping[newMonitor]
        let preservedViewport = mappedOldMonitor.flatMap { oldViewportsById[$0] } ?? oldViewportsById[newMonitor]
        if var preservedViewport {
            preservedViewport = MonitorViewport(
                id: newMonitor,
                activeWorkspaceId: nil,
                previousWorkspaceId: preservedViewport.previousWorkspaceId,
                lastActiveWorkspaceByProject: preservedViewport.lastActiveWorkspaceByProject,
            )
            runtime.workspaces.monitorViewportsById[newMonitor] = preservedViewport
        }
        let existingVisibleWorkspace = mappedOldMonitor
            .flatMap { oldViewportsById[$0]?.activeWorkspaceId }
            .flatMap { runtime.workspaces.workspaceById[$0] }
        if let existingVisibleWorkspace,
           newScreen.setActiveWorkspace(existingVisibleWorkspace)
        {
            // Restoring a viewport is not a user switch: retain its local navigation history.
            runtime.workspaces.monitorViewportsById[newMonitor]?.previousWorkspaceId = preservedViewport?.previousWorkspaceId
            continue
        }
        let projectId = existingVisibleWorkspace?.projectId ?? workspaceProjectDefaultId
        let workspace = getOrCreateFallbackWorkspace(
            projectId: projectId,
            monitor: newScreen.monitorApproximation,
            excluding: existingVisibleWorkspace,
        )
        check(newScreen.setActiveWorkspace(workspace),
              "Generated incompatible fallback workspace (\(workspace)) for the display viewport (\(newScreen)")
    }
}

@MainActor
func isValidAssignment(workspace: Workspace, screen: CGPoint) -> Bool {
    isValidAssignment(workspaceName: workspace.name, screen: screen)
}

@MainActor
func isValidAssignment(workspaceName: String, screen: CGPoint) -> Bool {
    if let forceAssigned = resolvedForceAssignedMonitor(forWorkspaceName: workspaceName), forceAssigned.rect.topLeftCorner != screen {
        return false
    } else {
        return true
    }
}
