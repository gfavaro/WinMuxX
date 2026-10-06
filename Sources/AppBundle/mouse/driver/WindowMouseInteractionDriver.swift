import AppKit
import Common

let resizeGestureCalibrationInterval: TimeInterval = 1.0 / 30.0
let resizePreviewVisibleChangeThreshold = CGFloat(0.5)

@MainActor
final class WindowMouseInteractionDriver {
    static let shared = WindowMouseInteractionDriver()

    struct MoveSession: Equatable {
        let windowId: UInt32
        let subject: WindowDragSubject
        let detachOrigin: TabDetachOrigin
        let startedInSidebar: Bool
    }

    struct ResizeSession: Equatable {
        let windowId: UInt32
    }

    struct PendingResizeCandidate {
        let windowId: UInt32
        let baseRect: Rect
        let observedRect: Rect
        let edges: ResizeGestureEdges
        let mouseSample: MousePointerSample
    }

    struct DragSourcePreviewState {
        let windowId: UInt32
        let subject: WindowDragSubject
        let anchorRect: Rect
        let mouseOffset: CGPoint
    }

    var moveSession: MoveSession?
    var resizeSession: ResizeSession?
    var dragSourcePreviewState: DragSourcePreviewState?
    var pendingResizeCandidate: PendingResizeCandidate?
    var resizeGesture: ResizeGestureSessionState?
    var isResizeSampleInFlight = false
    var isMouseUpResetScheduled = false
    var lastRenderedResizePreviewRect: Rect?
    var shakeGesture: WindowShakeGestureRecognizer?
    var didToggleLayoutWithShake = false

    private init() {}
}

extension WindowMouseInteractionDriver {
    func startDisplayLoop() {
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in
            self?.displayFrame()
        }
    }

    func displayFrame() {
        guard isLeftMouseButtonDown else {
            finishAfterMissedMouseUpIfNeeded()
            return
        }
        renderMoveFrame(force: false)
        sampleResizeFrame(force: false)
    }

    func finishAfterMissedMouseUpIfNeeded() {
        guard resizeSession != nil || moveSession != nil else {
            logWindowDragLive("resizePreview hide requested reason=displayLoop.idle mouseDown=\(isLeftMouseButtonDown)")
            DisplayRefreshDriver.shared.remove(owner: self)
            WindowResizePreviewPanel.shared.endStableFrame()
            WindowResizePreviewPanel.shared.hide(reason: "displayLoop.idle")
            return
        }
        guard !isMouseUpResetScheduled else { return }
        isMouseUpResetScheduled = true
        DisplayRefreshDriver.shared.remove(owner: self)
        Task { @MainActor in
            try? await resetManipulatedWithMouseIfPossible()
            isMouseUpResetScheduled = false
        }
    }
}

extension WindowMouseInteractionDriver {
    func noteGlobalDragActivity() {
        if moveSession != nil {
            renderMoveFrame(force: false)
        }
        if resizeSession != nil {
            sampleResizeFrame(force: false)
        }
    }

    func flushBeforeMouseUp() async {
        if moveSession != nil {
            renderMoveFrame(force: true)
        }
        guard let resizeSession else { return }
        defer { finishResizeFlush(session: resizeSession) }
        guard let window = Window.get(byId: resizeSession.windowId) else { return }
        guard let rect = await finalResizeRect(for: resizeSession, window: window) else { return }
        guard self.resizeSession == resizeSession else { return }
        updateResizePreviewIfNeeded(window: window, rect: rect, force: true)
        applyResizeWithMouse(window, rect: rect)
    }

    func stop() {
        logWindowDragLive("driver.stop moveSession=\(String(describing: moveSession)) resizeSession=\(String(describing: resizeSession)) manipulated=\(currentlyManipulatedWithMouseWindowId?.description ?? "nil") kind=\(getCurrentMouseManipulationKind()) mouseDown=\(isLeftMouseButtonDown)")
        DisplayRefreshDriver.shared.remove(owner: self)
        moveSession = nil
        resizeSession = nil
        dragSourcePreviewState = nil
        pendingResizeCandidate = nil
        shakeGesture = nil
        didToggleLayoutWithShake = false
        resetResizeTrackingState()
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "driver.stop")
        WindowMouseInteractionOpacityController.shared.restore()
        WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
    }

    func finishResizeFlush(session: ResizeSession) {
        if resizeSession == session {
            resizeSession = nil
        }
        pendingResizeCandidate = nil
        resetResizeTrackingState()
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "driver.finishResizeFlush")
    }
}
