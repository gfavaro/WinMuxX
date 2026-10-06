import AppKit
import Common

private let shakeToggleCooldown: TimeInterval = 1.25

extension WindowMouseInteractionDriver {
    func detectShakeIfNeeded(sourceWindow: Window, session: MoveSession) {
        guard config.enableShakeToToggleTiling,
              !didToggleLayoutWithShake,
              shouldRecognizeWindowShake(
                  kind: getCurrentMouseManipulationKind(),
                  subject: session.subject,
                  detachOrigin: session.detachOrigin,
                  startedInSidebar: session.startedInSidebar,
                  isPointerInsideSidebar: WorkspaceSidebarPanel.panel(
                      containing: MousePointerTracker.shared.currentSample.point
                  ) != nil,
              ),
              var gesture = shakeGesture
        else { return }
        let sample = MousePointerTracker.shared.currentSample
        guard gesture.observe(sample) else {
            shakeGesture = gesture
            return
        }
        shakeGesture = gesture
        let state = sourceWindow.shakeWindowState
        guard sample.timestamp - state.lastToggleTimestamp >= shakeToggleCooldown else { return }

        clearPendingWindowDragIntent()
        toggleFloatingForShake(sourceWindow)
        state.lastToggleTimestamp = sample.timestamp
        didToggleLayoutWithShake = true
    }

    func toggleFloatingForShake(_ window: Window) {
        guard let workspace = window.nodeWorkspace else { return }
        let state = window.shakeWindowState
        if window.isFloating {
            if let placement = state.tilingPlacement,
               let parent = placement.parent,
               parent.isBound,
               parent.nodeWorkspace === workspace
            {
                window.bind(
                    to: parent,
                    adaptiveWeight: placement.adaptiveWeight,
                    index: min(placement.index, parent.children.count),
                )
            } else {
                let placement = bindingDataForNewTilingWindow(workspace, window: window)
                window.bind(to: placement.parent, adaptiveWeight: placement.adaptiveWeight, index: placement.index)
            }
            state.tilingPlacement = nil
        } else {
            window.lastFloatingSize = window.lastKnownActualRect?.size ??
                window.lastAppliedLayoutPhysicalRect?.size ??
                window.lastFloatingSize
            if let placement = window.bindAsFloatingWindow(to: workspace) {
                state.tilingPlacement = WindowShakeTilingPlacement(placement)
            }
        }
        window.lastAppliedLayoutPhysicalRect = nil
    }
}
