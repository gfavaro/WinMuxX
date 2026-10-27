import AppKit
import Common
import PrivateApi

final class MacWindow: Window {
    let macApp: MacApp
    @MainActor override var minimumLayoutSize: CGSize { learnedMinimum.size }

    @MainActor private(set) var learnedMinimum = LearnedWindowMinimum()
    @MainActor private var minimumObservation: Task<Void, Never>?
    @MainActor private var frameRequestGeneration: UInt64 = 0
    @MainActor private var minimumRequest: (point: CGPoint?, size: CGSize?)?
    @MainActor private var scrollingSheetCache: (generation: UInt64, offsets: [CGRect])?

    @MainActor func invalidateScrollingSheetCache() { scrollingSheetCache = nil }

    @MainActor
    func scrollingSheetOffsets() async throws -> [CGRect] {
        let generation = nativeStateObservationToken()
        if let cache = scrollingSheetCache, cache.generation == generation { return cache.offsets }
        let offsets = try await macApp.attachedSheetOffsets(windowId)
        guard nativeStateObservationToken() == generation else { return [] }
        scrollingSheetCache = (generation, offsets)
        return offsets
    }

    @MainActor
    func resetLearnedMinimum() {
        frameRequestGeneration &+= 1
        minimumObservation?.cancel()
        minimumObservation = nil
        minimumRequest = nil
        learnedMinimum = LearnedWindowMinimum()
    }

    @MainActor
    func restoreLearnedMinimum(_ size: CGSize?, savedBundleId: String?, generation: MinimumEvidenceGeneration) {
        guard let size, size.width.isFinite, size.height.isFinite,
              size.width >= 0, size.height >= 0, size != .zero,
              PersistedAppMinimums.shared.acceptsEvidence(generation, for: macApp.rawAppBundleId,
                                                           savedBundleId: savedBundleId) else { return }
        learnedMinimum = LearnedWindowMinimum(size: size)
    }
    private var prevUnhiddenProportionalPositionInsideWorkspaceRect: CGPoint?
    private var workspaceReveal = WorkspaceWindowRevealState()
    /// The corner the window is parked in, together with the monitor rect it was parked
    /// against: when the monitor's geometry changes (or the workspace moves to another
    /// monitor), the old corner position is wrong and the window must be re-parked even
    /// though the corner still matches. One value so the two can't desync.
    private var hiddenInCorner: (corner: OptimalHideCorner, monitorVisibleRect: Rect)?

    @MainActor
    private init(_ id: UInt32, _ actor: MacApp, lastFloatingSize: CGSize?, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) {
        self.macApp = actor
        if !isUnitTest, let size = PersistedAppMinimums.shared.size(for: actor.rawAppBundleId) {
            learnedMinimum = LearnedWindowMinimum(size: size)
        }
        super.init(id: id, actor, lastFloatingSize: lastFloatingSize, parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor static var allWindowsMap: [UInt32: MacWindow] = [:]
    @MainActor static var allWindows: [MacWindow] { Array(allWindowsMap.values) }

    @MainActor
    @discardableResult
    static func getOrRegister(windowId: UInt32, macApp: MacApp) async throws -> MacWindow? {
        if runtime.workspaceBackend.kind == .native {
            return try await getOrRegisterNative(windowId: windowId, macApp: macApp)
        }
        // Focus/main-window AX attributes can continue reporting a closed id.
        // Never let the fast focus path recreate its layout node.
        if !isUnitTest && !winmux_window_exists(windowId) {
            allWindowsMap[windowId]?.garbageCollect(skipClosedWindowsCache: false)
            return nil
        }
        if let existing = allWindowsMap[windowId] {
            // No AX round-trip for known windows: this runs for every window on every refresh
            // barrier, and lastKnownActualRect stays correct without polling because moved /
            // resized AX events invalidate it and consumers re-fetch on demand.
            return existing
        }
        let creationWorkspace = isStartup ? nil : focus.workspace
        let rect = try await macApp.getAxRect(windowId)
        let data = try await unbindAndGetBindingDataForNewWindow(
            windowId,
            macApp,
            isStartup
                ? (rect?.center.monitorApproximation ?? mainMonitor).activeWorkspace
                : creationWorkspace ?? focus.workspace,
            window: nil,
        )

        // atomic synchronous section
        if let existing = allWindowsMap[windowId] { return existing }
        let window = MacWindow(windowId, macApp, lastFloatingSize: rect?.size, parent: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
        window.recordAuthoritativeActualRect(rect)
        allWindowsMap[windowId] = window
        WindowRecoveryController.shared.stageOriginalFrame(window, originalRect: rect)

        try await WindowDetectionOperations.shared.run(window) {
            window.restartIdentity = try? await macApp.getRestartWindowIdentity(windowId)
            if window.restartIdentity == nil, let bundleId = macApp.rawAppBundleId {
                window.restartIdentity = RestartWindowIdentity(bundleId: bundleId, pid: macApp.pid,
                    launchDate: macApp.nsApp.launchDate, title: "")
            }
            try await debugWindowsIfRecording(window)
            let didRestorePersistedFrozenWorld = try await restorePersistedFrozenWorldIfNeeded(newlyDetectedWindow: window)
            let didRestoreClosedWindowsCache = didRestorePersistedFrozenWorld ? false : try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
            if !didRestorePersistedFrozenWorld && !didRestoreClosedWindowsCache {
                try await tryOnWindowDetected(window)
            }
            if !didRestorePersistedFrozenWorld {
                trackPendingRestartWindow(window)
                if window.parent is TilingContainer || window.parent is Workspace {
                    invalidateLateRestartTreeRestoration()
                }
            }
        }
        if window.parent is MacosPopupWindowsContainer { WindowDetectionOperations.shared.schedulePopupChecks(window) }
        if let workspace = window.nodeWorkspace {
            NotificationCenter.default.post(name: workspaceControlsWindowDetected, object: nil, userInfo: [
                "projectId": workspace.projectId,
                "viewportId": MonitorViewportId(workspace.workspaceMonitor),
            ])
        }
        return window
    }

    @MainActor
    private static func getOrRegisterNative(windowId: UInt32, macApp: MacApp) async throws -> MacWindow? {
        let layouts = runtime.workspaceBackend.nativeLayouts
        guard let registration = layouts.registration(for: windowId),
              !macApp.nsApp.isTerminated else { return nil }
        let workspace = registration.workspace
        if let existing = allWindowsMap[windowId], existing.macApp === macApp,
           existing.nodeWorkspace === workspace {
            let native = try await macApp.readNativeState(windowId)
            try Task.checkCancellation()
            guard layouts.accepts(registration) else { return nil }
            existing.nativeLayoutEligible = native?.fullscreen == false && native?.minimized == false
            return existing.nativeLayoutEligible ? existing : nil
        }
        let rect = try await macApp.getAxRect(windowId)
        let type = try await macApp.getAxUiElementWindowType(windowId, getWindowLevel(for: windowId))
        let native = try await macApp.readNativeState(windowId)
        try Task.checkCancellation()
        guard layouts.accepts(registration),
              !macApp.nsApp.isTerminated, native?.fullscreen == false, native?.minimized == false else { return nil }
        if case .popup = type { return nil }
        if let existing = allWindowsMap[windowId] {
            if existing.macApp !== macApp {
                existing.garbageCollect(skipClosedWindowsCache: true)
            } else {
                let floated = existing.parent is Workspace
                let binding = floated ? BindingData(parent: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
                    : bindingDataForNewWindow(type: type, workspace: workspace, window: existing)
                existing.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
                existing.recordAuthoritativeActualRect(rect)
                return existing
            }
        }
        let binding = bindingDataForNewWindow(type: type, workspace: workspace, window: nil)
        let window = MacWindow(windowId, macApp, lastFloatingSize: rect?.size,
            parent: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
        window.recordAuthoritativeActualRect(rect)
        allWindowsMap[windowId] = window
        window.restartIdentity = try? await macApp.getRestartWindowIdentity(windowId)
        try await applyNativeWindowDetectedRules(window) { layouts.accepts(registration) }
        return window
    }

    // var description: String {
    //     let description = [
    //         ("title", title),
    //         ("role", axWindow.get(Ax.roleAttr)),
    //         ("subrole", axWindow.get(Ax.subroleAttr)),
    //         ("identifier", axWindow.get(Ax.identifierAttr)),
    //         ("modal", axWindow.get(Ax.modalAttr).map { String($0) } ?? ""),
    //         ("windowId", String(windowId)),
    //     ].map { "\($0.0): '\(String(describing: $0.1))'" }.joined(separator: ", ")
    //     return "Window(\(description))"
    // }

    func isWindowHeuristic(_ windowLevel: MacOsWindowLevel?) async throws -> Bool { // todo cache
        try await macApp.isWindowHeuristic(windowId, windowLevel)
    }

    func isDialogHeuristic(_ windowLevel: MacOsWindowLevel?) async throws -> Bool { // todo cache
        try await macApp.isDialogHeuristic(windowId, windowLevel)
    }

    func dumpAxInfo() async throws -> [String: Json] {
        try await macApp.dumpWindowAxInfo(windowId: windowId)
    }

    @MainActor
    override func readNativeState() async throws -> (fullscreen: Bool, minimized: Bool)? {
        do { return try await macApp.readNativeState(windowId) }
        catch let failure as AXReadFailure where failure.code == .cannotComplete { return nil }
    }

    func setNativeFullscreen(_ value: Bool) {
        if value { NotificationCenter.default.post(name: workspaceControlsWindowInvalidated, object: nil, userInfo: ["windowId": windowId]) }
        else { NotificationCenter.default.post(name: workspaceControlsWindowRestored, object: nil, userInfo: ["windowId": windowId]) }
        macApp.setNativeFullscreen(windowId, value)
    }

    func setNativeMinimized(_ value: Bool) {
        if value { NotificationCenter.default.post(name: workspaceControlsWindowInvalidated, object: nil, userInfo: ["windowId": windowId]) }
        else { NotificationCenter.default.post(name: workspaceControlsWindowRestored, object: nil, userInfo: ["windowId": windowId]) }
        macApp.setNativeMinimized(windowId, value)
    }

    // skipClosedWindowsCache is an optimization when it's definitely not necessary to cache closed window.
    //                        If you are unsure, it's better to pass `false`
    @MainActor
    func garbageCollect(skipClosedWindowsCache: Bool) {
        if runtime.workspaceBackend.kind == .native {
            guard MacWindow.allWindowsMap.removeValue(forKey: windowId) != nil else { return }
            WindowMotion.shared.forget(windowId)
            resetLearnedMinimum()
            if parent != nil { _ = unbindFromParent() }
            return
        }
        NotificationCenter.default.post(name: workspaceControlsWindowClosed, object: nil, userInfo: ["windowId": windowId])
        WindowDetectionOperations.shared.cancel(self)
        forgetPendingRestartWindow(windowId)
        if macApp.nsApp.isTerminated, MacWindow.allWindowsMap[windowId] != nil {
            rememberRestartWindowBeforeAppTermination(self)
        }
        WindowMotion.shared.forget(windowId)
        WindowBorderController.shared.remove(windowId: windowId)
        if MacWindow.allWindowsMap.removeValue(forKey: windowId) == nil {
            return
        }
        WindowRecoveryController.shared.forget(self)
        resetLearnedMinimum()
        if !skipClosedWindowsCache { cacheClosedWindowIfNeeded() }
        let parent = unbindFromParent().parent
        let deadWindowWorkspace = parent.nodeWorkspace
        let currentFocus = focus
        let previousFocus = prevFocus
        let previousPreviousFocus = prevPrevFocus
        let refreshSnapshot = refreshSessionFocusSnapshot
        let refreshSnapshotCloseFallback = refreshSnapshot?.fallbackWhenFocusedWindowCloses?.liveOrNil
        let refreshSnapshotPreviousFocus = refreshSessionFocusSnapshot?.prevFocus?.liveOrNil
        let refreshSnapshotPreviousPreviousFocus = refreshSessionFocusSnapshot?.prevPrevFocus?.liveOrNil
        debugFocusLog(
            "MacWindow.garbageCollect closing=\(windowId) currentFocus=\(debugDescribe(currentFocus)) prev=\(debugDescribe(previousFocus)) prevPrev=\(debugDescribe(previousPreviousFocus)) snapshot=\(debugDescribe(refreshSnapshot))"
        )
        if let replacementFocus = focusAfterWindowClosure(
            closingWindow: self,
            deadWindowWorkspace: deadWindowWorkspace,
            currentFocus: currentFocus,
            previousFocus: previousFocus,
            previousPreviousFocus: previousPreviousFocus,
            refreshSnapshotCloseFallback: refreshSnapshotCloseFallback,
            refreshSnapshotPreviousFocus: refreshSnapshotPreviousFocus,
            refreshSnapshotPreviousPreviousFocus: refreshSnapshotPreviousPreviousFocus,
            previousFocusedWorkspace: prevFocusedWorkspace,
            previousFocusedWorkspaceDate: prevFocusedWorkspaceDate,
        ) {
            switch parent.cases {
                case .tilingContainer, .workspace, .macosHiddenAppsWindowsContainer, .macosFullscreenWindowsContainer:
                    debugFocusLog("MacWindow.garbageCollect replacement closing=\(windowId) replacement=\(debugDescribe(replacementFocus))")
                    _ = setFocus(to: replacementFocus)
                    if replacementFocus.windowOrNil == nil, replacementFocus.workspace === deadWindowWorkspace {
                        holdFocusAfterLastWindowClosure(on: replacementFocus.workspace, appPid: macApp.pid)
                    }
                    if replacementFocus.windowOrNil != currentFocus.windowOrNil {
                        replacementFocus.windowOrNil?.nativeFocus()
                    }
                case .macosPopupWindowsContainer, .macosMinimizedWindowsContainer:
                    break // Don't switch back on popup destruction
            }
        }
    }

    @MainActor override var title: String { get async throws { try await macApp.getAxTitle(windowId) ?? "" } }
    @MainActor override var isMacosFullscreen: Bool { get async throws { try await macApp.isMacosNativeFullscreen(windowId) == true } }
    @MainActor override var isMacosMinimized: Bool { get async throws { try await macApp.isMacosNativeMinimized(windowId) == true } }

    @MainActor
    override func nativeFocus() {
        guard !isHiddenInCorner else { return }
        WorkspaceTransitionDiagnostics.record("focus", window: self, generation: workspaceReveal.generation)
        macApp.nativeFocus(windowId)
    }

    @MainActor
    func requestCloseForProjectDeletion(timeout: TimeInterval = 1.5) async -> Bool {
        guard (try? await macApp.pressCloseButton(windowId)) == true else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await macApp.containsAxWindow(windowId)) == false {
                garbageCollect(skipClosedWindowsCache: true)
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    override func closeAxWindow() {
        garbageCollect(skipClosedWindowsCache: true)
        macApp.closeAndUnregisterAxWindow(windowId)
    }

    // todo it's part of the window layout and should be moved to layoutRecursive.swift
    @MainActor
    func hideInCorner(_ corner: OptimalHideCorner, force: Bool = false) async throws {
        guard runtime.workspaceBackend.kind == .virtual else { return }
        guard let nodeMonitor else { return }
        // Don't accidentally override prevUnhiddenEmulationPosition in case of subsequent `hideInCorner` calls
        if !isHiddenInCorner {
            guard let windowRect = try await getAxRect() else { return }
            // Check for isHiddenInCorner for the second time because of the suspension point above
            if !isHiddenInCorner {
                let topLeftCorner = windowRect.topLeftCorner
                let monitorRect = windowRect.center.monitorApproximation.rect // Similar to layoutFloatingWindow. Non idempotent
                if !preserveRestoredWorkspacePreview, let preview = normalizedWorkspacePreviewFrame(
                    CGRect(origin: windowRect.topLeftCorner, size: windowRect.size),
                    origin: monitorRect.topLeftCorner, desktopSize: monitorRect.size)
                {
                    workspacePreviewFrame = preview
                }
                let absolutePoint = topLeftCorner - monitorRect.topLeftCorner
                // Startup cleanup may have moved native windows to a safe location.
                // Floating reveal must use the same saved position as its preview.
                prevUnhiddenProportionalPositionInsideWorkspaceRect = preserveRestoredWorkspacePreview
                    ? workspacePreviewFrame?.origin
                    : CGPoint(x: absolutePoint.x / monitorRect.width, y: absolutePoint.y / monitorRect.height)
            }
        }
        // A parking flag is only a hint: apps may reposition without AX events.
        // Query WindowServer before skipping the write, without paying an AX round-trip.
        var parkedFrame: CGRect?
        if !force, isHiddenInCorner, hiddenInCorner?.corner == corner,
           hiddenInCorner?.monitorVisibleRect == nodeMonitor.visibleRect {
            var actual = CGRect.zero
            if winmux_window_frame(windowId, &actual) { parkedFrame = actual }
        }
        var effectiveCorner = corner
        var windowSize = parkedFrame?.size ?? .zero
        if corner == .bottomLeftCorner, parkedFrame == nil {
            if let size = try await getAxSize() { windowSize = size }
            else { effectiveCorner = .bottomRightCorner }
        }
        let p = workspaceParkingPoint(corner: effectiveCorner,
            visibleRect: CGRect(origin: nodeMonitor.visibleRect.topLeftCorner, size: nodeMonitor.visibleRect.size),
            windowSize: windowSize, zeroOffset: macApp.appId == .zoom)
        if let parkedFrame, workspaceParkingFrameIsAcceptable(parkedFrame, requested: p,
            displays: monitors.map { CGRect(origin: $0.rect.topLeftCorner, size: $0.rect.size) }) { return }
        // Complete parking before another workspace is revealed. AX frame writes
        // are otherwise queued, allowing outgoing windows to overlap the destination.
        guard !WindowRecoveryController.shared.suppressAutomaticFrameWrites else { return }
        workspaceReveal.park()
        if !isUnitTest { WindowBorderController.shared.remove(windowId: windowId) }
        let parkingGeneration = workspaceReveal.generation
        WorkspaceTransitionDiagnostics.record("park-begin", window: self, generation: parkingGeneration,
            requested: CGRect(origin: p, size: CGSize(width: lastKnownActualRect?.width ?? 0, height: lastKnownActualRect?.height ?? 0)))
        try await setAxFrameBlocking(p, nil)
        try checkCancellation()
        guard workspaceReveal.generation == parkingGeneration else { return }
        hiddenInCorner = (corner, nodeMonitor.visibleRect)
        WorkspaceTransitionDiagnostics.record("park-end", window: self, generation: parkingGeneration)
    }

    @MainActor var hasCompletedNativeParking: Bool { hiddenInCorner != nil }

    @MainActor func nativeFrameForRecovery() -> CGRect? {
        var frame = CGRect.zero
        return winmux_window_frame(windowId, &frame) ? frame : nil
    }

    @MainActor func fallbackFrameForRecovery() -> CGRect? {
        guard let monitor = nodeMonitor else { return nil }
        if let unit = workspacePreviewFrame {
            return CGRect(x: monitor.rect.minX + unit.minX * monitor.width,
                y: monitor.rect.minY + unit.minY * monitor.height,
                width: unit.width * monitor.width, height: unit.height * monitor.height)
        }
        return terminationFrame(visibleFrame: CGRect(origin: monitor.visibleRect.topLeftCorner, size: monitor.visibleRect.size),
            floatingSize: lastFloatingSize)
    }

    @MainActor func resumeFromVisibleNativeGeometry() {
        guard let frame = nativeFrameForRecovery(), monitors.contains(where: {
            let intersection = frame.intersection(CGRect(origin: $0.rect.topLeftCorner, size: $0.rect.size))
            return !intersection.isNull && intersection.width > 1 && intersection.height > 1
        }) else { return }
        prevUnhiddenProportionalPositionInsideWorkspaceRect = nil
        hiddenInCorner = nil
        workspaceReveal = WorkspaceWindowRevealState()
        recordAuthoritativeActualRect(Rect(topLeftX: frame.minX, topLeftY: frame.minY, width: frame.width, height: frame.height))
        lastAppliedLayoutPhysicalRect = nil
        lastAppliedLayoutVirtualRect = nil
    }

    @MainActor
    func hasConfirmedNativeParkingPosition() -> Bool {
        guard isHiddenInCorner, let hiddenInCorner, let nodeMonitor,
              hiddenInCorner.monitorVisibleRect == nodeMonitor.visibleRect else { return false }
        var actual = CGRect.zero
        guard winmux_window_frame(windowId, &actual) else { return false }
        let requested = workspaceParkingPoint(corner: hiddenInCorner.corner,
            visibleRect: CGRect(origin: nodeMonitor.visibleRect.topLeftCorner, size: nodeMonitor.visibleRect.size),
            windowSize: actual.size, zeroOffset: macApp.appId == .zoom)
        return workspaceParkingFrameIsAcceptable(actual, requested: requested,
            displays: monitors.map { CGRect(origin: $0.rect.topLeftCorner, size: $0.rect.size) })
    }

    @MainActor
    func unhideFromCorner() async throws {
        guard let prevUnhiddenProportionalPositionInsideWorkspaceRect else { return }
        guard let nodeWorkspace else { return } // hiding only makes sense for workspace windows
        guard let parent else { return }

        func restoreToSavedWorkspacePosition() async throws {
            let workspaceRect = nodeWorkspace.workspaceMonitor.rect
            var newX = workspaceRect.topLeftX + workspaceRect.width * prevUnhiddenProportionalPositionInsideWorkspaceRect.x
            var newY = workspaceRect.topLeftY + workspaceRect.height * prevUnhiddenProportionalPositionInsideWorkspaceRect.y
            let windowWidth = lastKnownActualRect?.width ?? lastFloatingSize?.width ?? 0
            let windowHeight = lastKnownActualRect?.height ?? lastFloatingSize?.height ?? 0
            newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
            newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))
            let size = CGSize(width: windowWidth, height: windowHeight)
            _ = try await restoreFromCorner(to: CGRect(x: newX, y: newY, width: size.width, height: size.height), resize: false)
        }

        switch getChildParentRelation(child: self, parent: parent) {
            // Just a small optimization to avoid unnecessary AX calls for non floating windows
            // Tiling windows should be unhidden with layoutRecursive anyway
            case .floatingWindow:
                try await restoreToSavedWorkspacePosition()
            case .tiling:
                WindowMotion.shared.snapOnNextLayout(windowId)
            case .macosNativeFullscreenWindow, .macosNativeHiddenAppWindow, .macosNativeMinimizedWindow,
                 .macosPopupWindow, .rootTilingContainer, .shimContainerRelation: break
        }

    }

    @MainActor
    @discardableResult
    func restoreFromCorner(to target: CGRect, resize: Bool = true) async throws -> Bool {
        guard isHiddenInCorner, let workspace = nodeWorkspace else { return false }
        let token = workspaceReveal.begin()
        if !isUnitTest { WindowBorderController.shared.remove(windowId: windowId) }
        // Once a reveal starts, the old parking coordinates no longer describe
        // the native window. A later outgoing transition must park it again.
        hiddenInCorner = nil
        WorkspaceTransitionDiagnostics.record("restore-begin", window: self, generation: token, requested: target)
        do {
            try await setAxFrameBlocking(target.origin, resize ? target.size : nil, positionFirst: true)
            try checkCancellation()
            // AX success alone does not mean the app accepted the requested position.
            let actual = try await macApp.getAxRect(windowId)
            try checkCancellation()
            let matches = actual.map { abs($0.topLeftX - target.minX) <= 2 && abs($0.topLeftY - target.minY) <= 2 } ?? false
            let current = nodeWorkspace === workspace && (workspace.isVisible || !TrayMenuModel.shared.isEnabled)
            guard workspaceReveal.finish(token, succeeded: matches && current) else {
                lastAppliedLayoutPhysicalRect = nil
                WorkspaceTransitionDiagnostics.record("restore-pending", window: self, generation: token, requested: target)
                return false
            }
            preserveRestoredWorkspacePreview = false
            prevUnhiddenProportionalPositionInsideWorkspaceRect = nil
            hiddenInCorner = nil
            WorkspaceTransitionDiagnostics.record("restore-end", window: self, generation: token, requested: target)
            return true
        } catch {
            _ = workspaceReveal.finish(token, succeeded: false)
            lastAppliedLayoutPhysicalRect = nil
            WorkspaceTransitionDiagnostics.record("restore-cancelled-or-failed", window: self, generation: token, requested: target)
            throw error
        }
    }

    override var isHiddenInCorner: Bool {
        prevUnhiddenProportionalPositionInsideWorkspaceRect != nil
    }

    override func getAxSize() async throws -> CGSize? {
        try await macApp.getAxSize(windowId)
    }

    @MainActor
    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        WindowMotion.shared.cancel(windowId)
        guard !WindowRecoveryController.shared.suppressAutomaticFrameWrites else { return }
        if nodeWorkspace?.scrollingGestureMotionActive == true, let session = nodeWorkspace?.scrollingGestureSessionID,
           let topLeft, let size {
            setScrollingGestureFrame(CGRect(origin: topLeft, size: size), session: session)
            return
        }
        WindowRecoveryController.shared.recordBeforeMutation(self, originalRect: lastKnownActualRect)
        macApp.setAxFrame(windowId, topLeft, size)
        // Reasserting an unchanged layout must neither flood AX with observations nor
        // continually cancel the confirmation already waiting for that same request.
        if let previous = minimumRequest, previous.point == topLeft, previous.size == size { return }
        minimumRequest = (topLeft, size)
        frameRequestGeneration &+= 1
        minimumObservation?.cancel()
        guard let topLeft, let size, parent is TilingContainer, !isFullscreen,
              !isConcealedByScrolling,
              TrayMenuModel.shared.isEnabled, lastKnownActualRect?.size != size else { return }
        let generation = frameRequestGeneration
        minimumObservation = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                guard let self, self.canObserveMinimum(generation) else { return }
                let fullscreen = try await self.isMacosFullscreen
                let minimized = try await self.isMacosMinimized
                guard shouldLearnWindowMinimum(nativeFullscreen: fullscreen, nativeMinimized: minimized,
                                               animating: WindowMotion.shared.isAnimating(self.windowId)),
                      let first = try await self.macApp.getAxRectForLayoutConfirmation(self.windowId) else { return }
                try await Task.sleep(nanoseconds: 150_000_000)
                guard self.canObserveMinimum(generation),
                      let confirmed = try await self.macApp.getAxRectForLayoutConfirmation(self.windowId),
                      self.canObserveMinimum(generation),
                      abs(first.topLeftCorner.x - topLeft.x) <= 2,
                      abs(first.topLeftCorner.y - topLeft.y) <= 2,
                      abs(confirmed.topLeftCorner.x - topLeft.x) <= 2,
                      abs(confirmed.topLeftCorner.y - topLeft.y) <= 2 else { return }
                // Native fullscreen/minimize can start between the two samples.
                let confirmedFullscreen = try await self.isMacosFullscreen
                let confirmedMinimized = try await self.isMacosMinimized
                guard self.canObserveMinimum(generation),
                      shouldLearnWindowMinimum(nativeFullscreen: confirmedFullscreen, nativeMinimized: confirmedMinimized,
                                               animating: WindowMotion.shared.isAnimating(self.windowId)) else { return }
                let oldMinimum = self.learnedMinimum.size
                self.learnedMinimum.observe(requested: size, first: first.size, confirmed: confirmed.size)
                if runtime.workspaceBackend.kind == .native, self.learnedMinimum.size != oldMinimum {
                    runtime.workspaceBackend.observation?.requestRead(event: "nativeMinimumChanged")
                }
                if !isUnitTest { PersistedAppMinimums.shared.remember(self.learnedMinimum.size, for: self.macApp.rawAppBundleId) }
                WindowMotion.shared.noteLanded(self.windowId,
                    asked: CGRect(origin: topLeft, size: size),
                    got: CGRect(origin: confirmed.topLeftCorner, size: confirmed.size))
            } catch {
                // Cancellation, closed windows and failed AX reads are not minimum-size evidence.
            }
        }
    }

    @MainActor
    func setScrollingGestureFrame(_ frame: CGRect, session: UUID? = nil) {
        guard let workspace = nodeWorkspace, workspace.scrollingGestureMotionActive,
              let session = session ?? workspace.scrollingGestureSessionID else { return }
        suspendMinimumObservationForMotion()
        guard !WindowRecoveryController.shared.suppressAutomaticFrameWrites else { return }
        WindowRecoveryController.shared.recordBeforeMutation(self, originalRect: lastKnownActualRect)
        macApp.setAnimatedAxFrame(windowId, frame, session: session)
    }

    @MainActor
    private func canObserveMinimum(_ generation: UInt64) -> Bool {
        !Task.isCancelled && frameRequestGeneration == generation &&
            MacWindow.allWindowsMap[windowId] === self && parent is TilingContainer &&
            !isFullscreen && !WindowMotion.shared.isAnimating(windowId) && TrayMenuModel.shared.isEnabled &&
            !isConcealedByScrolling && nodeWorkspace?.scrollingGestureMotionActive != true &&
            !WindowRecoveryController.shared.isRecovering &&
            !WindowRecoveryController.shared.suppressAutomaticFrameWrites
    }

    @MainActor
    func suspendMinimumObservationForMotion() {
        frameRequestGeneration &+= 1
        minimumObservation?.cancel()
        minimumObservation = nil
        minimumRequest = nil
    }

    @MainActor
    func setAxFrameBlocking(_ topLeft: CGPoint?, _ size: CGSize?, positionFirst: Bool = false) async throws {
        WindowMotion.shared.cancel(windowId)
        frameRequestGeneration &+= 1
        minimumObservation?.cancel()
        minimumRequest = nil
        WindowRecoveryController.shared.recordBeforeMutation(self, originalRect: lastKnownActualRect)
        try await macApp.setAxFrameBlocking(windowId, topLeft, size, positionFirst: positionFirst)
    }

    @MainActor
    override func getAxRect() async throws -> Rect? {
        let observationToken = await nativeStateObservationToken()
        let rect = try await macApp.getAxRect(windowId)
        let windowId = self.windowId
        await MainActor.run {
            Window.get(byId: windowId)?.recordObservedActualRect(rect, token: observationToken)
        }
        return rect
    }
}
