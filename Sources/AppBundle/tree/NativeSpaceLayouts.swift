import Foundation
import NativeSpaces

/// macOS supplies identity/membership; existing Workspace objects retain layout
/// organization. Observing a switch never rebuilds or flattens a layout tree.
@MainActor
final class NativeSpaceLayouts {
    private(set) var retainedByUUID: [String: Workspace] = [:]
    private(set) var currentBySpaceID: [String: Workspace] = [:]
    private(set) var snapshot: NativeSpacesSnapshot?

    func reconcile(_ inventory: NativeWorkspaceInventory, displays: [Monitor]) {
        precondition(runtime.workspaceBackend.kind == .native)
        // Revoke the current membership view before considering a replacement.
        snapshot = nil
        currentBySpaceID = [:]
        guard let observed = inventory.currentSnapshot else {
            // During a read, retain the last observed viewport history. Fresh
            // membership authority is already revoked above. A failed/stopped
            // source has no active native viewport; it never creates a fallback.
            if inventory.status != .reading {
                for id in Array(runtime.workspaces.monitorViewportsById.keys) {
                    runtime.workspaces.monitorViewportsById[id]?.activeWorkspaceId = nil
                }
            }
            return
        }
        var active: [MonitorViewportId: Workspace] = [:]
        for record in inventory.records where record.space.isDesktop {
            guard let uuid = record.space.uuid else { continue }
            let matches = displays.filter { $0.displayUUID == record.displayIdentifier }
            // Never use ordinal or nearest-display fallback for native ownership.
            guard matches.count == 1, let display = matches.first else { continue }
            let workspace = retainedByUUID[uuid] ?? Workspace.get(byName: "__native_space_\(uuid)")
            retainedByUUID[uuid] = workspace
            workspace.preferredMonitorPoint = display.rect.topLeftCorner
            currentBySpaceID[record.space.id] = workspace
            if record.isActive {
                active[MonitorViewportId(display)] = workspace
            }
        }
        for viewportID in Set(runtime.workspaces.monitorViewportsById.keys).union(active.keys) {
            if let workspace = active[viewportID] {
                if runtime.workspaces.monitorViewportsById[viewportID]?.activeWorkspaceId != workspace.id {
                    _ = runtime.workspaces.setActiveWorkspace(workspace, on: viewportID)
                }
            } else {
                runtime.workspaces.monitorViewportsById[viewportID]?.activeWorkspaceId = nil
            }
        }
        snapshot = observed
    }

    /// Unlike Monitor.activeWorkspace, this never materializes a virtual fallback.
    func activeWorkspace(on displayIdentifier: String) -> Workspace? {
        guard let display = snapshot?.displays.first(where: { $0.identifier == displayIdentifier }) else { return nil }
        return currentBySpaceID[display.activeSpaceID]
    }

    func workspace(for windowID: UInt32, on displayIdentifier: String) -> Workspace? {
        guard let snapshot,
              case .desktop(let spaceID, _) = snapshot.eligibility(windowID: windowID, on: displayIdentifier) else { return nil }
        return currentBySpaceID[spaceID]
    }
}
