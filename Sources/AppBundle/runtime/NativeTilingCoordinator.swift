import AppKit
import Common
import NativeSpaces

enum NativeTilingCommandScope {
    @TaskLocal static var active = false
    @TaskLocal static var validateTarget: (@MainActor @Sendable () -> Bool)?
}

/// Applies the shared engine to observed active desktop trees. It neither owns
/// Spaces nor uses virtual activation, parking, recovery or layout algorithms.
@MainActor
final class NativeTilingCoordinator {
    private(set) var status = "Observation only"
    private(set) var ready = false
    /// Set by the first completed layout; windows registered before it existed at startup.
    private(set) var hasCompletedInitialLayout = false
    private var hasManagedNativeFocus = false
    private var generation: UInt64 = 0
    private var shortcutsInstalled = false
    private var mouseMonitor: Any?

    func invalidate() {
        generation &+= 1
        ready = false
        hasManagedNativeFocus = false
        if runtime.workspaceBackend.nativeTilingEnabled { status = "Waiting for native reconciliation" }
        for app in MacApp.allAppsMap.values { app.cancelPendingFrameWrites() }
    }

    func stop() {
        invalidate()
        MacApp.cancelPendingFocus()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    func accept(_ snapshot: NativeSpacesSnapshot, identities: [NativeWindowWriteIdentity]) async {
        guard runtime.workspaceBackend.nativeTilingEnabled else { return }
        guard !serverArgs.isReadOnly else { status = "Tiling suppressed by read-only startup"; return }
        guard AXIsProcessTrusted(), runtime.workspaceBackend.observation?.windowEventsAvailable == true else {
            status = "Tiling suspended: Accessibility or native lifecycle events unavailable"
            return
        }
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 else {
            status = "Tiling suspended: Mission Control observation is not validated on this macOS version"
            return
        }
        let version = generation
        let screenSizes = monitors.map { $0.rect.size }
        let missionControl = await Task.detached {
            guard let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return true }
            return isMissionControlVisible(rows, screenSizes: screenSizes) { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        }.value
        guard generation == version else { return }
        guard !missionControl, NSEvent.pressedMouseButtons == 0, !holdsForMouseRelease else {
            status = missionControl ? "Tiling paused for Mission Control" : "Tiling paused for mouse interaction"
            return
        }
        let backend = runtime.workspaceBackend
        guard snapshot.displays.contains(where: { backend.nativeLayouts.activeWorkspace(on: $0.identifier) != nil }) else {
            status = "Tiling paused: no active ordinary desktop"
            return
        }
        await backend.nativePersistence.reconcile(backend.nativeLayouts)
        guard generation == version else { return }
        backend.nativeWriteAuthority.replace(snapshot: snapshot, identities: identities)
        await synchronizeFocus()
        guard generation == version else { return }
        backend.noteNativeActivity()
        if mouseMonitor == nil && !isUnitTest {
            let owner = runtime
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp]) { [weak owner] event in
                let released = event.type == .leftMouseUp || event.type == .rightMouseUp
                let leftButton = event.type == .leftMouseDown || event.type == .leftMouseUp
                Task { @MainActor [weak owner] in
                    guard let owner else { return }
                    owner.withValue {
                        MacApp.cancelPendingFocus()
                        let tiling = owner.workspaceBackend.nativeTiling
                        guard released else {
                            // A read queued by the drag's own move events must not lay the
                            // window back out before its release is adopted.
                            if leftButton { tiling.holdsForMouseRelease = true }
                            return owner.workspaceBackend.nativeWriteAuthority.invalidate()
                        }
                        owner.task {
                            if leftButton { await tiling.adoptMouseRelease() }
                            tiling.holdsForMouseRelease = false
                            owner.workspaceBackend.observation?.requestRead(event: "nativeMouseReleased")
                        }
                    }
                }
            }
        }
        if !shortcutsInstalled {
            shortcutsInstalled = true
            try? await activateMode(mainModeId, runCallbacks: false)
        }
        guard !holdsForMouseRelease else { status = "Tiling paused for mouse interaction"; return }
        let targets = Set(snapshot.reconciliationSpaceIDs ?? snapshot.displays.map(\.activeSpaceID))
        for display in snapshot.displays where targets.contains(display.activeSpaceID) {
            guard generation == version,
                  let workspace = backend.nativeLayouts.activeWorkspace(on: display.identifier) else { continue }
            do { try await workspace.layoutWorkspace() }
            catch { status = "Native layout suspended: \(error)"; backend.nativeWriteAuthority.invalidate(); ready = false; return }
            guard generation == version else { return }
            await raiseCoveredNativeTabs(in: workspace, frontToBack: onScreenWindowOrder())
        }
        await backend.nativePersistence.save(backend.nativeLayouts)
        guard generation == version else { return }
        ready = true
        hasCompletedInitialLayout = true
        status = "Native tiling active"
        updateTrayText()
        await updateWindowTabModel() // Also refreshes borders.
        RawWorkspaceTouchSource.shared.updateDemand() // Touches are read only while a scrolling desktop shows.
    }

    /// Reads the frontmost window once its drag has ended and adopts a resize or a
    /// drop onto another tile; the read that follows lays the desktop out again.
    func adoptMouseRelease() async {
        let intent = pendingWindowDragIntent.map { "\($0.kind)" }
        if await applyNativeDragIntent() { return lastMouseRelease = "applied overlay \(intent ?? "")" }
        guard hasCompletedInitialLayout else { return lastMouseRelease = "ignored: no completed native layout yet" }
        guard let front = NSWorkspace.shared.frontmostApplication, let app = try? await MacApp.getOrRegister(front),
              let window = try? await app.getFocusedWindow() else {
            return lastMouseRelease = "ignored: frontmost window is not managed"
        }
        guard let actual = try? await window.getAxRect() else { return lastMouseRelease = "ignored: window \(window.windowId) frame unreadable" }
        let target = window.lastAppliedLayoutPhysicalRect.map { "\($0)" } ?? "none"
        let outcome = adoptNativeMouseRelease(window, actual: actual, pointer: mouseLocation)
        lastMouseRelease = "window \(window.windowId): \(outcome); actual \(actual), layout \(target)"
    }

    private var scrollingLayoutTask: Task<Void, Never>?
    private var scrollingLayoutPending = false

    /// Scrolling viewport changes (panning, settling, minimap, commands) re-lay out the
    /// visible scrolling desktops at once under the current write permits; waiting for
    /// an observation read would make panning lag. Requests coalesce into one pass.
    func relayoutVisibleScrolling() {
        guard ready else { return runtime.workspaceBackend.observation?.requestRead(event: "nativeScrolling") ?? () }
        if scrollingLayoutTask != nil { scrollingLayoutPending = true; return }
        scrollingLayoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                scrollingLayoutPending = false
                let version = generation
                for workspace in runtime.workspaceBackend.nativeLayouts.currentBySpaceID.values
                    where workspace.isVisible && workspace.arrangement == .scrolling {
                    guard ready, generation == version, !holdsForMouseRelease else { break }
                    let start = ContinuousClock.now
                    do { try await workspace.layoutWorkspace() } catch { break }
                    noteScrollingLayout(start.duration(to: .now), during: workspace.scrollingGestureMotionActive)
                }
            } while scrollingLayoutPending
            scrollingLayoutTask = nil
        }
    }

    /// Layout timings of the current or last pan, for doctor.
    private(set) var scrollingLayoutTiming = "none"
    private var panLayouts: [Duration] = []
    private var panStarted: ContinuousClock.Instant?

    private func noteScrollingLayout(_ duration: Duration, during gesture: Bool) {
        guard gesture else { panStarted = nil; return }
        if panStarted == nil { panStarted = .now; panLayouts = [] }
        panLayouts.append(duration)
        let ms = panLayouts.map { Double($0.components.attoseconds) / 1e15 + Double($0.components.seconds) * 1000 }
        let elapsed = panStarted.map { $0.duration(to: .now) } ?? .zero
        let seconds = max(0.001, Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds))
        scrollingLayoutTiming = String(format: "%d layouts, %.0f/s, avg %.1f ms, max %.1f ms", ms.count,
            Double(ms.count) / seconds, ms.reduce(0, +) / Double(ms.count), ms.max() ?? 0)
    }

    /// Set at left mouse-down; layout waits until that drag's release is adopted.
    var holdsForMouseRelease = false

    /// The last release decision, for doctor.
    private(set) var lastMouseRelease = "none"

    func synchronizeFocus() async {
        hasManagedNativeFocus = false
        let backend = runtime.workspaceBackend
        if let front = NSWorkspace.shared.frontmostApplication,
           let app = try? await MacApp.getOrRegister(front),
           let window = try? await app.getFocusedWindow(), window.nativeLayoutEligible,
           backend.nativeLayouts.registrationWorkspace(for: window.windowId) === window.nodeWorkspace {
            _ = window.focusWindow()
            runtime.nativeFocus.lastKnownWindowID = window.windowId
            hasManagedNativeFocus = true
            return
        }
        // An empty desktop still has a layout target; it must not activate an app.
        if let workspace = runtime.focus.requested.liveOrNil?.workspace,
           backend.nativeLayouts.currentBySpaceID.values.contains(where: { $0 === workspace }),
           workspace.isVisible { return }
        if let display = backend.nativeLayouts.snapshot?.displays.first,
           let workspace = backend.nativeLayouts.activeWorkspace(on: display.identifier) {
            _ = setFocus(to: workspace.toLiveFocus(), origin: .native)
        }
    }

    static func supports(_ command: any Command) -> Bool {
        switch command {
            case is DoctorCommand, is ReloadConfigCommand, is ModeCommand,
                 is ResizeCommand, is SwapCommand,
                 // Per-window actions; observation reconciles the states they produce.
                 is FullscreenCommand, is MacosNativeFullscreenCommand, is MacosNativeMinimizeCommand,
                 is CloseCommand, is CloseAllWindowsButCurrentCommand,
                 is BalanceSizesCommand, is SplitCommand, is SwapWithMasterCommand, is JoinWithCommand,
                 is ScrollingCenterCommand, is ScrollingWidthCommand, is ScrollingMinimapCommand: return true
            // Tab groups stack natively only with window tabs; Accordion overlap is not shown yet.
            case is StackWithCommand: return config.windowTabs.enabled
            case let command as MoveCommand: return command.args.boundaries == .workspace
            case let command as FocusCommand:
                return command.args.boundaries == .workspace && command.args.boundariesAction != .wrapAroundAllMonitors
            case let command as WorkspaceLayoutCommand:
                return command.args.layouts.val.allSatisfy { $0 == .dwindle || $0 == .master || $0 == .scrolling }
            case let command as LayoutCommand:
                return !command.args.forNextDetectedWindow && command.args.toggleBetween.val.allSatisfy {
                    [.tiles, .h_tiles, .v_tiles, .horizontal, .vertical, .auto, .tiling, .floating].contains($0) ||
                        $0 == .tabGroup && config.windowTabs.enabled
                }
            default: return false
        }
    }

    func run(_ commands: [any Command], env: CmdEnv, io: CmdIo) async throws -> Bool {
        guard commands.allSatisfy(Self.supports) else { return io.err("Operation unsupported by the native tiling MVP") }
        guard let target = NativeCommandTargetFence(commands, env: env,
            defaultFocus: runtime.focus.requested.liveOrNil, layouts: runtime.workspaceBackend.nativeLayouts) else {
            return io.err("Native command target is not an observed active desktop")
        }
        runtime.workspaceBackend.observation?.requestRead(event: "nativeCommand")
        // Bounded readiness wait, with no additional native queries. Reconciliation
        // is owned by the event pipeline; newer events can supersede it safely.
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            if ready { break }
            if case .unavailable = runtime.workspaceBackend.observation?.inventory.status { break }
        }
        guard ready else { return io.err("Native tiling is not ready: \(status)") }
        guard target.matches(runtime.workspaceBackend.nativeLayouts, defaultFocus: runtime.focus.requested.liveOrNil) else {
            return io.err("Native command cancelled because its target changed during reconciliation")
        }
        guard hasManagedNativeFocus || commands.allSatisfy({
            $0 is DoctorCommand || $0 is ReloadConfigCommand || $0 is ModeCommand ||
                $0.args.windowId != nil || env.windowId != nil
        }) else { return io.err("The frontmost window is not managed by native tiling; use an eligible explicit --window-id") }
        let validate: @MainActor @Sendable () -> Bool = {
            target.matches(runtime.workspaceBackend.nativeLayouts,
                defaultFocus: runtime.focus.requested.liveOrNil, allowDefaultFocusChanges: true)
        }
        let result = try await NativeTilingCommandScope.$validateTarget.withValue(validate) {
            try await NativeTilingCommandScope.$active.withValue(true) {
                try await commands.runCmdSeq(env, io)
            }
        }
        if result {
            guard validate() else { return io.err("Native command target changed before completion") }
            if commands.contains(where: { $0 is FocusCommand }) {
                focus.windowOrNil?.nativeFocus()
            } else {
                runtime.workspaceBackend.observation?.requestRead(event: "nativeCommandCompleted")
            }
        }
        return result
    }
}
