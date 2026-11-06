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
// A configured assignment overrides both while its display is connected, as in AeroSpace.
@MainActor
func workspaceIsAvailableForMonitor(_ workspace: Workspace, monitor: Monitor) -> Bool {
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
    focusing: Bool = true,
) -> Bool {
    // Ordinary selection never relocates an owned workspace, visible or hidden.
    if workspace.isVisible {
        guard workspace.visibleMonitor != nil else { return false }
        let focused = workspace.focusWorkspace()
        if focused { recordUserWorkspaceSelectionForRestoration() }
        return focused
    }
    let monitor = workspaceMonitorForUserActivation(workspace, on: targetMonitor)
    guard monitor.setActiveWorkspace(workspace) else { return false }
    WorkspaceMotionDiagnostics.selected(workspace)
    guard focusing else {
        recordUserWorkspaceSelectionForRestoration()
        return true
    }
    let focused = workspace.focusWorkspace()
    if focused { recordUserWorkspaceSelectionForRestoration() }
    return focused
}

/// A sidebar selection that changes what another display shows leaves focus on the
/// display in use. One already showing elsewhere is focused there.
@MainActor
func sidebarSelectionKeepsFocus(_ workspace: Workspace, on targetMonitor: Monitor) -> Bool {
    !workspace.isVisible && workspaceMonitorForUserActivation(workspace, on: targetMonitor).rect.topLeftCorner !=
        focus.workspace.workspaceMonitor.rect.topLeftCorner
}

@MainActor
/// `reserved` workspaces are never chosen to fill the display the workspace leaves.
/// Fails without changes when configuration assigns the workspace to another display.
func activateWorkspaceOnMonitorPreservingSourceViewport(_ workspace: Workspace, targetMonitor: Monitor, reserved: [Workspace] = []) -> Bool {
    guard !isAssignedElsewhere(workspace.name, than: targetMonitor) else { return false }
    // A later AX recovery must not undo an explicit display move from any entry point.
    resetClosedWindowsCache()
    return showWorkspacePreservingSourceViewport(workspace, on: targetMonitor, reserved: reserved)
}

@MainActor
private func showWorkspacePreservingSourceViewport(_ workspace: Workspace, on targetMonitor: Monitor, reserved: [Workspace] = []) -> Bool {
    let sourceMonitor = workspace.isVisible ? workspace.workspaceMonitor : nil
    let sourceProjectId = workspace.projectId
    if let sourceMonitor,
       sourceMonitor.rect.topLeftCorner != targetMonitor.rect.topLeftCorner
    {
        let fallbackWorkspace = getOrCreateMonitorViewportFallbackWorkspace(
            projectId: sourceProjectId,
            for: sourceMonitor,
            excluding: workspace,
            reserved: reserved,
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

/// Secondary displays retain only their visible slot, plus workspaces configuration assigns
/// to them. Restoration, new slots and topology changes follow the same rule as explicit moves.
@MainActor
func reconcileSecondaryWorkspaceAssignments() {
    let mainPoint = mainMonitor.rect.topLeftCorner
    for workspace in Workspace.all where !workspace.isVisible && workspace.forceAssignedMonitor == nil {
        guard let assigned = workspace.assignedMonitor, assigned.rect.topLeftCorner != mainPoint else { continue }
        workspace.preferredMonitorPoint = mainPoint
    }
}

/// An assigned workspace showing elsewhere, after a config edit, restoration or display
/// change, moves to its display. Restart recovery stays valid: this is not a user move.
@MainActor
func showAssignedWorkspacesOnTheirDisplays() {
    for workspace in Workspace.all {
        guard let visible = workspace.visibleMonitor, let assigned = workspace.forceAssignedMonitor,
              visible.rect.topLeftCorner != assigned.rect.topLeftCorner else { continue }
        _ = showWorkspacePreservingSourceViewport(workspace, on: assigned)
    }
}

@MainActor
func gcMonitors() {
    rearrangeWorkspacesOnMonitors()
}

extension CGPoint {
    @MainActor
    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        let viewportId = MonitorViewportId(topLeftCorner: self)
        guard !runtime.workspaces.isWorkspaceActive(workspace.id, outside: viewportId),
              workspace.forceAssignedMonitor.map({ $0.rect.topLeftCorner == self }) != false else {
            return false
        }
        if let monitor = sortedMonitors.first(where: { $0.rect.topLeftCorner == self }),
           runtime.workspaces.visibleWorkspace(for: monitor) !== workspace {
        }
        _ = runtime.workspaces.setActiveWorkspace(workspace, on: viewportId)
        checkWorkspaceHierarchyInvariants()
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
        }
    }

    guard requireActiveMonitorViewports else { return }
    for monitor in monitors {
        let viewportId = MonitorViewportId(monitor)
        guard let activeWorkspaceId = runtime.workspaces.monitorViewportsById[viewportId]?.activeWorkspaceId,
              runtime.workspaces.workspaceById[activeWorkspaceId] != nil
        else {
            check(false, "Current monitor viewport '\(viewportId)' has no active workspace after reconciliation")
            continue
        }
    }
}

/// A display that disappears stops showing its workspace at once, so that workspace is an
/// ordinary hidden one while the topology settles; its viewport is stashed by display UUID
/// for reconnection. Fallbacks for new displays still wait for the settled pass.
@MainActor
func retireDisconnectedViewports() {
    let connected = Set(monitors.compactMap(\.displayUUID))
    for (id, viewport) in runtime.workspaces.monitorViewportsById {
        // Without a UUID a vanished coordinate proves nothing; the settled pass maps it.
        guard let uuid = viewport.displayUUID, !connected.contains(uuid) else { continue }
        runtime.workspaces.disconnectedViewportsByDisplay[uuid] = viewport
        runtime.workspaces.monitorViewportsById[id] = nil
    }
}

@MainActor
func rearrangeWorkspacesOnMonitors() {
    let displayUUIDById = Dictionary(monitors.map { (MonitorViewportId($0), $0.displayUUID) }, uniquingKeysWith: { first, _ in first })
    // Record the display of viewports that have none yet. A recorded one is never overwritten
    // here: displays that swapped positions must keep their own workspaces.
    for (id, uuid) in displayUUIDById where runtime.workspaces.monitorViewportsById[id]?.displayUUID == nil {
        runtime.workspaces.monitorViewportsById[id]?.displayUUID = uuid
    }
    let oldViewportsById = runtime.workspaces.monitorViewportsById
    runtime.workspaces.disconnectedViewportsByDisplay = runtime.workspaces.disconnectedViewportsByDisplay.filter {
        $0.value.activeWorkspaceId.flatMap { runtime.workspaces.workspaceById[$0] } != nil
    }
    let currentMonitorIds = Set(monitors.map(MonitorViewportId.init))
    let activeViewportIds = Set(oldViewportsById.compactMap { viewportId, viewport -> MonitorViewportId? in
        guard let workspaceId = viewport.activeWorkspaceId, runtime.workspaces.workspaceById[workspaceId] != nil else { return nil }
        return viewportId
    })
    let displaysMoved = displayUUIDById.contains { id, uuid in
        guard let uuid, let recorded = oldViewportsById[id]?.displayUUID else { return false }
        return recorded != uuid
    }
    if activeViewportIds == currentMonitorIds && !displaysMoved {
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
    // A display keeps its viewport by identity even when the arrangement moves it.
    for newMonitor in newMonitors {
        guard let uuid = displayUUIDById[newMonitor] ?? nil,
              let oldMonitor = oldVisibleMonitors.first(where: { oldViewportsById[$0]?.displayUUID == uuid }) else { continue }
        oldVisibleMonitors.remove(oldMonitor)
        newMonitorToOldMonitorMapping[newMonitor] = oldMonitor
    }
    for newMonitor in newMonitors where newMonitorToOldMonitorMapping[newMonitor] == nil && oldVisibleMonitors.contains(newMonitor) {
        check(oldVisibleMonitors.remove(newMonitor) != nil)
        newMonitorToOldMonitorMapping[newMonitor] = newMonitor
    }
    // A reconnected display shows the workspace it showed before it was disconnected.
    var reconnectedViewports: [MonitorViewportId: MonitorViewport] = [:]
    for newMonitor in newMonitors where newMonitorToOldMonitorMapping[newMonitor] == nil {
        guard let uuid = displayUUIDById[newMonitor] ?? nil,
              let viewport = runtime.workspaces.disconnectedViewportsByDisplay.removeValue(forKey: uuid) else { continue }
        reconnectedViewports[newMonitor] = viewport
    }
    for newMonitor in newMonitors {
        if newMonitorToOldMonitorMapping[newMonitor] != nil || reconnectedViewports[newMonitor] != nil { continue }
        if let oldMonitor = oldVisibleMonitors.minBy({ ($0.topLeftCorner - newMonitor.topLeftCorner).vectorLength }) {
            check(oldVisibleMonitors.remove(oldMonitor) != nil)
            newMonitorToOldMonitorMapping[newMonitor] = oldMonitor
        }
    }
    for oldMonitor in oldVisibleMonitors {
        guard let viewport = oldViewportsById[oldMonitor], let uuid = viewport.displayUUID else { continue }
        runtime.workspaces.disconnectedViewportsByDisplay[uuid] = viewport
    }

    runtime.workspaces.monitorViewportsById = [:]
    var assignedElsewhere: [Workspace] = []

    for newMonitor in newMonitors {
        defer { runtime.workspaces.monitorViewportsById[newMonitor]?.displayUUID = displayUUIDById[newMonitor] ?? nil }
        let newScreen = newMonitor.topLeftCorner
        let mappedOldMonitor = newMonitorToOldMonitorMapping[newMonitor]
        let reconnected = reconnectedViewports[newMonitor]
        let preservedViewport = mappedOldMonitor.flatMap { oldViewportsById[$0] } ?? reconnected ?? oldViewportsById[newMonitor]
        if var preservedViewport {
            preservedViewport = MonitorViewport(
                id: newMonitor,
                activeWorkspaceId: nil,
                previousWorkspaceId: preservedViewport.previousWorkspaceId,
                lastActiveWorkspaceByProject: preservedViewport.lastActiveWorkspaceByProject,
            )
            runtime.workspaces.monitorViewportsById[newMonitor] = preservedViewport
        }
        // A workspace the user showed elsewhere meanwhile stays there: setActiveWorkspace refuses it.
        let existingVisibleWorkspace = (mappedOldMonitor.flatMap { oldViewportsById[$0]?.activeWorkspaceId } ?? reconnected?.activeWorkspaceId)
            .flatMap { runtime.workspaces.workspaceById[$0] }
        if let existingVisibleWorkspace,
           newScreen.setActiveWorkspace(existingVisibleWorkspace)
        {
            // Restoring a viewport is not a user switch: retain its local navigation history.
            runtime.workspaces.monitorViewportsById[newMonitor]?.previousWorkspaceId = preservedViewport?.previousWorkspaceId
            continue
        }
        if let existingVisibleWorkspace, isAssignedElsewhere(existingVisibleWorkspace.name, than: newScreen.monitorApproximation) {
            assignedElsewhere.append(existingVisibleWorkspace)
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
    // A workspace whose assignment now resolves to another display keeps showing, there.
    for workspace in assignedElsewhere where !workspace.isVisible {
        if let assigned = workspace.forceAssignedMonitor { _ = assigned.setActiveWorkspace(workspace) }
    }
}
