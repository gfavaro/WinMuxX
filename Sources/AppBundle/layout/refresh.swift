import AppKit
import PrivateApi
import Common
import os

@MainActor
private var activeRefreshTask: Task<(), any Error>? { runtime.refresh.activeRefreshTask }

@MainActor
private var activeScheduledRefreshEvent: RefreshSessionEvent? { runtime.refresh.activeScheduledRefreshEvent }

@MainActor
private var activeScheduledRefreshGeneration: UInt64 {
    get { runtime.refresh.activeScheduledRefreshGeneration }
    set { runtime.refresh.activeScheduledRefreshGeneration = newValue }
}

@MainActor
private var scheduledRefreshOverrideForTests: (@MainActor @Sendable (RefreshSessionEvent, Bool) async throws -> Void)? {
    get { runtime.refresh.scheduledRefreshOverrideForTests }
    set { runtime.refresh.scheduledRefreshOverrideForTests = newValue }
}

@MainActor
private var refreshOverrideForTests: (@MainActor @Sendable () async throws -> Void)? {
    get { runtime.refresh.refreshOverrideForTests }
    set { runtime.refresh.refreshOverrideForTests = newValue }
}

@MainActor
private var normalizeLayoutReasonOverrideForTests: (@MainActor @Sendable () async throws -> Void)? {
    get { runtime.refresh.normalizeLayoutReasonOverrideForTests }
    set { runtime.refresh.normalizeLayoutReasonOverrideForTests = newValue }
}

/// Activation survives event coalescing and cancelled sessions until focus is reconciled.
struct RefreshActivationContext: Equatable, Sendable {
    let generation: UInt64
    let workspaceName: String
    let pid: Int32
    var selectionGeneration: UInt64 = 0

    func shouldRaise(currentWorkspace: String, nativeWindowId: UInt32?, logicalWindowId: UInt32?,
                     frontmostPid: Int32?, targetPid: Int32?) -> Bool {
        workspaceName != currentWorkspace && nativeWindowId != nil && nativeWindowId == logicalWindowId &&
            frontmostPid == pid && targetPid == pid
    }
}

@MainActor
private var activationGeneration: UInt64 {
    get { runtime.refresh.activationGeneration }
    set { runtime.refresh.activationGeneration = newValue }
}
@MainActor
private var pendingActivation: RefreshActivationContext? {
    get { runtime.refresh.pendingActivation }
    set { runtime.refresh.pendingActivation = newValue }
}

@MainActor
func recordRefreshActivation(workspaceName: String, pid: Int32) {
    activationGeneration += 1
    pendingActivation = RefreshActivationContext(generation: activationGeneration, workspaceName: workspaceName, pid: pid,
                                                 selectionGeneration: runtime.refresh.workspaceSelectionGeneration)
    if runtime.events.isRecording {
        runtime.events.record(.activationRecorded, source: .refresh, generation: activationGeneration,
                              workspaceID: Workspace.existing(byName: workspaceName)?.id, reason: "pid:\(pid)")
    }
    if runtime.refresh.windowlessActivationPid != pid { runtime.refresh.windowlessActivationPid = nil }
}

@MainActor
func pendingRefreshActivationForTests() -> RefreshActivationContext? { pendingActivation }

private func isAxGeometryRefreshEvent(_ event: RefreshSessionEvent) -> Bool {
    guard case .ax(let notif) = event else { return false }
    return notif == kAXMovedNotification as String || notif == kAXResizedNotification as String
}

private func shouldDropScheduledRefresh(_ newEvent: RefreshSessionEvent, activeEvent: RefreshSessionEvent?) -> Bool {
    guard isAxGeometryRefreshEvent(newEvent), let activeEvent else { return false }
    if isAxGeometryRefreshEvent(activeEvent) {
        return true
    }
    if case .resetManipulatedWithMouse = activeEvent {
        return true
    }
    return false
}

@MainActor
func shouldSyncFocusBackToMacOs(
    nativeFocused: Window?,
    frontmostActivationPolicy: NSApplication.ActivationPolicy?,
    frontmostPid: pid_t? = nil,
    windowlessActivationPid: pid_t? = runtime.refresh.windowlessActivationPid,
) -> Bool {
    if ignoresCrossWorkspaceActivation(nativeFocused) {
        switch refreshSessionEvent {
            case .socketServer, .hotkeyBinding, .menuBarButton: break
            case .globalObserver(let name) where name == "workspaceSwipe" || name == "workspaceOverviewSelection": break
            default: return false
        }
    }
    if nativeFocused?.participatesInWorkspaceFocus == false {
        return false
    }
    if nativeFocused == nil && frontmostActivationPolicy == .accessory {
        return false
    }
    // Another app was activated before it had a window, as when it launches: taking focus back
    // would open its window behind the old one, and its window's own event focuses it once known.
    // An app that has just closed its last window had windows when it was activated, so focus
    // still returns to the window WinMux keeps focused.
    if nativeFocused == nil, let frontmostPid, frontmostPid == windowlessActivationPid, frontmostPid != focus.windowOrNil?.app.pid {
        return false
    }
    return true
}

@MainActor
private var pendingRefreshRequest: RefreshRequest? {
    get { runtime.refresh.pendingRefreshRequest }
    set { runtime.refresh.pendingRefreshRequest = newValue }
}

/// Adds an event to the follow-up owed, keeping the most demanding of them.
@MainActor
private func queueRefreshFollowUp(_ event: RefreshSessionEvent, optimisticallyPreLayoutWorkspaces: Bool) {
    pendingRefreshRequest = pendingRefreshRequest.map {
        RefreshRequest(event: mergeRefreshEvents($0.event, event),
                       optimisticallyPreLayoutWorkspaces: $0.optimisticallyPreLayoutWorkspaces || optimisticallyPreLayoutWorkspaces)
    } ?? RefreshRequest(event: event, optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
}

/// When two refresh requests coalesce, keep the event whose session does more work, so the
/// follow-up session covers the requirements of every event that arrived while one was running.
private func mergeRefreshEvents(_ old: RefreshSessionEvent, _ new: RefreshSessionEvent) -> RefreshSessionEvent {
    // Parking repair is a placement-only pass. Never let it replace a pending
    // focus/tab/activation reconciliation, including one with the same cost score.
    if case .onWindowParkingDrift = new { return old }
    if case .onWindowParkingDrift = old { return new }
    func score(_ e: RefreshSessionEvent) -> Int {
        // Re-parking hidden windows after a wake has no other trigger, and it used to tie
        // with (and lose to) the Space and mouse events that arrive right after a wake.
        // From WinMux PR #30 by Ilya Kudravets.
        (e.requiresHiddenWindowsReassertion ? 4 : 0) +
            (e.requiresWindowRefreshBarrier ? 2 : 0) + (e.canReuseLastAppliedWindowFrames ? 0 : 1)
    }
    return score(new) >= score(old) ? new : old
}

@MainActor
func scheduleRefreshSession(
    _ event: RefreshSessionEvent,
    optimisticallyPreLayoutWorkspaces: Bool = false,
    recordsActivation: Bool = true,
) {
    runtime.events.record(.refreshRequested, source: .refresh, generation: activeScheduledRefreshGeneration)
    // Startup owns the first enumeration and tree restoration. AX notifications from
    // newly subscribed apps must not start a second enumeration alongside it.
    guard isUnitTest || isWinMuxRuntimeReady else { return }
    if recordsActivation, case .globalObserver(let notification) = event,
       notification == NSWorkspace.didActivateApplicationNotification.rawValue,
       let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
        recordRefreshActivation(workspaceName: focus.workspace.name, pid: pid)
    }
    if shouldDropScheduledRefresh(event, activeEvent: activeScheduledRefreshEvent) ||
        shouldDropScheduledRefresh(event, activeEvent: pendingRefreshRequest?.event)
    {
        debugLog(.focus, "scheduleRefreshSession dropped event=\(event) active=\(activeScheduledRefreshEvent?.description ?? "nil") pending=\(pendingRefreshRequest?.event.description ?? "nil")")
        return
    }
    // Coalesce instead of cancel-and-restart: cancelling the in-flight session on every event
    // meant that during event bursts (app launch, window storms) the refresh kept restarting
    // and never completed until the burst quieted down. Let the active session finish, then
    // run a single follow-up session on behalf of all events that arrived in the meantime.
    if activeRefreshTask != nil {
        runtime.events.record(.refreshCoalesced, source: .refresh, generation: activeScheduledRefreshGeneration)
        queueRefreshFollowUp(event, optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
        return
    }
    // A light session may cancel the active task while leaving a heavier request pending.
    queueRefreshFollowUp(event, optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
    let request = pendingRefreshRequest!
    pendingRefreshRequest = nil
    activeScheduledRefreshGeneration += 1
    let generation = activeScheduledRefreshGeneration
    let override = scheduledRefreshOverrideForTests
    let task = runtime.throwingTask {
        defer {
            // Generation mismatch means someone took over (light session, test setup); they are
            // responsible for the next refresh, so don't drain the pending request from here.
            if activeScheduledRefreshGeneration == generation {
                runtime.refresh.active = nil
                if let pending = pendingRefreshRequest {
                    pendingRefreshRequest = nil
                    scheduleRefreshSession(pending.event, optimisticallyPreLayoutWorkspaces: pending.optimisticallyPreLayoutWorkspaces,
                                           recordsActivation: false)
                }
            }
        }
        do {
            try checkCancellation()
            if let override {
                try await override(request.event, request.optimisticallyPreLayoutWorkspaces)
            } else {
                try await runRefreshSessionBlocking(request.event, optimisticallyPreLayoutWorkspaces: request.optimisticallyPreLayoutWorkspaces)
            }
            runtime.events.record(.refreshCompleted, source: .refresh, generation: generation)
        } catch is CancellationError {
            runtime.events.record(.cancelled, source: .refresh, generation: generation)
            return
        } catch {
            recordSessionFailure(error, request.event)
            throw error
        }
    }
    runtime.refresh.active = ActiveRefresh(task: task, event: request.event)
}

@MainActor
func runRefreshSessionBlocking(_ event: RefreshSessionEvent, layoutWorkspaces: Bool = true,
                               optimisticallyPreLayoutWorkspaces: Bool = false) async throws {
    let stateStore = runtime.publicState
    if stateStore.transactionDepth == 0, hasPublicStateSubscribers { _ = publicStateSnapshot() }
    stateStore.transactionDepth += 1
    defer { stateStore.transactionDepth -= 1; requestPublicStateUpdate(structural: true) }
    try await AXReadBudget.$current.withValue(AXReadBudget()) {
        try await performRefreshSession(event, layoutWorkspaces: layoutWorkspaces,
                                        optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
    }
    // Settled topology work can coalesce with another native event. Its pending
    // state belongs to the display owner, rather than the winning event's name.
    if layoutWorkspaces, event.requiresWindowRefreshBarrier { runSettledDisplayChangeHook() }
}

@MainActor
func runCommandSession<T>(_ event: RefreshSessionEvent, _ token: RunSessionGuard,
                          isQuery: Bool, shouldSchedulePostRefresh: Bool,
                          body: @MainActor () async throws -> T) async throws -> T {
    if isQuery {
        return try await AXReadBudget.$current.withValue(AXReadBudget(), operation: body)
    }
    return try await runLightSession(event, token, shouldSchedulePostRefresh: shouldSchedulePostRefresh, body: body)
}

@MainActor
func runLightSession<T>(_ event: RefreshSessionEvent, _ token: RunSessionGuard,
                       shouldSchedulePostRefresh: Bool = true,
                       body: @MainActor () async throws -> T) async throws -> T {
    let stateStore = runtime.publicState
    if stateStore.transactionDepth == 0, hasPublicStateSubscribers { _ = publicStateSnapshot() }
    stateStore.transactionDepth += 1
    defer {
        stateStore.transactionDepth -= 1
        // Command sequences mark their own changed domains. UI/gesture bodies may
        // mutate the tree directly and must invalidate structural snapshots here.
        let structural: Bool = switch event {
            case .hotkeyBinding, .socketServer, .onModeChanged: false
            default: true
        }
        requestPublicStateUpdate(structural: structural)
    }
    return try await AXReadBudget.$current.withValue(AXReadBudget()) {
        try await performLightSession(event, token, shouldSchedulePostRefresh: shouldSchedulePostRefresh, body: body)
    }
}

/// A light session nobody waits for, as a click or a notification starts. Its failure has no
/// caller to report to and the next refresh repairs what it left, so it is only recorded.
@MainActor
func runUnattendedLightSession<T>(_ event: RefreshSessionEvent, _ token: RunSessionGuard,
                                  shouldSchedulePostRefresh: Bool = true,
                                  body: @MainActor () async throws -> T) async {
    do {
        _ = try await runLightSession(event, token, shouldSchedulePostRefresh: shouldSchedulePostRefresh, body: body)
    } catch {
        recordSessionFailure(error, event)
    }
}

private let sessionLog = Logger(subsystem: winMuxAppId, category: "session")

/// Cancellation is how a newer session takes over, not a failure.
func recordSessionFailure(_ error: any Error, _ event: RefreshSessionEvent) {
    if error is CancellationError { return }
    sessionLog.error("\(event.description, privacy: .public) session failed: \(error.localizedDescription, privacy: .public)")
}

@MainActor
private func performRefreshSession(
    _ event: RefreshSessionEvent,
    layoutWorkspaces shouldLayoutWorkspaces: Bool = true,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) async throws {
    let state = signposter.beginInterval(#function, "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer { signposter.endInterval(#function, state) }
    if !TrayMenuModel.shared.isEnabled { return }
    if case .onWindowParkingDrift = event {
        guard !WindowBorderController.shared.isMissionControlActive else { return }
        // A native window can move without an AX event. Repair placement promptly
        // while preserving logical focus and avoiding unrelated AX enumeration.
        try await $refreshSessionEvent.withValue(event) { try await layoutWorkspaces() }
        return
    }
    let focusSnapshot = captureRefreshSessionFocusSnapshot()
    let activation = pendingActivation
    debugLog(.focus, "runRefreshSessionBlocking begin event=\(event) snapshot=\(debugDescribe(focusSnapshot))")
    try await $refreshSessionEvent.withValue(event) {
        try await $_isStartup.withValue(event.isStartup) {
            try await $_refreshSessionFocusSnapshot.withValue(focusSnapshot) {
                let frontmostApplication = NSWorkspace.shared.frontmostApplication
                let frontmostActivationPolicy = frontmostApplication?.activationPolicy
                // Decided before this session registers new windows: a launching app has none yet.
                if let activation, activation.pid == frontmostApplication?.processIdentifier,
                   !MacWindow.allWindows.contains(where: { $0.app.pid == activation.pid }) {
                    runtime.refresh.windowlessActivationPid = activation.pid
                }
                let observation = try await observeAndRecordNativeFocusForSession()
                let nativeFocused = observation.window

                if shouldLayoutWorkspaces && optimisticallyPreLayoutWorkspaces { try await layoutWorkspaces() }
                try checkCancellation()

                refreshModel()
                if event.requiresWindowRefreshBarrier {
                    if let refreshOverrideForTests {
                        try await refreshOverrideForTests()
                    } else {
                        try await refresh()
                    }
                    try checkCancellation()
                    gcMonitors()
                }

                if event.requiresLayoutReasonNormalization {
                    if let normalizeLayoutReasonOverrideForTests {
                        try await normalizeLayoutReasonOverrideForTests()
                    } else {
                        try await normalizeLayoutReason()
                    }
                    try checkCancellation()
                    refreshModel()
                }
                updateTrayText()
                SecureInputPanel.shared.refresh()
                if shouldLayoutWorkspaces {
                    try await layoutWorkspaces()
                    try checkCancellation()
                    if observation.known && shouldSyncFocusBackToMacOs(
                        nativeFocused: nativeFocused,
                        frontmostActivationPolicy: frontmostActivationPolicy,
                        frontmostPid: frontmostApplication?.processIdentifier,
                    ) {
                        let logicalFocused = focus.windowOrNil
                        if logicalFocused?.windowId != nativeFocused?.windowId {
                            debugLog(.focus, "runRefreshSessionBlocking syncFocus event=\(event) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") logicalFocused=\(logicalFocused?.windowId.description ?? "nil")"
                            )
                            logicalFocused?.nativeFocus()
                        } else {
                            // Cmd+Tab already reports the chosen AX window as focused, but
                            // switching virtual workspaces can leave another window above it.
                            if pendingActivation == activation, let window = logicalFocused as? MacWindow, !window.isHiddenInCorner,
                               activation?.shouldRaise(
                                   currentWorkspace: focus.workspace.name,
                                   nativeWindowId: nativeFocused?.windowId, logicalWindowId: logicalFocused?.windowId,
                                   frontmostPid: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                   targetPid: window.macApp.pid
                               ) == true {
                                window.macApp.nativeFocus(window.windowId, forceRaise: true)
                            }
                            debugLog(.focus, "runRefreshSessionBlocking skipSyncFocus event=\(event) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") logicalFocused=\(logicalFocused?.windowId.description ?? "nil")"
                            )
                        }
                    }
                }
                await updateWorkspaceSidebarModel()
                // A newer activation arriving during AX awaits belongs to the next session.
                if shouldLayoutWorkspaces, pendingActivation == activation {
                    pendingActivation = nil
                }
                await updateWindowTabModel()
                schedulePersistedFrozenWorldSave()
                debugLog(.focus, "runRefreshSessionBlocking end event=\(event) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") focus=\(debugDescribe(focus))")
            }
        }
    }
}

@MainActor
private func performLightSession<T>(
    _ event: RefreshSessionEvent,
    _: RunSessionGuard,
    shouldSchedulePostRefresh: Bool = true,
    body: @MainActor () async throws -> T,
) async throws -> T {
    if case .globalObserver("workspaceSwipe") = event {
        // The swipe's own commit keeps its preview until the real layout is ready.
    } else {
        WorkspaceSwipeController.shared.cancelVisualInteraction()
    }
    let state = signposter.beginInterval(#function, "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer { signposter.endInterval(#function, state) }
    // Keep work that a native event already requested. A cheap command/swipe may
    // skip its own follow-up, but must not lose an interrupted creation/wake pass.
    if let event = activeScheduledRefreshEvent {
        queueRefreshFollowUp(event, optimisticallyPreLayoutWorkspaces: false)
    }
    // Give priority to runSession. Taking the generation keeps the cancelled task's completion
    // from spawning a coalesced follow-up session in the middle of this light session. The
    // post-refresh scheduled at the end of the light session (or any later event) picks the
    // pending request up instead.
    runtime.refresh.stopActive()
    let generation = activeScheduledRefreshGeneration
    // Errors and cancellation must also drain interrupted native work. A newer
    // session owns its own completion and must not be disturbed by this one.
    defer {
        if activeScheduledRefreshGeneration == generation, activeRefreshTask == nil,
           let pending = pendingRefreshRequest {
            scheduleRefreshSession(pending.event,
                optimisticallyPreLayoutWorkspaces: pending.optimisticallyPreLayoutWorkspaces,
                recordsActivation: false)
        }
    }
    let focusSnapshot = captureRefreshSessionFocusSnapshot()
    debugLog(.focus, "runLightSession begin event=\(event) snapshot=\(debugDescribe(focusSnapshot))")
    return try await $refreshSessionEvent.withValue(event) {
        try await $_isStartup.withValue(event.isStartup) {
            try await $_refreshSessionFocusSnapshot.withValue(focusSnapshot) {
                let nativeFocused = try await observeAndRecordNativeFocusForSession().window
                let focusBefore = focus.windowOrNil

                refreshModel()
                let result = try await body()
                try checkCancellation()
                refreshModel()

                let focusAfter = focus.windowOrNil

                updateTrayText()
                SecureInputPanel.shared.refresh()
                try await layoutWorkspaces()
                try checkCancellation()
                if focusBefore != focusAfter {
                    focusAfter?.nativeFocus() // syncFocusToMacOs before sidebar title queries
                }
                await updateWorkspaceSidebarModel()
                await updateWindowTabModel()
                schedulePersistedFrozenWorldSave()
                if shouldSchedulePostRefresh || pendingRefreshRequest != nil {
                    scheduleRefreshSession(event)
                }
                debugLog(.focus, "runLightSession end event=\(event) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") focusBefore=\(focusBefore?.windowId.description ?? "nil") focusAfter=\(focusAfter?.windowId.description ?? "nil") logicalFocus=\(debugDescribe(focus))")
                return result
            }
        }
    }
}

@MainActor
func setScheduledRefreshOverrideForTests(
    _ override: (@MainActor @Sendable (RefreshSessionEvent, Bool) async throws -> Void)?
) {
    runtime.refresh.stopActive()
    pendingRefreshRequest = nil
    pendingActivation = nil
    scheduledRefreshOverrideForTests = override
}

@MainActor
func setBlockingRefreshOverridesForTests(
    refresh: (@MainActor @Sendable () async throws -> Void)? = nil,
    normalizeLayoutReason: (@MainActor @Sendable () async throws -> Void)? = nil,
) {
    runtime.refresh.stopActive()
    pendingRefreshRequest = nil
    pendingActivation = nil
    refreshOverrideForTests = refresh
    normalizeLayoutReasonOverrideForTests = normalizeLayoutReason
}

@MainActor
func waitForScheduledRefreshForTests() async throws {
    // A completing session may schedule a coalesced follow-up session; drain until quiet.
    for _ in 0 ..< 100 {
        guard let task = activeRefreshTask else { return }
        try await task.value
    }
}

struct RunSessionGuard: Sendable {
    @MainActor
    static var isServerEnabled: RunSessionGuard? { TrayMenuModel.shared.isEnabled ? forceRun : nil }
    @MainActor
    static func isServerEnabled(orIsEnableCommand command: (any Command)?) -> RunSessionGuard? {
        (command is EnableCommand || command is StateCommand) ? .forceRun : .isServerEnabled
    }
    @MainActor
    static func checkServerIsEnabledOrDie(
        file: StaticString = #fileID,
        line: Int = #line,
        column: Int = #column,
        function: String = #function,
    ) -> RunSessionGuard {
        .isServerEnabled ?? dieT("server is disabled", file: file, line: line, column: column, function: function)
    }
    static let forceRun = RunSessionGuard()
    private init() {}
}

@MainActor
func refreshModel() {
    // Focus-only sessions skip AX enumeration, but must still free layout slots
    // for closed native windows. Hidden/minimized windows remain valid here.
    if !isUnitTest {
        let windowIds = Array(Set(MacWindow.allWindowsMap.keys).union(WindowBorderController.shared.missionControlWindowIds))
        windowIds.withUnsafeBufferPointer {
            winmux_watch_windows($0.baseAddress, Int32($0.count))
        }
    }
    for window in MacWindow.allWindows where !runtime.windowServer.exists(window.windowId) {
        window.garbageCollect(skipClosedWindowsCache: false)
        // WindowServer confirms it is gone, as when the native close notification was missed.
        invalidateClosedWindowsCacheForNativeClosure(window.windowId)
    }
    Workspace.reconcileWorkspaceState()
    checkOnFocusChangedCallbacks()
    normalizeContainers()
    if !isUnitTest { WorkspaceOverviewController.shared.modelDidChange() }
}

@MainActor
private func refresh() async throws {
    // Garbage collect terminated apps and windows before working with all windows
    let mapping = try await MacApp.refreshAllAndGetAliveWindowIds(
        frontmostAppBundleId: isLockScreenApp(NSWorkspace.shared.frontmostApplication) ? lockScreenAppBundleId : nil)
    let aliveWindowIds = mapping.values.flatMap { $0 }.toSet()

    for window in MacWindow.allWindows {
        if !aliveWindowIds.contains(window.windowId) {
            window.garbageCollect(skipClosedWindowsCache: false)
        }
    }
    // One task per app so the per-window AX round-trips of different apps overlap;
    // a single slow app no longer delays every other app's window registration.
    try await withThrowingTaskGroup(of: Void.self) { group in
        for (app, windowIds) in mapping {
            group.addTask { @Sendable @MainActor in
                try await skippingUnansweredApp {
                    for windowId in windowIds {
                        try await MacWindow.getOrRegister(windowId: windowId, macApp: app)
                    }
                }
            }
        }
        try await group.waitForAll()
    }
    // Floating windows are the only windows whose real frame can't be derived from the applied
    // layout, and some synchronous consumers (interaction-opacity parking, agent pane info)
    // read the cached rect directly. Re-warm just the ones invalidated by move/resize events —
    // typically none — instead of polling every window's frame each barrier.
    let staleFloatingWindows = Workspace.all.flatMap { workspace in
        workspace.floatingWindows.filter { $0.lastKnownActualRect == nil }
    }
    if !staleFloatingWindows.isEmpty {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for window in staleFloatingWindows {
                group.addTask { @Sendable @MainActor in
                    _ = try? await window.getAxRect()
                }
            }
            try await group.waitForAll()
        }
    }
    try await skippingUnansweredApp { try await retryPendingRestartWindows() }
    try await finalizePersistedFrozenWorldAfterRefresh(aliveWindowIds: aliveWindowIds)

    // Garbage collect workspaces after apps, because workspaces contain apps.
    Workspace.reconcileWorkspaceState()
}

func refreshObs(_: AXObserver, _ ax: AXUIElement, notif: CFString, _ context: UnsafeMutableRawPointer?) {
    let notif = notif as String
    let destroyedWindowId = notif == kAXUIElementDestroyedNotification as String
        ? context?.assumingMemoryBound(to: UInt32.self).pointee ?? ax.containingWindowId()
        : nil
    let emittingAppPid = axTaskLocalAppThreadToken?.pid
    if notif == kAXFocusedWindowChangedNotification as String || notif == kAXUIElementDestroyedNotification as String {
        debugLog(.focus, "refreshObs notif=\(notif)")
    }
    // Minimize state changed: drop the event-invalidated native-state cache for this window so
    // the next normalizeLayoutReason pass fetches it live. containingWindowId runs here on the
    // app's AX thread, not on the main thread.
    let isMinimizeStateNotif =
        notif == kAXWindowMiniaturizedNotification as String || notif == kAXWindowDeminiaturizedNotification as String
    let invalidateNativeStateWindowId: UInt32? = isMinimizeStateNotif ? ax.containingWindowId() : nil
    // A busy app can time out the windowId resolution. Losing this invalidation would poison
    // the cache permanently (a minimized window emits no further geometry events), so fall
    // back to invalidating every window of the emitting app.
    let invalidateNativeStateAppPid: pid_t? =
        isMinimizeStateNotif && invalidateNativeStateWindowId == nil ? axTaskLocalAppThreadToken?.pid : nil
    Task { @MainActor in
        if destroyedWindowId != nil { windowLifecycleChanges.notify() }
        if let destroyedWindowId {
            WindowBorderController.shared.remove(windowId: destroyedWindowId)
            (Window.get(byId: destroyedWindowId) as? MacWindow)?.garbageCollect(skipClosedWindowsCache: false)
            if let emittingAppPid, let app = MacApp.allAppsMap[emittingAppPid] {
                try? await app.unregisterDestroyedWindow(destroyedWindowId)
            }
        }
        if let invalidateNativeStateWindowId {
            Window.get(byId: invalidateNativeStateWindowId)?.invalidateLastKnownNativeState()
        } else if let invalidateNativeStateAppPid {
            for window in MacWindow.allWindows where window.macApp.pid == invalidateNativeStateAppPid {
                window.invalidateLastKnownNativeState()
            }
        }
        if !TrayMenuModel.shared.isEnabled { return }
        scheduleRefreshSession(.ax(notif))
    }
}

@MainActor
private func layoutWorkspaces() async throws {
    if WindowRecoveryController.shared.suppressAutomaticFrameWrites { return }
    let monitors = monitors
    var monitorToOptimalHideCorner: [CGPoint: OptimalHideCorner] = [:]
    for monitor in monitors {
        monitorToOptimalHideCorner[monitor.rect.topLeftCorner] = optimalWorkspaceHideCorner(
            for: monitor.rect, displays: monitors.map(\.rect))
    }

    // Stage timings count only refreshes that park or reveal something, as workspace switches do.
    let parkingStarted = CACurrentMediaTime()
    var parked = 0
    for workspace in Workspace.all where !workspace.isVisible {
        let corner = monitorToOptimalHideCorner[workspace.workspaceMonitor.rect.topLeftCorner] ?? .bottomRightCorner
        let shouldReassertHiddenWindows = refreshSessionEvent?.requiresHiddenWindowsReassertion == true
        for window in workspace.allLeafWindowsRecursive {
            try checkCancellation()
            guard let macWindow = window as? MacWindow else { continue }
            macWindow.lastAppliedLayoutPhysicalRect = nil
            macWindow.lastAppliedLayoutVirtualRect = nil
            // A nil cached rect means a geometry event arrived since the window was last
            // observed — including our own parking move, but also an app repositioning its
            // parked window (document restore, [NSWindow center], ...). Re-observe and
            // re-park exactly those windows: this keeps the drift self-heal the old
            // reassert-everything-on-every-event behavior provided, while windows with a
            // confirmed parked position cost nothing.
            let geometryUnconfirmed = macWindow.lastKnownActualRect == nil
            if geometryUnconfirmed {
                _ = try? await macWindow.getAxRect()
            }
            // Geometry invalidation also follows our own parking notifications. Let
            // hideInCorner confirm native placement, including safe OS clamping,
            // instead of forcing the same rejected position on every refresh.
            if !macWindow.isHiddenInCorner { parked += 1 }
            try await skippingUnansweredApp { try await macWindow.hideInCorner(corner, force: shouldReassertHiddenWindows) }
        }
    }
    if parked > 0 { WorkspaceMotionDiagnostics.record("Park outgoing windows", milliseconds: (CACurrentMediaTime() - parkingStarted) * 1000) }
    // Reveal incoming windows only after outgoing workspaces are parked.
    let revealStarted = CACurrentMediaTime()
    var revealed = 0
    defer {
        if revealed > 0 { WorkspaceMotionDiagnostics.record("Reveal and lay out visible workspaces", milliseconds: (CACurrentMediaTime() - revealStarted) * 1000) }
    }
    for monitor in monitors {
        let workspace = monitor.activeWorkspace
        for window in workspace.allLeafWindowsRecursive {
            try checkCancellation()
            guard let macWindow = window as? MacWindow else { continue }
            if shouldKeepWindowHiddenForVisibleWorkspaceLayout(window) {
                continue
            }
            if macWindow.isHiddenInCorner { revealed += 1 }
            try await skippingUnansweredApp { try await macWindow.unhideFromCorner() }
        }
        try await workspace.layoutWorkspace()
        try checkCancellation()
        if monitor.activeWorkspace === workspace { WorkspaceMotionDiagnostics.layoutReady(workspace) }
    }
}

@MainActor
private func shouldKeepWindowHiddenForVisibleWorkspaceLayout(_ window: Window) -> Bool {
    guard let tabGroup = window.nearestWindowTabGroup, tabGroup.usesWindowTabBehavior else { return false }
    return tabGroup.tabActiveWindow != window
}

@MainActor
private func normalizeContainers() {
    // Can't do it only for visible workspace because most of the commands support --window-id and --workspace flags
    for workspace in Workspace.all {
        workspace.normalizeContainers()
    }
}

/// Reads native focus and, when it is known, records it in the focus cache and
/// fullscreen chrome state. Shared preamble of full and light refresh sessions.
@MainActor
private func observeAndRecordNativeFocusForSession() async throws -> (window: Window?, known: Bool) {
    let observation = try await observeNativeFocusForSession()
    let nativeFocused = observation.window
    try checkCancellation()
    if let nativeFocused { try await debugWindowsIfRecording(nativeFocused) }
    if observation.known {
        updateNativeFullscreenChromeSuppression()
        updateFocusCache(nativeFocused)
    }
    try checkCancellation()
    return observation
}
