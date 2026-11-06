import AppKit

@MainActor var workspaceSwipeGestureEnabled: Bool {
    config.workspaceSwipe.enabled
}
@MainActor var workspaceOverviewGestureEnabled: Bool {
    config.workspaceOverview.threeFingerUp
}

/// Composition boundary: input lifetime and arbitration stay outside individual features.
@MainActor
final class WorkspaceGestureCoordinator {
    static let shared = WorkspaceGestureCoordinator()
    private var trackpadGestures: [Int] = []

    /// macOS's three-finger gesture settings, which decide whether WinMuxX reads macOS's swipes.
    private static func readTrackpadGestures() -> [Int] {
        ["TrackpadThreeFingerHorizSwipeGesture", "TrackpadThreeFingerVertSwipeGesture"].map(macTrackpadGesture)
    }

    /// System Settings changes those gestures without telling other apps, so they are read again
    /// when it stops being frontmost or quits; a change re-routes the swipes.
    func systemSettingsDeactivated() {
        guard Self.readTrackpadGestures() != trackpadGestures else { return }
        syncConfiguration()
    }

    func syncConfiguration() {
        trackpadGestures = Self.readTrackpadGestures()
        cancelInteractions()
        DockWorkspaceSwipeSource.shared.syncConfiguration()
    }
    func reset() {
        cancelInteractions()
    }
    private func cancelInteractions() {
        WorkspaceSwipeController.shared.reset()
        WorkspaceOverviewController.shared.invalidate()
    }
}
