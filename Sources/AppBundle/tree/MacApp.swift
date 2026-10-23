import AppKit
import Common
import PrivateApi

// Potential alternative implementation
// https://github.com/swiftlang/swift-evolution/blob/main/proposals/0392-custom-actor-executors.md
// (only available since macOS 14)
final class MacApp: AbstractApp {
    /*conforms*/ let pid: Int32
    /*conforms*/ let rawAppBundleId: String?
    let appId: KnownBundleId?
    let nsApp: NSRunningApplication
    let isAccessoryApp: Bool
    private let axApp: ThreadGuardedValue<AXUIElement>
    /// Second app element with a much shorter messaging timeout, for the focused-window query
    /// that fronts every refresh session: when the app is too busy to answer quickly, the
    /// session must leave confirmed focus untouched instead of treating a timeout as no focus.
    private let axAppFastTimeout: ThreadGuardedValue<AXUIElement>
    private let appAxSubscriptions: ThreadGuardedValue<[AxSubscription]> // keep subscriptions in memory
    private let windows: ThreadGuardedValue<[UInt32: AxWindow]> = .init([:])
    // Retain the destroyed element only until AX stops enumerating it. This
    // prevents a late/stale AXWindows response from resurrecting a closed node.
    private let destroyedWindows: ThreadGuardedValue<[UInt32: AXUIElement]> = .init([:])
    private let animatedSizes: ThreadGuardedValue<[UInt32: (session: UUID, size: CGSize)]> = .init([:])
    private var windowsCount = 0
    var lastNativeFocusedWindowId: UInt32? = nil
    private var thread: Thread?
    private var setFrameJobs: [UInt32: RunLoopJob] = [:]
    @MainActor private static var focusJob: RunLoopJob? = nil

    /*conforms*/ var name: String? { nsApp.localizedName }
    /*conforms*/ var execPath: String? { nsApp.executableURL?.path }
    /*conforms*/ var bundlePath: String? { nsApp.bundleURL?.path }

    // todo think if it's possible to integrate this global mutable state to https://github.com/nikitabobko/WinMux/issues/1215
    //      and make deinitialization automatic in deinit
    @MainActor static var allAppsMap: [pid_t: MacApp] = [:]
    @MainActor static let registrationRetries = AppRegistrationRetries()
    @MainActor private static var wipPids: [pid_t: AwaitableOneTimeBroadcastLatch] = [:]

    private init(_ nsApp: NSRunningApplication, _ axApp: AXUIElement, _ axAppFastTimeout: AXUIElement, _ axSubscriptions: [AxSubscription], _ thread: Thread) {
        self.nsApp = nsApp
        self.isAccessoryApp = appDeclaresAccessory(nsApp.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary })
        self.axApp = .init(axApp)
        self.axAppFastTimeout = .init(axAppFastTimeout)
        self.pid = nsApp.processIdentifier
        self.rawAppBundleId = nsApp.bundleIdentifier
        self.appId = nsApp.bundleIdentifier.flatMap { KnownBundleId.init(rawValue: $0) }
        assert(!axSubscriptions.isEmpty)
        self.appAxSubscriptions = .init(axSubscriptions)
        self.thread = thread
    }

    @MainActor
    @discardableResult
    static func getOrRegister(_ nsApp: NSRunningApplication) async throws -> MacApp? {
        // Don't perceive any of the lock screen windows as real windows
        // Otherwise, false positive ax notifications might trigger that lead to gcWindows
        if nsApp.bundleIdentifier == lockScreenAppBundleId { return nil }
        let pid = nsApp.processIdentifier
        // AX requests crash if you send them to yourself
        if pid == myPid { return nil }

        if let existing = allAppsMap[pid] {
            if !existing.nsApp.isTerminated, existing.nsApp.launchDate == nsApp.launchDate { return existing }
            await existing.destroy()
        }
        try checkCancellation()
        if let wip = wipPids[pid] {
            try await wip.await()
            return allAppsMap[pid]
        }
        let process = RegistrationProcess(pid: pid, launchDate: nsApp.launchDate, fallbackIdentity: ObjectIdentifier(nsApp))
        guard registrationRetries.canAttempt(process) else { return nil }
        // Share a single registration attempt with current waiters. If it fails,
        // a later refresh can retry without spinning inside this call.
        let wip = AwaitableOneTimeBroadcastLatch()
        wipPids[pid] = wip

        let thread = Thread {
            $axTaskLocalAppThreadToken.withValue(AxAppThreadToken(pid: pid, idForDebug: nsApp.idForDebug)) {
                let axApp = AXUIElementCreateApplication(nsApp.processIdentifier)
                // Cap AX round-trips to this app at 1s instead of the 6s global default,
                // so a busy/unresponsive app can't stall window operations for seconds.
                AXUIElementSetMessagingTimeout(axApp, 1.0)
                let axAppFastTimeout = AXUIElementCreateApplication(nsApp.processIdentifier)
                AXUIElementSetMessagingTimeout(axAppFastTimeout, MacApp.focusedWindowQueryTimeout)
                let handlers: HandlerToNotifKeyMapping = [
                    (refreshObs, [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]),
                ]
                let job = RunLoopJob()
                let subscriptions = (try? AxSubscription.bulkSubscribe(nsApp, axApp, job, handlers)) ?? []
                let isGood = !subscriptions.isEmpty
                let app = isGood ? MacApp(nsApp, axApp, axAppFastTimeout, subscriptions, Thread.current) : nil
                Task { @MainActor in
                    if nsApp.isTerminated {
                        if let app { await app.destroy() }
                        registrationRetries.cancel(pid: pid)
                    } else {
                        allAppsMap[pid] = app
                        if app != nil { registrationRetries.cancel(pid: pid) }
                        else {
                            registrationRetries.failed(process) {
                                guard !nsApp.isTerminated else { registrationRetries.cancel(pid: pid); return }
                                if (try? await getOrRegister(nsApp)) != nil {
                                    scheduleRefreshSession(.globalObserver("registrationRetry"))
                                }
                            }
                        }
                    }
                    wipPids[pid] = nil
                    await wip.signalToAll()
                }
                if isGood {
                    CFRunLoopRun()
                }
            }
        }
        thread.name = "AxAppThread \(nsApp.idForDebug)"
        thread.start()

        try await wip.await()
        return allAppsMap[pid]
    }

    func closeAndUnregisterAxWindow(_ windowId: UInt32) {
        if serverArgs.isReadOnly { return }
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        _ = withWindowAsync(windowId) { [windows] window, job in
            guard let closeButton = window.get(Ax.closeButtonAttr) else { return }
            if measuredAXOperation(.axAction, { AXUIElementPerformAction(closeButton.cast, kAXPressAction as CFString) }) == .success {
                windows.threadGuarded.removeValue(forKey: windowId)
            }
        }
    }

    func pressCloseButton(_ windowId: UInt32) async throws -> Bool {
        if serverArgs.isReadOnly { return false }
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        return try await withWindow(windowId) { window, job in
            guard let closeButton = window.get(Ax.closeButtonAttr) else { return false }
            return measuredAXOperation(.axAction, { AXUIElementPerformAction(closeButton.cast, kAXPressAction as CFString) }) == .success
        } ?? false
    }

    func containsAxWindow(_ windowId: UInt32) async throws -> Bool {
        try await thread?.runInLoop { [axApp] job in
            axApp.threadGuarded.findAxWindow(windowId: windowId) != nil
        } ?? false
    }

    func getAxSize(_ windowId: UInt32) async throws -> CGSize? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.sizeAttr)
        }
    }

    /// How long the focused-window query may block a refresh session. Deliberately much shorter
    /// than the general 1s cap: this query fronts every session (including every hotkey), and
    /// on timeout there is an accurate fallback (see getFocusedWindow).
    static let focusedWindowQueryTimeout: Float = 0.25

    private enum FocusedWindowQuery {
        case window(UInt32)
        case noFocusedWindow
        case timedOut
    }

    private func queryFocusedWindowId() async throws -> FocusedWindowQuery {
        try await thread?.runInLoop { [nsApp, axAppFastTimeout, windows] job -> FocusedWindowQuery in
            if AXReadBudget.current?.permits(nsApp.processIdentifier) == false { return .timedOut }
            var raw: AnyObject?
            let error = AXUIElementCopyAttributeValue(axAppFastTimeout.threadGuarded, kAXFocusedWindowAttribute as CFString, &raw)
            AXReadBudget.current?.record(error, pid: nsApp.processIdentifier)
            switch error {
                case .success:
                    guard let raw else { return .noFocusedWindow }
                    let element = raw as! AXUIElement
                    // Fresh elements use the 6s global default; bound follow-up traffic like
                    // every other window element.
                    AXUIElementSetMessagingTimeout(element, 1.0)
                    guard let windowId = element.containingWindowId(),
                          let registered = try windows.threadGuarded.getOrRegisterAxWindow(windowId: windowId, element, nsApp, job)
                    else { return .noFocusedWindow }
                    return .window(registered.windowId)
                case .cannotComplete:
                    return .timedOut
                default:
                    return .noFocusedWindow
            }
        } ?? .noFocusedWindow
    }

    // todo merge together with detectNewWindows
    func getFocusedWindow() async throws -> Window? {
        switch try await queryFocusedWindowId() {
            case .window(let windowId):
                return try await MacWindow.getOrRegister(windowId: windowId, macApp: self)
            case .noFocusedWindow:
                return nil
            case .timedOut:
                throw NativeFocusUnknown()
        }
    }

    @MainActor func nativeFocus(_ windowId: UInt32, forceRaise: Bool = false) {
        if serverArgs.isReadOnly || !TrayMenuModel.shared.isEnabled || WindowRecoveryController.shared.isTerminating { return }
        MacApp.focusJob?.cancel()
        // Performance optimization. If possible avoid doing AX requests
        // (important for apps which are slow at responding even such basic AX requests. E.g. Godot)
        // Beware of the macOS bug: https://github.com/nikitabobko/WinMux/issues/101
        let useActivationOnly = !forceRaise && (!NSScreen.screensHaveSeparateSpaces || monitors.count == 1) &&
            shouldUseActivationOnlyForNativeFocus(
                targetWindowId: windowId,
                lastNativeFocusedWindowId: lastNativeFocusedWindowId,
                logicalWindowsCount: logicalWindowCount,
            )
        debugFocusLog(
            "MacApp.nativeFocus app=\(nsApp.localizedName ?? rawAppBundleId ?? String(pid)) target=\(windowId) lastNative=\(lastNativeFocusedWindowId?.description ?? "nil") logicalWindowsCount=\(logicalWindowCount) windowsCount=\(windowsCount) strategy=\(useActivationOnly ? "activate" : "ax-focus")"
        )
        if useActivationOnly
        {
            nsApp.activate(options: .activateIgnoringOtherApps)
        } else {
            MacApp.focusJob = withWindowAsync(windowId) { [nsApp, axApp] window, job in
                try job.checkCancellation()
                _ = measuredAXOperation(.axWrite, { AXUIElementSetAttributeValue(axApp.threadGuarded, kAXFocusedWindowAttribute as CFString, window) })
                try job.checkCancellation()
                // Raise firstly to make sure that by the time we activate the app, the window would be already on top
                window.set(Ax.isMainAttr, true)
                try job.checkCancellation()
                let raiseError = measuredAXOperation(.axAction, { AXUIElementPerformAction(window, kAXRaiseAction as CFString) })
                AXWindowOperation.current?.record(raiseError, from: ObjectIdentifier(window))
                try job.checkCancellation()
                nsApp.activate(options: .activateIgnoringOtherApps)
            }
        }
    }

    @MainActor static func cancelPendingFocus() {
        focusJob?.cancel()
        focusJob = nil
    }

    @MainActor
    func cancelPendingFrameWrites() {
        for job in setFrameJobs.values { job.cancel() }
        setFrameJobs.removeAll()
    }

    @MainActor
    func setAxFrame(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?) {
        guard !WindowRecoveryController.shared.suppressAutomaticFrameWrites else { return }
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { [axApp, animatedSizes] window, job in
            animatedSizes.threadGuarded[windowId] = nil
            try setFrame(window, app: axApp.threadGuarded, topLeft, size, job)
        }
    }

    @MainActor
    func setAnimatedAxFrame(_ windowId: UInt32, _ frame: CGRect, session: UUID) {
        guard !WindowRecoveryController.shared.suppressAutomaticFrameWrites else { return }
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { [axApp, animatedSizes] window, job in
            // Intermediate steps need no readback or minimum-size confirmation.
            // Finish both writes of a started step; cancellation drops queued steps.
            try disableAnimations(app: axApp.threadGuarded, job) {
                if animatedSizes.threadGuarded[windowId]?.session != session || animatedSizes.threadGuarded[windowId]?.size != frame.size {
                    let accepted = window.set(Ax.sizeAttr, frame.size)
                    animatedSizes.threadGuarded[windowId] = accepted ? (session, frame.size) : nil
                }
                window.set(Ax.topLeftCornerAttr, frame.origin)
            }
        }
    }

    func setAxFrameBlocking(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?, positionFirst: Bool = false) async throws {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        try await withWindow(windowId) { [axApp, animatedSizes] window, job in
            animatedSizes.threadGuarded[windowId] = nil
            try setFrame(window, app: axApp.threadGuarded, topLeft, size, job, positionFirst: positionFirst, traceWindowId: windowId)
        }
    }

    func getAxWindowsCount() async throws -> Int? {
        try await thread?.runInLoop { [axApp] job in
            axApp.threadGuarded.discoverAxWindows()?.count
        }
    }

    func restartWindowIdentities() async throws -> [(UInt32, RestartWindowIdentity)] {
        guard let bundleId = rawAppBundleId else { return [] }
        let launchDate = nsApp.launchDate
        let pid = pid
        guard let thread else { return [] }
        return try await thread.runInLoop { [axApp] job -> [(UInt32, RestartWindowIdentity)] in
            (axApp.threadGuarded.discoverAxWindows() ?? []).map { id, window in
                (id, RestartWindowIdentity(bundleId: bundleId, pid: pid,
                    launchDate: launchDate, title: window.get(Ax.titleAttr) ?? "",
                    documentURL: window.get(Ax.documentAttr),
                    accessibilityIdentifier: window.get(Ax.identifierAttr)))
            }
        }
    }

    func getRestartWindowIdentity(_ windowId: UInt32) async throws -> RestartWindowIdentity? {
        guard let bundleId = rawAppBundleId else { return nil }
        let launchDate = nsApp.launchDate
        let pid = pid
        return try await withWindow(windowId) { window, _ in
            RestartWindowIdentity(bundleId: bundleId, pid: pid, launchDate: launchDate,
                title: window.get(Ax.titleAttr) ?? "", documentURL: window.get(Ax.documentAttr),
                accessibilityIdentifier: window.get(Ax.identifierAttr))
        }
    }

    @MainActor
    private var logicalWindowCount: Int {
        var result = 0
        for window in MacWindow.allWindows where window.macApp === self {
            result += 1
            if result > 1 {
                return result
            }
        }
        return result
    }

    func getAxRect(_ windowId: UInt32) async throws -> Rect? {
        try await withWindow(windowId) { window, job in
            guard let topLeftCorner = window.get(Ax.topLeftCornerAttr) else { return nil }
            guard let size = window.get(Ax.sizeAttr) else { return nil }
            return Rect(topLeftX: topLeftCorner.x, topLeftY: topLeftCorner.y, width: size.width, height: size.height)
        }
    }

    func isWindowHeuristic(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?) async throws -> Bool {
        return try await withWindow(windowId) { [nsApp, axApp, appId] window, job in
            window.isWindowHeuristic(axApp: axApp.threadGuarded, appId, nsApp.activationPolicy, windowLevel)
        } == true
    }

    func getAxUiElementWindowType(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?) async throws -> AxUiElementWindowType {
        return try await withWindow(windowId) { [nsApp, axApp, appId, isAccessoryApp] window, job in
            window.getWindowType(axApp: axApp.threadGuarded, appId, nsApp.activationPolicy, windowLevel, accessory: isAccessoryApp)
        } ?? .window
    }

    func isDialogHeuristic(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?) async throws -> Bool {
        try await withWindow(windowId) { [appId, isAccessoryApp] window, job in
            window.isDialogHeuristic(appId, windowLevel, accessory: isAccessoryApp)
        } == true
    }

    func setNativeFullscreen(_ windowId: UInt32, _ value: Bool) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { window, job in
            window.set(Ax.isFullscreenAttr, value)
        }
    }

    func setNativeMinimized(_ windowId: UInt32, _ value: Bool) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { window, job in
            window.set(Ax.minimizedAttr, value)
        }
    }

    func dumpWindowAxInfo(windowId: UInt32) async throws -> [String: Json] {
        try await withWindow(windowId) { window, job in
            dumpAxRecursive(window, .window)
        } ?? [:]
    }

    func dumpAppAxInfo() async throws -> [String: Json] {
        try await thread?.runInLoop { [axApp] job in
            dumpAxRecursive(axApp.threadGuarded, .app)
        } ?? [:]
    }

    func getAxTitle(_ windowId: UInt32) async throws -> String? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.titleAttr)
        }
    }

    func readNativeState(_ windowId: UInt32) async throws -> (fullscreen: Bool, minimized: Bool)? {
        try await withWindow(windowId) { window, _ in
            let fullscreen = try window.read(Ax.isFullscreenAttr).get() ?? false
            let minimized = fullscreen ? false : try window.read(Ax.minimizedAttr).get() ?? false
            return (fullscreen, minimized)
        }
    }

    func isMacosNativeFullscreen(_ windowId: UInt32) async throws -> Bool? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.isFullscreenAttr)
        }
    }

    func isMacosNativeMinimized(_ windowId: UInt32) async throws -> Bool? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.minimizedAttr)
        }
    }

    /// Cooperative cancellation deadline for one app's window refresh. A CPU-starved
    /// app answers each AX message only at the messaging timeout, so its enumeration can take
    /// (windows × timeout); every other app's layout would wait behind it. Cancellation skips
    /// remaining reads, then falls back to current model windows. An AX call already in flight
    /// must finish or time out before the thread can acknowledge cancellation.
    private static let singleAppRefreshDeadline: Duration = .milliseconds(1500)

    @MainActor
    private static func refreshAppAndGetAliveWindowIdsWithDeadline(
        _ nsApp: NSRunningApplication,
        frontmostAppBundleId: String?,
    ) async throws -> [UInt32] {
        let pid = nsApp.processIdentifier
        let work = Task { @MainActor () -> [UInt32] in
            guard let app = try await MacApp.getOrRegister(nsApp) else { return [] }
            return try await app.refreshAndGetAliveWindowIds(frontmostAppBundleId: frontmostAppBundleId)
        }
        let deadline = Task { @MainActor in
            try? await Task.sleep(for: singleAppRefreshDeadline)
            work.cancel()
        }
        defer { deadline.cancel() }
        return try await withTaskCancellationHandler {
            do {
                return try await work.value
            } catch is CancellationError {
                // Propagate if the whole refresh session was cancelled; otherwise the deadline
                // fired — report the model's current windows for this app as alive.
                try checkCancellation()
                return MacWindow.allWindows.filter { $0.macApp.pid == pid }.map(\.windowId)
            }
        } onCancel: {
            work.cancel()
        }
    }

    @MainActor
    static func refreshAllAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> [MacApp: [UInt32]] {
        // Unit tests use TestApp/TestWindow. Enumerating the runner's real desktop
        // can feed native AX elements into the mock-only attribute decoder.
        guard !isUnitTest else { return [:] }
        for (_, app) in MacApp.allAppsMap { // gc dead apps
            try checkCancellation()
            if app.nsApp.isTerminated {
                await app.destroy()
            }
        }
        return try await withThrowingTaskGroup(of: (pid_t, [UInt32]).self, returning: [MacApp: [UInt32]].self) { group in
            func refreshTheApp(_ nsApp: NSRunningApplication) {
                group.addTask { @Sendable @MainActor in
                    (
                        nsApp.processIdentifier,
                        try await refreshAppAndGetAliveWindowIdsWithDeadline(nsApp, frontmostAppBundleId: frontmostAppBundleId)
                    )
                }
            }
            // Register new apps
            for nsApp in NSWorkspace.shared.runningApplications {
                try checkCancellation()
                if nsApp.activationPolicy == .regular {
                    refreshTheApp(nsApp)
                }
            }
            for (_, app) in MacApp.allAppsMap {
                try checkCancellation()
                // "About this Mac" window, TouchID, and a lot of other utility windows
                // We don't monitor them actively as we do for regular apps, but if a window of one of those utility
                // apps got focused it will end up in allAppsMap
                if app.nsApp.activationPolicy != .regular {
                    refreshTheApp(app.nsApp)
                }
            }
            var result: [MacApp: [UInt32]] = [:]
            for try await (pid, windowIds) in group {
                if let app = MacApp.allAppsMap[pid] {
                    result[app] = windowIds
                }
            }
            return result
        }
    }

    func unregisterDestroyedWindow(_ windowId: UInt32) async throws {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        try await thread?.runInLoop { [windows, destroyedWindows, animatedSizes] _ in
            animatedSizes.threadGuarded[windowId] = nil
            if let removed = windows.threadGuarded.removeValue(forKey: windowId) {
                destroyedWindows.threadGuarded[windowId] = removed.ax
            }
        }
    }

    private func refreshAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> [UInt32] {
        if nsApp.isTerminated {
            await destroy()
            return []
        }
        guard let thread else { return [] }
        let (alive, dead) = try await thread.runInLoop { [nsApp, windows, axApp, destroyedWindows] (job) -> ([UInt32], [UInt32]) in
            var alive: [UInt32: AxWindow] = windows.threadGuarded
            var dead = [UInt32: AxWindow]()
            // Second line of defence against lock screen. See the first line of defence: closedWindowsCache
            // Second and third lines of defence are technically needed only to avoid potential flickering
            if frontmostAppBundleId != lockScreenAppBundleId {
                (alive, dead) = try alive.partition {
                    try job.checkCancellation()
                    if !isUnitTest && !winmux_window_exists($0.key) { return false }
                    let (windowId, error) = $0.value.ax.containingWindowIdWithError()
                    if windowId != nil { return true }
                    // .cannotComplete means the app didn't answer (CPU-starved or briefly
                    // unresponsive), not that the window is gone. Treating it as death made
                    // a busy app's windows get GC'd and later re-detected as new windows
                    // (losing their tree position). Keep them; a later refresh reconciles
                    // once the app responds or terminates.
                    return error == .cannotComplete
                }
            }

            let discovered = axApp.threadGuarded.discoverAxWindows()
            for (id, window) in discovered ?? [] {
                try job.checkCancellation()
                if !isUnitTest && !winmux_window_exists(id) { continue }
                if let destroyed = destroyedWindows.threadGuarded[id] {
                    if isDestroyedWindowElement(destroyed, window.cast) { continue }
                    destroyedWindows.threadGuarded.removeValue(forKey: id)
                }
                try alive.getOrRegisterAxWindow(windowId: id, window.cast, nsApp, job)
            }
            if let discovered {
                let reportedIds = Set(discovered.map { $0.windowId })
                for id in Array(destroyedWindows.threadGuarded.keys) where !reportedIds.contains(id) {
                    destroyedWindows.threadGuarded.removeValue(forKey: id)
                }
            }

            try job.checkCancellation()
            windows.threadGuarded = alive
            return (Array(alive.keys), Array(dead.keys))
        }
        try checkCancellation()
        windowsCount = alive.count
        for windowId in dead {
            setFrameJobs.removeValue(forKey: windowId)?.cancel()
        }
        return alive
    }

    private func destroy() async {
        _ = await Task { @MainActor [pid] in _ = MacApp.allAppsMap.removeValue(forKey: pid) }.result
        for (_, job) in setFrameJobs {
            job.cancel()
        }
        setFrameJobs = [:]
        thread?.runInLoopAsync { [windows, destroyedWindows, animatedSizes, appAxSubscriptions, axApp, axAppFastTimeout] job in
            animatedSizes.destroy()
            appAxSubscriptions.destroy() // Destroy AX objects in reverse order of their creation
            windows.destroy()
            destroyedWindows.destroy()
            axAppFastTimeout.destroy()
            axApp.destroy()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        thread = nil // Disallow all future job submissions
    }

    private func withWindow<T>(_ windowId: UInt32, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> T?) async throws -> T? {
        try await thread?.runInLoop { [windows, axApp, nsApp, animatedSizes] job in
            if AXReadBudget.current?.permits(nsApp.processIdentifier) == false { throw AXReadFailure(code: .cannotComplete) }
            let value = try withRecoverableWindow(load: { replacing in
                try job.checkCancellation()
                if replacing {
                    windows.threadGuarded.removeValue(forKey: windowId)
                    animatedSizes.threadGuarded[windowId] = nil
                }
                return try windows.threadGuarded.getOrRegisterAxWindow(
                    windowId: windowId, from: axApp.threadGuarded, nsApp, job)
            }, identify: { (window: AxWindow) in ObjectIdentifier(window.ax) }, body: { window in try body(window.ax, job) })
            if AXReadBudget.current?.permits(nsApp.processIdentifier) == false { throw AXReadFailure(code: .cannotComplete) }
            return value
        }
    }

    private func withWindowAsync(_ windowId: UInt32, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> ()) -> RunLoopJob {
        thread?.runInLoopAsync { [windows, axApp, nsApp, animatedSizes] job in
            do {
                let _: Void? = try withRecoverableWindow(load: { replacing in
                    try job.checkCancellation()
                    if replacing {
                        windows.threadGuarded.removeValue(forKey: windowId)
                        animatedSizes.threadGuarded[windowId] = nil
                    }
                    return try windows.threadGuarded.getOrRegisterAxWindow(
                        windowId: windowId, from: axApp.threadGuarded, nsApp, job)
                }, identify: { (window: AxWindow) in ObjectIdentifier(window.ax) }, body: { window in try body(window.ax, job) })
            } catch {
                // Closed windows, cancelled jobs and failed AX requests are retried by refresh.
            }
        } ?? .cancelled
    }
}

func isDestroyedWindowElement(_ destroyed: AXUIElement?, _ discovered: AXUIElement) -> Bool {
    destroyed.map { CFEqual($0, discovered) } ?? false
}

func shouldUseActivationOnlyForNativeFocus(
    targetWindowId: UInt32,
    lastNativeFocusedWindowId: UInt32?,
    logicalWindowsCount: Int,
) -> Bool {
    lastNativeFocusedWindowId == targetWindowId || logicalWindowsCount == 1
}
