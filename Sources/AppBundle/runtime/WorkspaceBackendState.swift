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
    private(set) var nativeTilingEnabled = false
    private(set) var selectionLocked = false
    private(set) var observation: NativeSpacesObservation?
    let nativeLayouts = NativeSpaceLayouts()
    let nativeWriteAuthority = NativeSpaceWriteAuthority()
    let nativeWindows = NativeWindowReconciler()
    let nativeTiling = NativeTilingCoordinator()
    let nativePersistence = NativeLayoutPersistence()
    let nativeNavigation = NativeSpaceNavigator()
    var capabilities: WorkspaceBackendCapabilities {
        if kind == .virtual { return .virtual }
        return WorkspaceBackendCapabilities(ownsWorkspaceLifecycle: false, activatesWorkspaces: false,
            relocatesWorkspaces: false, tilesWindows: nativeTilingEnabled, parksInactiveWindows: false, usesVirtualRecovery: false)
    }

    /// Whether this backend implements a command. Native shortcuts whose commands
    /// fail this check are left unregistered, so macOS keeps keys such as
    /// Control-arrow for its own Space switching instead of WinMuxX swallowing them.
    func accepts(_ command: any Command) -> Bool {
        kind == .virtual || command is DoctorCommand || command is ReloadConfigCommand ||
            Self.isNativeNavigation(command) || (nativeTilingEnabled && NativeTilingCoordinator.supports(command))
    }

    /// Navigation runs outside the native tiling command fence, so a sequence may
    /// pair it only with diagnostics, never with window commands.
    func accepts(_ commands: [any Command]) -> Bool {
        guard commands.allSatisfy(accepts) else { return false }
        return kind == .virtual || !commands.contains(where: Self.isNativeNavigation) ||
            commands.allSatisfy { Self.isNativeNavigation($0) || $0 is DoctorCommand || $0 is ReloadConfigCommand }
    }

    static func isNativeNavigation(_ command: any Command) -> Bool {
        (command as? WorkspaceCommand).map { NativeSpaceNavigator.supports($0.args) } ?? false
    }

    /// Live switching is intentionally unavailable until all motion/recovery
    /// owners can be handed over transactionally. Configuration enforces restart.
    func selectForStartup(_ kind: WorkspaceBackendKind, nativeTilingEnabled: Bool = false) {
        precondition(observation == nil && !selectionLocked)
        self.kind = kind
        self.nativeTilingEnabled = nativeTilingEnabled
    }

    func lockSelection() { selectionLocked = true }

    func startObservation(onChange: @escaping @MainActor (NativeWorkspaceInventory, String) -> Void) {
        precondition(kind == .native)
        guard observation == nil else { return }
        let observer = NativeSpacesObservation()
        let owner = runtime
        observation = observer
        observer.onWindowsChanged = { [weak owner] in
            guard let owner else { return }
            owner.withValue {
                owner.workspaceBackend.nativeWriteAuthority.invalidate()
                owner.workspaceBackend.nativeTiling.invalidate()
            }
        }
        observer.onWindowClosed = { [weak owner] id in
            guard let owner else { return }
            owner.withValue {
                owner.workspaceBackend.nativeWriteAuthority.invalidate()
                owner.workspaceBackend.nativeTiling.invalidate()
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
                self.nativeTiling.invalidate()
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
        nativeTiling.stop()
        observation?.stop()
        observation?.onChange = nil
        observation?.onWindowClosed = nil
        observation?.onWindowsChanged = nil
        observation = nil
    }
}
