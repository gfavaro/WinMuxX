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

    /// Read once: after every app activation AppKit drops its cached answer and asks
    /// LaunchServices again, and the menu bar and sidebar read every window's app name.
    /*conforms*/ let name: String?
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
        self.name = nsApp.localizedName
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
        let pid = nsApp.processIdentifier
        // AX requests crash if you send them to yourself
        if pid == myPid { return nil }

        // A registered app was checked when it registered; only new ones need the lock screen check.
        if let existing = allAppsMap[pid] {
            switch appRegistrationDecision(existingTerminated: existing.nsApp.isTerminated,
                                           sameProcess: isSameRunningProcess(existing.nsApp, nsApp),
                                           incomingTerminated: { nsApp.isTerminated }) {
                case .reuse: return existing
                case .reject: return nil
                case .replace: await existing.destroy()
            }
        } else if nsApp.isTerminated {
            return nil
        }
        if isLockScreenApp(nsApp) { return nil }
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
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        _ = withWindowAsync(windowId) { [windows] window, job in
            guard let closeButton = window.get(Ax.closeButtonAttr) else { return }
            if measuredAXOperation(.axAction, { AXUIElementPerformAction(closeButton.cast, kAXPressAction as CFString) }) == .success {
                windows.threadGuarded.removeValue(forKey: windowId)
            }
        }
    }

    func pressCloseButton(_ windowId: UInt32) async throws -> Bool {
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

    /// Whether a frame write could reach the window now, for `doctor`. A cached element counts only
    /// if it still answers for this window. Unreachable means the app answered every lookup and none
    /// was this window; the first lookup it does not answer ends the check as unknown, so a slow app
    /// costs one timeout. The registered element keeps its operational timeout; only the fresh
    /// copies read here use the shorter diagnostic one, because the timeout stays on an element.
    func axWindowReachability(_ windowId: UInt32) async -> AxWindowReachability {
        guard let thread else { return .appRetired }
        let timeout = axDiagnosticTimeout
        do {
            return try await thread.runInLoop { [windows, axApp] job -> AxWindowReachability in
                if let cached = windows.threadGuarded[windowId]?.ax {
                    let (resolved, error) = cached.containingWindowIdWithError()
                    if resolved == windowId { return .reachable }
                    if error == .cannotComplete { return .unknown("the app did not answer") }
                }
                let unanswered = AxWindowReachability.unknown("the app did not answer")
                for source in [kAXWindowsAttribute, kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
                    try job.checkCancellation()
                    var raw: CFTypeRef?
                    if AXUIElementCopyAttributeValue(axApp.threadGuarded, source as CFString, &raw) == .cannotComplete { return unanswered }
                    let elements = (raw as? [AnyObject]) ?? raw.map { [$0 as AnyObject] } ?? []
                    for element in elements where CFGetTypeID(element) == AXUIElementGetTypeID() {
                        let (resolved, error) = (element as! AXUIElement).containingWindowIdWithError(timeout: timeout)
                        if resolved == windowId { return .reachable }
                        if error == .cannotComplete { return unanswered }
                    }
                }
                return .unreachable
            }
        } catch {
            return .unknown("the check was interrupted")
        }
    }


    /// The app's raw AX window sources for `doctor`, before the window-id filter that
    /// discovery applies, so an element that maps to no or another window id is visible.
    func probeAxWindows(limit: Int = 12) async throws -> [AxWindowProbe] {
        try await thread?.runInLoop { [axApp] job in
            var result: [AxWindowProbe] = []
            do {
                // The app element keeps its operational timeout; window copies read here are fresh.
                let listed = try diagnosticRead(axApp.threadGuarded, kAXWindowsAttribute, into: &result, source: "AXWindows")
                let elements = (listed as? [AnyObject]) ?? []
                if elements.count > limit { result.append(AxWindowProbe(source: "AXWindows", failure: "\(elements.count) windows, first \(limit) shown")) }
                for (index, element) in elements.prefix(limit).enumerated() where CFGetTypeID(element) == AXUIElementGetTypeID() {
                    try job.checkCancellation()
                    result.append(try diagnosticProbe(element as! AXUIElement, "AXWindows[\(index)]"))
                }
                for (attribute, source) in [(kAXMainWindowAttribute, "AXMainWindow"), (kAXFocusedWindowAttribute, "AXFocusedWindow")] {
                    let value = try diagnosticRead(axApp.threadGuarded, attribute, into: &result, source: source)
                    if let value, CFGetTypeID(value) == AXUIElementGetTypeID() { result.append(try diagnosticProbe(value as! AXUIElement, source)) }
                }
            } catch {
                result.append(AxWindowProbe(source: "probe", failure: "stopped: the app stopped answering"))
            }
            return result
        } ?? []
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
                    guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return .noFocusedWindow }
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
        if !TrayMenuModel.shared.isEnabled || WindowRecoveryController.shared.isTerminating { return }
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
        debugLog(.focus, "MacApp.nativeFocus app=\(nsApp.localizedName ?? rawAppBundleId ?? String(pid)) target=\(windowId) lastNative=\(lastNativeFocusedWindowId?.description ?? "nil") logicalWindowsCount=\(logicalWindowCount) windowsCount=\(windowsCount) strategy=\(useActivationOnly ? "activate" : "ax-focus")"
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

    /// Restack a window without setting main/focused attributes or activating its app.
    @MainActor func raiseWithoutActivating(_ windowId: UInt32) async throws {
        try await withWindow(windowId) { window, job in
            try job.checkCancellation()
            let error = measuredAXOperation(.axAction) { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
            AXWindowOperation.current?.record(error, from: ObjectIdentifier(window))
        }
    }

    @MainActor func cancelFrameWrite(_ windowId: UInt32) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
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

    @MainActor
    /// False when nothing was written: the app object is retired or the window has no AX element.
    @discardableResult
    func setAxFrameBlocking(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?, positionFirst: Bool = false) async throws -> Bool {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        let written = try await withWindow(windowId) { [axApp, animatedSizes] window, job -> Bool in
            animatedSizes.threadGuarded[windowId] = nil
            try setFrame(window, app: axApp.threadGuarded, topLeft, size, job, positionFirst: positionFirst, traceWindowId: windowId)
            return true
        }
        return written == true
    }

    @MainActor
    func getAxRectForLayoutConfirmation(_ windowId: UInt32) async throws -> Rect? {
        return try await withWindow(windowId) { window, job in
            try job.checkCancellation()
            guard let point = window.get(Ax.topLeftCornerAttr), let size = window.get(Ax.sizeAttr) else { return nil }
            return Rect(topLeftX: point.x, topLeftY: point.y, width: size.width, height: size.height)
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
        pid: pid_t,
        frontmostAppBundleId: String?,
    ) async throws -> [UInt32] {
        let work = Task { @MainActor () -> [UInt32] in
            let registered = MacApp.allAppsMap[pid].flatMap { isSameRunningProcess($0.nsApp, nsApp) ? $0 : nil }
            let app = if let registered { registered } else { try await MacApp.getOrRegister(nsApp) }
            guard let app else { return [] }
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
        for (pid, app) in MacApp.allAppsMap { // gc dead apps
            try checkCancellation()
            // The cache answers without LaunchServices; confirm before destroying a running app's
            // object, which would leave its windows unable to move or park.
            if !RegularApplications.shared.isRunning(app.nsApp, pid: pid), app.nsApp.isTerminated {
                await app.destroy()
            }
        }
        return try await withThrowingTaskGroup(of: (pid_t, [UInt32]).self, returning: [MacApp: [UInt32]].self) { group in
            func refreshTheApp(_ nsApp: NSRunningApplication, pid: pid_t) {
                group.addTask { @Sendable @MainActor in
                    (pid, try await refreshAppAndGetAliveWindowIdsWithDeadline(nsApp, pid: pid, frontmostAppBundleId: frontmostAppBundleId))
                }
            }
            // Register new apps
            for (pid, nsApp) in RegularApplications.shared.byPid {
                try checkCancellation()
                refreshTheApp(nsApp, pid: pid)
            }
            for (pid, app) in MacApp.allAppsMap {
                try checkCancellation()
                // "About this Mac" window, TouchID, and a lot of other utility windows
                // We don't monitor them actively as we do for regular apps, but if a window of one of those utility
                // apps got focused it will end up in allAppsMap
                if !RegularApplications.shared.isRegular(pid) {
                    refreshTheApp(app.nsApp, pid: pid)
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

    @MainActor
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

    /// Retires this app object before any suspension: no new AX work is accepted, and the registry
    /// entry is removed only while it is still this object, so a late or repeated call cannot
    /// remove a replacement registered for the same pid.
    @MainActor
    func destroy() async {
        let retiring = thread
        thread = nil // Disallow all future job submissions
        if MacApp.allAppsMap[pid] === self { MacApp.allAppsMap.removeValue(forKey: pid) }
        for (_, job) in setFrameJobs {
            job.cancel()
        }
        setFrameJobs = [:]
        retiring?.runInLoopAsync { [windows, destroyedWindows, animatedSizes, appAxSubscriptions, axApp, axAppFastTimeout] job in
            animatedSizes.destroy()
            appAxSubscriptions.destroy() // Destroy AX objects in reverse order of their creation
            windows.destroy()
            destroyedWindows.destroy()
            axAppFastTimeout.destroy()
            axApp.destroy()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    /// A destroyed app object has no AX thread; windows still holding it cannot be read or moved.
    var isRetired: Bool { thread == nil }

    private func withWindow<T>(_ windowId: UInt32, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> T?) async throws -> T? {
        try await thread?.runInLoop { [windows, axApp, nsApp, animatedSizes] job in
            if AXReadBudget.current?.permits(nsApp.processIdentifier) == false { throw AXReadFailure(code: .cannotComplete) }
            let value = try Self.withRecoverableAxWindow(
                windowId, windows: windows, animatedSizes: animatedSizes, axApp: axApp, nsApp: nsApp, job, body)
            if AXReadBudget.current?.permits(nsApp.processIdentifier) == false { throw AXReadFailure(code: .cannotComplete) }
            return value
        }
    }

    private func withWindowAsync(_ windowId: UInt32, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> ()) -> RunLoopJob {
        thread?.runInLoopAsync { [windows, axApp, nsApp, animatedSizes] job in
            do {
                let _: Void? = try Self.withRecoverableAxWindow(
                    windowId, windows: windows, animatedSizes: animatedSizes, axApp: axApp, nsApp: nsApp, job, body)
            } catch {
                // Closed windows, cancelled jobs and failed AX requests are retried by refresh.
            }
        } ?? .cancelled
    }

    /// Runs `body` on the window's AX element; a stale element is dropped and reloaded once.
    /// Must be called on the app's AX thread.
    private static func withRecoverableAxWindow<T>(
        _ windowId: UInt32,
        windows: ThreadGuardedValue<[UInt32: AxWindow]>,
        animatedSizes: ThreadGuardedValue<[UInt32: (session: UUID, size: CGSize)]>,
        axApp: ThreadGuardedValue<AXUIElement>,
        nsApp: NSRunningApplication,
        _ job: RunLoopJob,
        _ body: (AXUIElement, RunLoopJob) throws -> T?,
    ) throws -> T? {
        try withRecoverableWindow(load: { replacing in
            try job.checkCancellation()
            if replacing {
                windows.threadGuarded.removeValue(forKey: windowId)
                animatedSizes.threadGuarded[windowId] = nil
            }
            return try windows.threadGuarded.getOrRegisterAxWindow(
                windowId: windowId, from: axApp.threadGuarded, nsApp, job)
        }, identify: { (window: AxWindow) in ObjectIdentifier(window.ax) }, body: { window in try body(window.ax, job) })
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

enum AppRegistrationDecision: Equatable {
    case reuse, reject, replace
}

/// What `getOrRegister` does with an app already registered for the pid. One process holds a pid at
/// a time, so a live registration is never evicted; a request carrying an ended process is refused.
/// `incomingTerminated` is a LaunchServices request, made only when the answer matters.
func appRegistrationDecision(existingTerminated: Bool, sameProcess: Bool, incomingTerminated: () -> Bool) -> AppRegistrationDecision {
    if !existingTerminated { return sameProcess || !incomingTerminated() ? .reuse : .reject }
    return incomingTerminated() ? .reject : .replace
}

/// Diagnostics wait less than window operations for an unresponsive app.
private let axDiagnosticTimeout: Float = 0.25

/// Thrown by `doctor`'s probe at the first read the app does not answer, so a slow app costs one timeout.
private struct DiagnosticReadUnanswered: Error {}

/// Reads one attribute for `doctor`; a failure other than "no answer" is recorded under `source`.
private func diagnosticRead(_ element: AXUIElement, _ attribute: String, into result: inout [AxWindowProbe], source: String) throws -> CFTypeRef? {
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    if status == .cannotComplete { throw DiagnosticReadUnanswered() }
    if status != .success, status != .noValue { result.append(AxWindowProbe(source: source, failure: status.repr)) }
    return status == .success ? value : nil
}

/// One window element for `doctor`. Every read stops the probe if the app does not answer.
private func diagnosticProbe(_ element: AXUIElement, _ source: String) throws -> AxWindowProbe {
    AXUIElementSetMessagingTimeout(element, axDiagnosticTimeout)
    let (windowId, error) = element.containingWindowIdWithError(timeout: axDiagnosticTimeout)
    if error == .cannotComplete { throw DiagnosticReadUnanswered() }
    func attribute(_ name: String) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        if status == .cannotComplete { throw DiagnosticReadUnanswered() }
        return status == .success ? value : nil
    }
    let origin = try attribute(kAXPositionAttribute).flatMap { axGeometryValue($0, .cgPoint, CGPoint.zero) }
    let size = try attribute(kAXSizeAttribute).flatMap { axGeometryValue($0, .cgSize, CGSize.zero) }
    return AxWindowProbe(source: source, windowId: windowId, idError: windowId == nil ? error.repr : nil,
        frame: origin.flatMap { origin in size.map { CGRect(origin: origin, size: $0) } },
        role: try attribute(kAXRoleAttribute) as? String, subrole: try attribute(kAXSubroleAttribute) as? String)
}
