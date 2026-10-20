import AppKit
import Common

extension WorkspaceOverviewController {
    /// Returns false to retain release-only navigation when motion is disabled.
    func beginGesture(opening: Bool, progress: Double) -> Bool {
        guard gestureOpening == nil,
              !dependencies.nativeIntegration || WorkspaceGestureAnimation.duration(
                milliseconds: config.workspaceSwipe.animationDurationMs, enabled: config.animations.enabled,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) != nil else { return false }
        if opening {
            guard !isOpen, show(gestureProgress: progress) else { return false }
        } else {
            guard isOpen else { return false }
        }
        gestureOpening = opening
        updateGesture(progress: progress)
        return true
    }

    func updateGesture(progress: Double) {
        guard isOpen, let opening = gestureOpening, progress.isFinite else { return }
        let visible = opening ? progress : 1 - progress
        for panel in panels { panel.updateGesture(progress: visible) }
    }

    func endGesture(commit: Bool, velocity: Double) {
        guard let opening = gestureOpening else { return }
        gestureOpening = nil
        guard isOpen else { return }
        let speed = velocity.isFinite ? (opening ? velocity : -velocity) : 0
        if opening != commit { dismiss(gestureVelocity: speed) }
        else { for panel in panels { panel.settleGesture(velocity: speed) } }
    }
}
