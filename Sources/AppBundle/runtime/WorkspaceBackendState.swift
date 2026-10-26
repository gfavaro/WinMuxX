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
    private(set) var observation: NativeSpacesObservation?
    var capabilities: WorkspaceBackendCapabilities {
        kind == .virtual ? .virtual : .nativeObservation
    }

    /// Live switching is intentionally unavailable until all motion/recovery
    /// owners can be handed over transactionally. Configuration enforces restart.
    func selectForStartup(_ kind: WorkspaceBackendKind) {
        precondition(observation == nil)
        self.kind = kind
    }

    func startObservation(onChange: @escaping @MainActor (NativeWorkspaceInventory, String) -> Void) {
        precondition(kind == .native)
        guard observation == nil else { return }
        let observer = NativeSpacesObservation()
        observation = observer
        observer.onChange = onChange
        observer.start()
    }

    func stop() {
        observation?.stop()
        observation?.onChange = nil
        observation = nil
    }
}
