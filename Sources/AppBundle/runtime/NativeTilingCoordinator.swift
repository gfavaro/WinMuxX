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
        guard !missionControl, NSEvent.pressedMouseButtons == 0 else {
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
                Task { @MainActor [weak owner] in
                    guard let owner else { return }
                    owner.withValue {
                        MacApp.cancelPendingFocus()
                        if released { owner.workspaceBackend.observation?.requestRead(event: "nativeMouseReleased") }
                        else { owner.workspaceBackend.nativeWriteAuthority.invalidate() }
                    }
                }
            }
        }
        if !shortcutsInstalled {
            shortcutsInstalled = true
            try? await activateMode(mainModeId, runCallbacks: false)
        }
        let targets = Set(snapshot.reconciliationSpaceIDs ?? snapshot.displays.map(\.activeSpaceID))
        for display in snapshot.displays where targets.contains(display.activeSpaceID) {
            guard generation == version,
                  let workspace = backend.nativeLayouts.activeWorkspace(on: display.identifier) else { continue }
            do { try await workspace.layoutWorkspace() }
            catch { status = "Native layout suspended: \(error)"; backend.nativeWriteAuthority.invalidate(); ready = false; return }
        }
        await backend.nativePersistence.save(backend.nativeLayouts)
        guard generation == version else { return }
        ready = true
        hasCompletedInitialLayout = true
        status = "Native tiling active"
        updateTrayText()
        WindowBorderController.shared.refresh()
    }

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
                 is BalanceSizesCommand, is SplitCommand, is SwapWithMasterCommand: return true
            case let command as MoveCommand: return command.args.boundaries == .workspace
            case let command as FocusCommand:
                return command.args.boundaries == .workspace && command.args.boundariesAction != .wrapAroundAllMonitors
            case let command as WorkspaceLayoutCommand:
                return command.args.layouts.val.allSatisfy { $0 == .dwindle || $0 == .master }
            case let command as LayoutCommand:
                return !command.args.forNextDetectedWindow && command.args.toggleBetween.val.allSatisfy {
                    [.tiles, .h_tiles, .v_tiles, .horizontal, .vertical, .auto, .tiling, .floating].contains($0)
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
