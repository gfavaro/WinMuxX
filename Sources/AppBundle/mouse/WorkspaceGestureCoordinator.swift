import AppKit

func workspaceGesturesNeedRawTouch(horizontal: Bool, overview: Bool, overviewOpen: Bool, runtimeEnabled: Bool) -> Bool {
    runtimeEnabled && (horizontal || overview || overviewOpen)
}

/// Composition boundary: input lifetime and arbitration stay outside individual features.
@MainActor
final class WorkspaceGestureCoordinator {
    static let shared = WorkspaceGestureCoordinator()
    private var applyingConfiguration = false
    func syncConfiguration() {
        applyingConfiguration = true
        defer { applyingConfiguration = false }
        cancelInteractions()
        RawWorkspaceTouchSource.shared.onFrame = { WorkspaceGestureRouter.shared.handle($0) }
        RawWorkspaceTouchSource.shared.syncConfiguration()
    }
    func reset() {
        cancelInteractions()
        RawWorkspaceTouchSource.shared.updateDemand()
    }
    private func cancelInteractions() {
        WorkspaceScrollingMinimap.shared.dismiss()
        WorkspaceGestureRouter.shared.reset()
        WorkspaceSwipeController.shared.reset()
        WorkspaceOverviewController.shared.invalidate()
    }
    func overviewPresentationChanged() {
        WorkspaceScrollingGestureController.shared.reset()
        if !applyingConfiguration, RawWorkspaceTouchSource.shared.updateDemand() {
            // A source stopped on partial finger lift cannot deliver its final
            // zero-contact frame. Never carry that sequence into a later opening.
            WorkspaceGestureRouter.shared.reset()
        }
    }
}
