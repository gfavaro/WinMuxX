import NativeSpaces

enum WorkspaceBackendKind: String, Sendable {
    case virtual, native
}

/// Capabilities describe implemented operations, not symbol availability. Native
/// observation deliberately cannot borrow virtual navigation, parking or recovery.
struct WorkspaceBackendCapabilities: Equatable, Sendable {
    let ownsWorkspaceLifecycle: Bool
    let activatesWorkspaces: Bool
    let relocatesWorkspaces: Bool
    let tilesWindows: Bool
    let parksInactiveWindows: Bool
    let usesVirtualRecovery: Bool

    static let virtual = Self(ownsWorkspaceLifecycle: true, activatesWorkspaces: true,
        relocatesWorkspaces: true, tilesWindows: true, parksInactiveWindows: true, usesVirtualRecovery: true)
    static let nativeObservation = Self(ownsWorkspaceLifecycle: false, activatesWorkspaces: false,
        relocatesWorkspaces: false, tilesWindows: false, parksInactiveWindows: false, usesVirtualRecovery: false)
}

/// The runtime owns one backend selection. Existing Workspace trees and layout
/// algorithms remain unchanged; the ownership source is separate from those trees.
@MainActor
final class WorkspaceBackendState {
    private(set) var kind: WorkspaceBackendKind = .virtual
    private(set) var selectionLocked = false
    private(set) var observation: NativeSpacesObservation?
    let nativeLayouts = NativeSpaceLayouts()
    let nativeWriteAuthority = NativeSpaceWriteAuthority()
    let nativeWindows = NativeWindowReconciler()
    var capabilities: WorkspaceBackendCapabilities {
        kind == .virtual ? .virtual : .nativeObservation
    }

    /// Live switching is intentionally unavailable until all motion/recovery
    /// owners can be handed over transactionally. Configuration enforces restart.
    func selectForStartup(_ kind: WorkspaceBackendKind) {
        precondition(observation == nil && !selectionLocked)
        self.kind = kind
    }

    func lockSelection() { selectionLocked = true }

    func startObservation(onChange: @escaping @MainActor (NativeWorkspaceInventory, String) -> Void) {
        precondition(kind == .native)
        guard observation == nil else { return }
        let observer = NativeSpacesObservation()
        let owner = runtime
        observation = observer
        observer.onWindowClosed = { [weak owner] id in
            guard let owner else { return }
            owner.withValue {
                owner.workspaceBackend.nativeWriteAuthority.invalidate()
                owner.workspaceBackend.nativeWindows.invalidate()
                guard let window = MacWindow.allWindowsMap[id] else { return }
                window.garbageCollect(skipClosedWindowsCache: true)
                owner.task { try? await window.macApp.unregisterDestroyedWindow(id) }
            }
        }
        observer.onChange = { [weak self, weak owner] inventory, event in
            guard let self, let owner else { return }
            owner.withValue {
                self.nativeWriteAuthority.invalidate()
                self.nativeWindows.invalidate()
                for window in MacWindow.allWindows { window.suspendMinimumObservationForMotion() }
                self.nativeLayouts.reconcile(inventory, displays: owner.displays.all())
                if let snapshot = inventory.currentSnapshot { self.nativeWindows.reconcile(snapshot) }
                onChange(inventory, event)
            }
        }
        observer.start()
    }

    func stop() {
        nativeWriteAuthority.invalidate()
        nativeWindows.invalidate()
        observation?.stop()
        observation?.onChange = nil
        observation?.onWindowClosed = nil
        observation = nil
    }
}
