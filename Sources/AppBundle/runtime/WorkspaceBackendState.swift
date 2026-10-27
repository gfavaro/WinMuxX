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
    /// Window moves travel through WinMuxX's animation; native frames are written directly.
    var animatesWindowMotion = true
    /// Floating windows get frames from layout; native ones keep their physical geometry.
    var arrangesFloatingWindows = true
    /// Publishes state to `subscribe` clients.
    var publishesState = true

    static let virtual = Self(ownsWorkspaceLifecycle: true, activatesWorkspaces: true,
        relocatesWorkspaces: true, tilesWindows: true, parksInactiveWindows: true, usesVirtualRecovery: true)
    /// Native observation, with native tiling on or off.
    func withTiling(_ enabled: Bool) -> Self {
        Self(ownsWorkspaceLifecycle: ownsWorkspaceLifecycle, activatesWorkspaces: activatesWorkspaces,
             relocatesWorkspaces: relocatesWorkspaces, tilesWindows: enabled, parksInactiveWindows: parksInactiveWindows,
             usesVirtualRecovery: usesVirtualRecovery, animatesWindowMotion: animatesWindowMotion,
             arrangesFloatingWindows: arrangesFloatingWindows, publishesState: publishesState)
    }

    static let nativeObservation = Self(ownsWorkspaceLifecycle: false, activatesWorkspaces: false,
        relocatesWorkspaces: false, tilesWindows: false, parksInactiveWindows: false, usesVirtualRecovery: false,
        animatesWindowMotion: false, arrangesFloatingWindows: false, publishesState: false)
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
    let nativeWindowMoves = NativeWindowSpaceMoves()
    let nativeActivity = NativeActivityTracker()
    /// Every window WindowServer knew when native mode started, on any desktop. Rules
    /// that move windows apply only to windows opened later, even if a pre-existing
    /// window is first seen when its desktop is visited.
    var windowsPresentAtLaunch: Set<UInt32> = []
    private lazy var virtualBackend = VirtualWorkspaceBackend()
    private lazy var nativeBackend = NativeWorkspaceBackend(self)
    /// What differs between the backends; shared code asks this instead of `kind`.
    var current: any WorkspaceBackend { kind == .native ? nativeBackend : virtualBackend }
    var capabilities: WorkspaceBackendCapabilities {
        if kind == .virtual { return .virtual }
        return WorkspaceBackendCapabilities.nativeObservation.withTiling(nativeTilingEnabled)
    }

    /// Whether this backend implements a command. Native shortcuts whose commands
    /// fail this check are left unregistered, so macOS keeps keys such as
    /// Control-arrow for its own Space switching instead of WinMuxX swallowing them.
    func accepts(_ command: any Command) -> Bool {
        // Moving windows writes; observation-only mode stays physically read-only.
        kind == .virtual || Self.isNativeDiagnosticOrQuery(command) ||
            (Self.isNativeNavigation(command) && (nativeTilingEnabled || command is WorkspaceCommand || command is WorkspaceBackAndForthCommand)) ||
            (nativeTilingEnabled && NativeTilingCoordinator.supports(command))
    }

    /// Navigation and queries run outside the native tiling command fence, so a
    /// sequence with window commands may add only diagnostics and config reloads.
    func accepts(_ commands: [any Command]) -> Bool {
        guard commands.allSatisfy(accepts) else { return false }
        return kind == .virtual || commands.allSatisfy(Self.runsOutsideNativeTilingFence) || commands.allSatisfy {
            !Self.runsOutsideNativeTilingFence($0) || $0 is DoctorCommand || $0 is ReloadConfigCommand
        }
    }

    static func runsOutsideNativeTilingFence(_ command: any Command) -> Bool {
        isNativeNavigation(command) || isNativeDiagnosticOrQuery(command)
    }

    /// Read-only commands that answer from config or native snapshots, the palette and
    /// sidebar, whose selections run their own native commands, and pointer moves.
    static func isNativeDiagnosticOrQuery(_ command: any Command) -> Bool {
        switch command {
            case is DoctorCommand, is ReloadConfigCommand, is ListWorkspacesCommand, is ListWindowsCommand,
                 is ListAppsCommand, is ListModesCommand, is ListExecEnvVarsCommand, is ConfigCommand,
                 is PaletteCommand, is OpenSidebarCommand, is ListMonitorsCommand, is MoveMouseCommand,
                 // Starts a process; no window or Space is touched.
                 is ExecAndForgetCommand,
                 // Switches key bindings only; it must work while tiling is paused.
                 is ModeCommand: true
            default: false
        }
    }

    /// Space navigation and cross-Space window moves: Space-level operations that run
    /// without native tiling, outside its command fence.
    static func isNativeNavigation(_ command: any Command) -> Bool {
        switch command {
            case let command as WorkspaceCommand: NativeSpaceNavigator.supports(command.args)
            case let command as MoveNodeToWorkspaceCommand: NativeWindowSpaceMoves.supports(command.args)
            // Focus may leave the desktop toward another display; it moves no window.
            case let command as FocusCommand:
                command.args.boundaries == .allMonitorsOuterFrame || focusesWindowOnHiddenDesktop(command)
            case is WorkspaceBackAndForthCommand, is MoveNodeToMonitorCommand, is FocusMonitorCommand,
                 is MoveWorkspaceToMonitorCommand, is FocusBackAndForthCommand, is EnableCommand: true
            default: false
        }
    }

    /// `focus --window-id` for a window whose desktop is not showing switches there first,
    /// so it runs as navigation rather than inside the tiling fence.
    static func focusesWindowOnHiddenDesktop(_ command: FocusCommand) -> Bool {
        guard let id = command.args.windowId, let workspace = Window.get(byId: id)?.nodeWorkspace else { return false }
        return !workspace.isVisible
    }

    /// Feeds desktop history and native hooks; call after observations and focus sync.
    func noteNativeActivity() {
        guard kind == .native, let displays = nativeObservedDisplays() else { return }
        let focused = focus.workspace
        let display = nativeLayouts.currentBySpaceID.values.contains { $0 === focused } ? focused.workspaceMonitor.displayUUID : nil
        nativeActivity.observe(displays, focusedDisplay: display, focusedWindow: focus.windowOrNil?.windowId)
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
        observer.holdsWindowReads = { MainActor.assumeIsolated { NativeScrollingPan.shared.isPanning } }
        observer.onWindowsChanged = { [weak owner] in
            guard let owner else { return }
            owner.withValue {
                owner.workspaceBackend.nativeWriteAuthority.invalidate()
                owner.workspaceBackend.nativeTiling.invalidate("WindowServer event")
            }
        }
        observer.onWindowClosed = { [weak owner] id in
            guard let owner else { return }
            owner.withValue {
                owner.workspaceBackend.nativeWriteAuthority.invalidate()
                owner.workspaceBackend.nativeTiling.invalidate("window closed")
                owner.workspaceBackend.nativeWindows.invalidate()
                guard let window = MacWindow.allWindowsMap[id] else { return }
                window.garbageCollect(skipClosedWindowsCache: true)
                owner.task { try? await window.macApp.unregisterDestroyedWindow(id) }
            }
        }
        observer.onChange = { [weak self, weak owner] inventory, event in
            guard let self, let owner else { return }
            let start = ContinuousClock.now
            defer { nativePanTiming.record("observation change", start.duration(to: .now)) }
            owner.withValue {
                self.nativeWriteAuthority.invalidate()
                self.nativeTiling.invalidate("read: \(event)")
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
