import NativeSpaces

/// Owns the native backend's observation, navigation, writes and lifecycle work.
/// Its callbacks retain the originating runtime binding, including across tasks.
@MainActor
final class NativeWorkspaceLifecycle {
    private unowned let state: WorkspaceBackendState
    init(_ state: WorkspaceBackendState) { self.state = state }
    private(set) var tilingEnabled = false
    func configureTiling(_ enabled: Bool) { tilingEnabled = enabled }
    private(set) var observation: NativeSpacesObservation?
    let layouts = NativeSpaceLayouts()
    let writeAuthority = NativeSpaceWriteAuthority()
    let windows = NativeWindowReconciler()
    let tiling = NativeTilingCoordinator()
    let stateChanges = ChangeSignal()
    let persistence = NativeLayoutPersistence()
    let navigation = NativeSpaceNavigator()
    let windowMoves = NativeWindowSpaceMoves()
    let activity = NativeActivityTracker()
    let focusHold = NativeFocusHold()
    let desktopTopUp = NativeDesktopTopUp()
    private(set) var topUpTimer: Task<Void, Never>?
    private var topUpGeneration = 0
    private var topUpSuspended = false
    /// Every window WindowServer knew when native mode started, on any desktop. Rules
    /// that move windows apply only to windows opened later, even if a pre-existing
    /// window is first seen when its desktop is visited.
    var windowsPresentAtLaunch: Set<UInt32> = []
    /// Each read revokes the desktop map until it completes. Navigation outside the tiling
    /// fence waits for an in-flight read instead of failing on, or acting on, a stale map.
    func awaitCurrentObservation(timeout: Duration = .milliseconds(500)) async {
        guard state.kind == .native, let observation else { return }
        _ = await stateChanges.wait(timeout: timeout) { observation.inventory.status != .reading }
    }

    /// Feeds desktop history and native hooks; call after observations and focus sync.
    func noteNativeActivity() {
        guard state.kind == .native, let displays = nativeObservedDisplays() else { return }
        let focused = focus.workspace
        let display = layouts.currentBySpaceID.values.contains { $0 === focused } ? focused.workspaceMonitor.displayUUID : nil
        activity.observe(displays, focusedDisplay: display, focusedWindow: focus.windowOrNil?.windowId)
    }

    func startObservation(observer: NativeSpacesObservation = NativeSpacesObservation(), onChange: @escaping @MainActor (NativeWorkspaceInventory, String) -> Void) {
        precondition(state.kind == .native)
        guard observation == nil else { return }
        let owner = runtime
        observation = observer
        observer.holdsWindowReads = { MainActor.assumeIsolated { NativeScrollingPan.shared.isPanning } }
        observer.onWindowsChanged = { [weak owner] in
            guard let owner else { return }
            owner.withValue {
                owner.workspaceBackend.native.writeAuthority.invalidate()
                owner.workspaceBackend.native.tiling.invalidate("WindowServer event")
            }
        }
        observer.onWindowClosed = { [weak owner] id in
            guard let owner else { return }
            owner.withValue {
                owner.workspaceBackend.native.writeAuthority.invalidate()
                owner.workspaceBackend.native.tiling.invalidate("window closed")
                owner.workspaceBackend.native.windows.invalidate()
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
                self.writeAuthority.invalidate()
                self.tiling.invalidate("read: \(event)")
                self.windows.invalidate()
                for window in MacWindow.allWindows { window.suspendMinimumObservationForMotion() }
                self.layouts.reconcile(inventory, displays: owner.displays.all())
                if let snapshot = inventory.currentSnapshot { self.windows.reconcile(snapshot) }
                onChange(inventory, event)
                self.stateChanges.notify()
                self.topUpNativeDesktops(inventory)
            }
        }
        observer.start()
    }

    /// Desktop creation is a write, so it waits for native tiling like window moves do.
    func topUpNativeDesktops(_ inventory: NativeWorkspaceInventory) {
        guard tilingEnabled, !topUpSuspended, TrayMenuModel.shared.isEnabled, inventory.status != .reading, let snapshot = inventory.currentSnapshot else { return }
        let changed = desktopTopUp.observed(snapshot.displays,
            target: NativeDesktopTopUpPlan.target(config.persistentWorkspaces), home: nativeDesktopHome) { [weak self] delay in
            self?.scheduleTopUpRead(after: delay)
        }
        if changed { observation?.requestRead(event: "desktopTopUp") }
    }

    func scheduleTopUpRead(after delay: Duration) {
        topUpTimer?.cancel()
        topUpGeneration += 1
        let generation = topUpGeneration
        topUpTimer = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled, self.topUpGeneration == generation,
                  self.tilingEnabled, !self.topUpSuspended, TrayMenuModel.shared.isEnabled, let observation = self.observation else { return }
            self.topUpTimer = nil
            observation.requestRead(event: "desktopTopUp")
        }
    }

    func cancelTopUpRead() {
        topUpGeneration += 1
        topUpTimer?.cancel()
        topUpTimer = nil
    }

    func setTopUpEnabled(_ enabled: Bool) {
        topUpSuspended = !enabled
        cancelTopUpRead()
    }

    func stop() {
        cancelTopUpRead()
        writeAuthority.invalidate()
        windows.invalidate()
        tiling.stop()
        observation?.stop()
        observation?.onChange = nil
        observation?.onWindowClosed = nil
        observation?.onWindowsChanged = nil
        observation = nil
    }
}
