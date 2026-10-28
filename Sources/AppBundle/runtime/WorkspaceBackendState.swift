enum WorkspaceBackendKind: String, Sendable {
    case virtual, native
}

/// Capabilities describe implemented operations, not symbol availability. Native
/// observation deliberately cannot borrow virtual navigation, parking or recovery.
struct WorkspaceBackendCapabilities: Equatable, Sendable {
    let ownsWorkspaceLifecycle: Bool
    /// Changes which virtual workspace occupies a display, not native Space switching.
    let activatesVirtualWorkspaces: Bool
    /// Changes ownership of a virtual workspace, not native desktop-content transfer.
    let relocatesVirtualWorkspaces: Bool
    let tilesWindows: Bool
    let parksInactiveWindows: Bool
    let usesVirtualRecovery: Bool
    /// Window moves travel through WinMuxX's animation; native frames are written directly.
    var animatesWindowMotion = true
    /// Floating windows get frames from layout; native ones keep their physical geometry.
    var arrangesFloatingWindows = true
    /// Publishes state to `subscribe` clients.
    var publishesState = true

    static let virtual = Self(ownsWorkspaceLifecycle: true, activatesVirtualWorkspaces: true,
        relocatesVirtualWorkspaces: true, tilesWindows: true, parksInactiveWindows: true, usesVirtualRecovery: true)
    /// Native observation, with native tiling on or off.
    func withTiling(_ enabled: Bool) -> Self {
        Self(ownsWorkspaceLifecycle: ownsWorkspaceLifecycle, activatesVirtualWorkspaces: activatesVirtualWorkspaces,
             relocatesVirtualWorkspaces: relocatesVirtualWorkspaces, tilesWindows: enabled, parksInactiveWindows: parksInactiveWindows,
             usesVirtualRecovery: usesVirtualRecovery, animatesWindowMotion: animatesWindowMotion,
             arrangesFloatingWindows: arrangesFloatingWindows, publishesState: publishesState)
    }

    static let nativeObservation = Self(ownsWorkspaceLifecycle: false, activatesVirtualWorkspaces: false,
        relocatesVirtualWorkspaces: false, tilesWindows: false, parksInactiveWindows: false, usesVirtualRecovery: false,
        animatesWindowMotion: false, arrangesFloatingWindows: false, publishesState: false)
}

/// The runtime owns one backend selection. Existing Workspace trees and layout
/// algorithms remain unchanged; the ownership source is separate from those trees.
@MainActor
final class WorkspaceBackendState {
    private(set) var kind: WorkspaceBackendKind = .virtual
    private(set) var selectionLocked = false
    private(set) lazy var native = NativeWorkspaceLifecycle(self)
    private lazy var virtualBackend = VirtualWorkspaceBackend()
    private lazy var nativeBackend = NativeWorkspaceBackend(native)
    private lazy var virtualUI = VirtualWorkspaceBackendUI()
    private lazy var nativeUI = NativeWorkspaceBackendUI()
    var ui: any WorkspaceBackendUI { kind == .native ? nativeUI : virtualUI }
    /// What differs between the backends; shared code asks this instead of `kind`.
    var current: any WorkspaceBackend { kind == .native ? nativeBackend : virtualBackend }
    var capabilities: WorkspaceBackendCapabilities {
        if kind == .virtual { return .virtual }
        return WorkspaceBackendCapabilities.nativeObservation.withTiling(native.tilingEnabled)
    }

    /// Virtual commands use shared implementations; native admission stays in native policy.
    func accepts(_ command: any Command) -> Bool {
        kind == .virtual || NativeCommandPolicy.accepts(command, tilingEnabled: native.tilingEnabled)
    }

    func accepts(_ commands: [any Command]) -> Bool {
        guard commands.allSatisfy(accepts) else { return false }
        return kind == .virtual || NativeCommandPolicy.acceptsSequence(commands)
    }

    /// Live switching is intentionally unavailable until all motion/recovery
    /// owners can be handed over transactionally. Configuration enforces restart.
    func selectForStartup(_ kind: WorkspaceBackendKind, nativeTilingEnabled: Bool = false) {
        precondition(native.observation == nil && !selectionLocked)
        self.kind = kind
        native.configureTiling(nativeTilingEnabled)
    }

    func lockSelection() { selectionLocked = true }

    func stop() { native.stop() }
}
