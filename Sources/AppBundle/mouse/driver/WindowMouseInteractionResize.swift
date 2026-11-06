import AppKit
import Common

extension WindowMouseInteractionDriver {
    func calibrateResizeGesture(window: Window, session: ResizeSession, force: Bool) {
        guard force || !isResizeSampleInFlight else { return }
        isResizeSampleInFlight = true
        let sessionWindowId = session.windowId
        let sample = MousePointerTracker.shared.currentSample
        Task { @MainActor in
            defer { isResizeSampleInFlight = false }
            guard resizeSession?.windowId == sessionWindowId, isLeftMouseButtonDown else { return }
            guard let rect = try? await window.getAxRect() else { return }
            guard resizeSession?.windowId == sessionWindowId, isLeftMouseButtonDown else { return }
            updateCalibratedResizeGesture(
                window: window,
                rect: rect,
                sessionWindowId: sessionWindowId,
                initialSample: sample,
            )
        }
    }

    func updateCalibratedResizeGesture(
        window: Window,
        rect: Rect,
        sessionWindowId: UInt32,
        initialSample: MousePointerSample,
    ) {
        let freshSample = MousePointerTracker.shared.currentSample
        if var gesture = resizeGesture, gesture.windowId == sessionWindowId {
            gesture.calibrate(observedRect: rect, mouse: freshSample.point, timestamp: freshSample.timestamp)
            resizeGesture = gesture
            updateResizePreviewIfNeeded(window: window, rect: gesture.predictedRect(mouse: freshSample.point))
        } else if let gesture = makeResizeGesture(window: window, observedRect: rect, sample: initialSample) {
            resizeGesture = gesture
            updateResizePreviewIfNeeded(window: window, rect: gesture.predictedRect(mouse: freshSample.point), force: true)
        } else {
            updateResizePreviewIfNeeded(window: window, rect: rect, force: true)
        }
    }
}

extension WindowMouseInteractionDriver {
    func makePendingResizeCandidate() async -> PendingResizeCandidate? {
        // The candidate is best-effort calibration data: makeResizeGesture discards it unless
        // its windowId matches the window that actually reports resize events (which is
        // re-verified live there). So the logical focus is good enough here, and it avoids a
        // getNativeFocusedWindow AX round-trip to the focused app on every single left click.
        guard getCurrentMouseManipulationKind() == .none,
              let window = focus.windowOrNil,
              window.parent is TilingContainer,
              !window.isHiddenInCorner
        else { return nil }
        let sample = MousePointerTracker.shared.currentSample
        guard cachedResizeCandidateIsViable(window: window, sample: sample) else { return nil }
        let cachedRect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect
        guard let observedRect = (try? await window.getAxRect()) ?? cachedRect else { return nil }
        let baseRect = window.lastAppliedLayoutPhysicalRect ?? observedRect
        let edges = resizeGestureCandidateEdges(mouse: sample.point, rect: observedRect)
        guard edges.hasAny else { return nil }
        return PendingResizeCandidate(
            windowId: window.windowId,
            baseRect: baseRect,
            observedRect: observedRect,
            edges: edges,
            mouseSample: sample,
        )
    }

    func cachedResizeCandidateIsViable(window: Window, sample: MousePointerSample) -> Bool {
        guard let cachedRect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect else { return true }
        return resizeGestureCandidateEdges(mouse: sample.point, rect: cachedRect).hasAny
    }
}

extension WindowMouseInteractionDriver {
    func capturePendingResizeCandidate() async {
        guard let candidate = await makePendingResizeCandidate() else {
            pendingResizeCandidate = nil
            return
        }
        pendingResizeCandidate = candidate
    }

    func makeResizeGesture(window: Window, observedRect: Rect?, sample: MousePointerSample) -> ResizeGestureSessionState? {
        guard let observedRect = observedRect ?? window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect else { return nil }
        if let pendingResizeCandidate,
           pendingResizeCandidate.windowId == window.windowId
        {
            return makeResizeGestureSession(
                windowId: window.windowId,
                baseRect: pendingResizeCandidate.baseRect,
                observedRect: pendingResizeCandidate.observedRect,
                mouse: pendingResizeCandidate.mouseSample.point,
                edges: pendingResizeCandidate.edges,
                timestamp: pendingResizeCandidate.mouseSample.timestamp,
            )
        }
        return makeResizeGestureFromObservedRect(window: window, observedRect: observedRect, sample: sample)
    }

    func makeResizeGestureFromObservedRect(
        window: Window,
        observedRect: Rect,
        sample: MousePointerSample,
    ) -> ResizeGestureSessionState? {
        let baseRect = window.lastAppliedLayoutPhysicalRect ?? observedRect
        return makeResizeGestureSession(
            windowId: window.windowId,
            baseRect: baseRect,
            observedRect: observedRect,
            mouse: sample.point,
            edges: resizeGestureEdges(baseRect: baseRect, observedRect: observedRect, mouse: sample.point),
            timestamp: sample.timestamp,
        )
    }
}

extension WindowMouseInteractionDriver {
    func beginStableResizePreviewFrame(for window: Window) {
        guard let workspace = window.nodeWorkspace else { return }
        WindowResizePreviewPanel.shared.beginStableFrame(workspace.workspaceMonitor.rect.toAppKitScreenRect)
    }

    func updateResizePreviewIfNeeded(window: Window, rect: Rect, force: Bool = false) {
        guard force || resizePreviewHasVisibleChange(from: lastRenderedResizePreviewRect, to: rect) else { return }
        lastRenderedResizePreviewRect = rect
        updateCompositedResizePreview(window, rect: rect)
    }
}

func resizePreviewHasVisibleChange(from previous: Rect?, to next: Rect) -> Bool {
    guard let previous else { return true }
    return abs(previous.topLeftX - next.topLeftX) >= resizePreviewVisibleChangeThreshold ||
        abs(previous.topLeftY - next.topLeftY) >= resizePreviewVisibleChangeThreshold ||
        abs(previous.width - next.width) >= resizePreviewVisibleChangeThreshold ||
        abs(previous.height - next.height) >= resizePreviewVisibleChangeThreshold
}

extension WindowMouseInteractionDriver {
    func sampleResizeFrame(force: Bool) {
        guard let session = resizeSession else {
            logWindowDragLive("resize.sample skipped reason=no-session force=\(force) mouseDown=\(isLeftMouseButtonDown) kind=\(getCurrentMouseManipulationKind())")
            return
        }
        guard isLeftMouseButtonDown, getCurrentMouseManipulationKind() == .resize else {
            logWindowDragLive("resize.sample skipped reason=inactive session=\(session.windowId) force=\(force) mouseDown=\(isLeftMouseButtonDown) kind=\(getCurrentMouseManipulationKind())")
            return
        }
        guard let window = Window.get(byId: session.windowId) else {
            logWindowDragLive("resize.sample missing-window session=\(session.windowId); stopping driver")
            stop()
            return
        }

        let sample = MousePointerTracker.shared.currentSample
        if var gesture = resizeGesture, gesture.windowId == session.windowId {
            let rect = gesture.predictedRect(mouse: sample.point)
            logWindowDragLive("resize.sample predicted session=\(session.windowId) force=\(force) mouse=\(debugDescribe(sample.point)) rect=\(debugDescribe(rect))")
            gesture.latestRect = rect
            resizeGesture = gesture
            updateResizePreviewIfNeeded(window: window, rect: rect, force: force)
            if force || sample.timestamp - gesture.lastCalibrationTimestamp >= resizeGestureCalibrationInterval {
                calibrateResizeGesture(window: window, session: session, force: false)
            }
            return
        }

        guard force || !isResizeSampleInFlight else {
            logWindowDragLive("resize.sample skipped reason=calibration-in-flight session=\(session.windowId)")
            return
        }
        logWindowDragLive("resize.sample calibrating session=\(session.windowId) force=\(force)")
        calibrateResizeGesture(window: window, session: session, force: force)
    }

    func finalResizeRect(for session: ResizeSession, window: Window) async -> Rect? {
        if let rect = try? await window.getAxRect() {
            return rect
        }
        if let resizeGesture, resizeGesture.windowId == session.windowId {
            return resizeGesture.predictedRect(mouse: MousePointerTracker.shared.currentSample.point)
        }
        return window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect
    }
}

extension WindowMouseInteractionDriver {
    func startResize(windowId: UInt32) {
        forgetPendingRestartWindow(windowId)
        let session = ResizeSession(windowId: windowId)
        let isNewSession = resizeSession != session
        logWindowDragLive("resize.start window=\(windowId) isNewSession=\(isNewSession) existingSession=\(String(describing: resizeSession)) mouseDown=\(isLeftMouseButtonDown) kind=\(getCurrentMouseManipulationKind())")
        if isNewSession {
            resetResizeTrackingState()
            clearPendingWindowDragIntent()
        }
        resizeSession = session
        currentlyManipulatedWithMouseWindowId = windowId
        WindowMouseInteractionOpacityController.shared.update(
            activeWindowId: windowId,
            hidesPassiveTabGroupChrome: true,
        )
        setCurrentMouseManipulationKind(.resize)
        configureResizeChrome(windowId: windowId)
        startDisplayLoop()
        sampleResizeFrame(force: true)
    }

    func configureResizeChrome(windowId: UInt32) {
        guard let window = Window.get(byId: windowId) else {
            logWindowDragLive("resize.configureChrome missing-window window=\(windowId)")
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction()
            return
        }
        logWindowDragLive("resize.configureChrome window=\(windowId) lastKnown=\(debugDescribe(window.lastKnownActualRect)) lastApplied=\(debugDescribe(window.lastAppliedLayoutPhysicalRect))")
        WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: false)
        if resizeGesture == nil {
            let sample = MousePointerTracker.shared.currentSample
            resizeGesture = makeResizeGesture(window: window, observedRect: window.lastKnownActualRect, sample: sample)
        }
        guard let rect = resizeGesture?.predictedRect(mouse: MousePointerTracker.shared.currentSample.point) ??
            window.lastAppliedLayoutPhysicalRect ??
            window.lastKnownActualRect
        else { return }
        beginStableResizePreviewFrame(for: window)
        updateResizePreviewIfNeeded(window: window, rect: rect, force: true)
    }

    func resetResizeTrackingState() {
        resizeGesture = nil
        isResizeSampleInFlight = false
        isMouseUpResetScheduled = false
        lastRenderedResizePreviewRect = nil
    }
}
