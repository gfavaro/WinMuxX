import Foundation
import NativeSpaces

struct NativeWindowRegistration {
    let windowID: UInt32
    let workspace: Workspace
    fileprivate let generation: UInt64
}

/// macOS supplies identity/membership; existing Workspace objects retain layout
/// organization. Observing a switch never rebuilds or flattens a layout tree.
@MainActor
final class NativeSpaceLayouts {
    private(set) var retainedByUUID: [String: Workspace] = [:]
    private(set) var currentBySpaceID: [String: Workspace] = [:]
    private(set) var snapshot: NativeSpacesSnapshot?
    private var generation: UInt64 = 0

    func reconcile(_ inventory: NativeWorkspaceInventory, displays: [Monitor]) {
        precondition(runtime.workspaceBackend.kind == .native)
        generation &+= 1
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
            let isNew = retainedByUUID[uuid] == nil
            let workspace = retainedByUUID[uuid] ?? Workspace.get(byName: "__native_space_\(uuid)")
            retainedByUUID[uuid] = workspace
            if isNew, runtime.workspaceBackend.nativeTilingEnabled, config.defaultRootContainerLayout == .master {
                workspace.rootTilingContainer.layout = .tiles
                workspace.transitionArrangement(to: .master)
            }
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

    func registrationWorkspace(for windowID: UInt32) -> Workspace? {
        guard let snapshot else { return nil }
        for display in snapshot.displays {
            if let workspace = workspace(for: windowID, on: display.identifier) { return workspace }
        }
        return nil
    }

    func registration(for windowID: UInt32) -> NativeWindowRegistration? {
        registrationWorkspace(for: windowID).map {
            NativeWindowRegistration(windowID: windowID, workspace: $0, generation: generation)
        }
    }

    func accepts(_ registration: NativeWindowRegistration) -> Bool {
        registration.generation == generation && registrationWorkspace(for: registration.windowID) === registration.workspace
    }
}
