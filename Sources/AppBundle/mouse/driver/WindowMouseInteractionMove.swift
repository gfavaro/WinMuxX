import AppKit
import Common

extension WindowMouseInteractionDriver {
    func beginCompositedMovePreview(sourceWindow: Window, session: MoveSession) {
        guard session.subject == .group else {
            clearMovePreview()
            return
        }
        guard let anchorRect = draggedWindowAnchorRect(for: sourceWindow.windowId) ??
            resolvedDraggedWindowAnchorRect(for: sourceWindow, subject: session.subject),
            anchorRect.width > 0,
            anchorRect.height > 0
        else {
            clearMovePreview()
            return
        }
        let mouseLocation = MousePointerTracker.shared.currentSample.point
        dragSourcePreviewState = DragSourcePreviewState(
            windowId: sourceWindow.windowId,
            subject: session.subject,
            anchorRect: anchorRect,
            mouseOffset: CGPoint(x: mouseLocation.x - anchorRect.topLeftX, y: mouseLocation.y - anchorRect.topLeftY)
        )
        updateCompositedMovePreview(sourceWindow: sourceWindow, mouseLocation: mouseLocation)
    }

    func updateCompositedMovePreview(sourceWindow: Window, mouseLocation: CGPoint) {
        guard let state = dragSourcePreviewState,
              state.windowId == sourceWindow.windowId,
              state.subject == .group
        else { return }
        let frame = Rect(
            topLeftX: mouseLocation.x - state.mouseOffset.x,
            topLeftY: mouseLocation.y - state.mouseOffset.y,
            width: state.anchorRect.width,
            height: state.anchorRect.height,
        )
        guard let item = windowDragSourcePreviewItem(window: sourceWindow, subject: state.subject, frame: frame)
        else { return }
        if let stableFrame = windowResizePreviewAllScreensFrame() {
            WindowResizePreviewPanel.shared.beginStableFrame(stableFrame)
        } else {
            WindowResizePreviewPanel.shared.endStableFrame()
        }
        WindowResizePreviewPanel.shared.show([item])
    }
}

extension WindowMouseInteractionDriver {
    func renderMoveFrame(force: Bool) {
        guard let session = moveSession else { return }
        guard (isLeftMouseButtonDown || force), getCurrentMouseManipulationKind() == .move else { return }
        guard currentlyManipulatedWithMouseWindowId == session.windowId,
              let sourceWindow = Window.get(byId: session.windowId)
        else {
            clearPendingWindowDragIntent()
            stop()
            return
        }

        let mouse = MousePointerTracker.shared.currentSample.point
        detectShakeIfNeeded(sourceWindow: sourceWindow, session: session)
        updateCompositedMovePreview(sourceWindow: sourceWindow, mouseLocation: mouse)
        let isPointerInsideSidebar = WorkspaceSidebarPanel.panel(containing: mouse) != nil
        let shouldProcess = session.startedInSidebar || isPointerInsideSidebar || WindowDragFrameGate.shared.shouldProcess(
            windowId: sourceWindow.windowId,
            point: mouse,
            force: force,
        )
        let gateState = WindowDragFrameGate.shared.state(for: sourceWindow.windowId)
        logWindowDragHitTestIfNeeded(
            signature: "drag-live:frame:window=\(sourceWindow.windowId):bucket=\(debugDescribeDragPointBucket(mouse)):process=\(shouldProcess):settled=\(gateState?.isSettled.description ?? "nil")",
            "[drag-live] frame window=\(sourceWindow.windowId) subject=\(debugDescribe(session.subject)) origin=\(session.detachOrigin) mouse=\(debugDescribe(mouse)) bucket=\(debugDescribeDragPointBucket(mouse)) shouldProcess=\(shouldProcess) velocity=\(gateState?.velocity.description ?? "nil") settled=\(gateState?.isSettled.description ?? "nil") force=\(force)"
        )
        guard shouldProcess else { return }

        renderManagedMoveFrame(sourceWindow: sourceWindow, mouseLocation: mouse, session: session)
    }

    func renderManagedMoveFrame(sourceWindow: Window, mouseLocation: CGPoint, session: MoveSession) {
        if didToggleLayoutWithShake {
            clearPendingWindowDragIntent()
            if sourceWindow.isFloating {
                moveFloatingWindowWithMouse(sourceWindow)
            }
            return
        }
        if WorkspaceSidebarPanel.panel(containing: mouseLocation) != nil {
            _ = updatePendingWindowDragIntent(
                sourceWindow: sourceWindow,
                mouseLocation: mouseLocation,
                subject: session.subject,
                detachOrigin: session.detachOrigin,
            )
            return
        }
        if session.startedInSidebar {
            refreshActiveWorkspaceSidebarDragPreviewIfNeeded()
            _ = updatePendingWindowDragIntent(
                sourceWindow: sourceWindow,
                mouseLocation: mouseLocation,
                subject: session.subject,
                detachOrigin: session.detachOrigin,
            )
            return
        }
        switch sourceWindow.parent?.cases {
            case .workspace:
                moveFloatingWindowWithMouse(sourceWindow)
            case .tilingContainer:
                _ = updatePendingWindowDragIntent(
                    sourceWindow: sourceWindow,
                    mouseLocation: mouseLocation,
                    subject: session.subject,
                    detachOrigin: session.detachOrigin,
                )
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer, nil:
                clearPendingWindowDragIntent()
        }
    }
}

extension WindowMouseInteractionDriver {
    func startMove(
        windowId: UInt32,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
        startedInSidebar: Bool,
    ) {
        forgetPendingRestartWindow(windowId)
        let session = MoveSession(
            windowId: windowId,
            subject: subject,
            detachOrigin: detachOrigin,
            startedInSidebar: startedInSidebar,
        )
        let isNewSession = moveSession != session
        if isNewSession {
            WindowDragFrameGate.shared.reset(windowId: windowId)
            shakeGesture = WindowShakeGestureRecognizer()
            didToggleLayoutWithShake = false
        }
        moveSession = session
        WindowMouseInteractionOpacityController.shared.restore()
        if isNewSession {
            configureMoveChrome(windowId: windowId, session: session)
        }
        startDisplayLoop()
        renderMoveFrame(force: isNewSession)
    }

    func configureMoveChrome(windowId: UInt32, session: MoveSession) {
        if session.startedInSidebar {
            clearMovePreview()
            WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
        } else if shouldShowCompositedGroupMovePreview(session: session) {
            WindowTabStripPanelController.shared.hideChromeDuringMouseInteraction(showFrameOnly: false)
            if let sourceWindow = Window.get(byId: windowId) {
                beginCompositedMovePreview(sourceWindow: sourceWindow, session: session)
            }
        } else {
            clearMovePreview()
            WindowTabStripPanelController.shared.showChromeDuringMouseInteraction()
        }
    }

    func clearMovePreview() {
        dragSourcePreviewState = nil
        WindowResizePreviewPanel.shared.endStableFrame()
        WindowResizePreviewPanel.shared.hide(reason: "moveStart.clearMovePreview")
    }
}
