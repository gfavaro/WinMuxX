@testable import AppBundle
import Common
import Foundation
import TOMLKit

extension [TomlParseError] {
    var descriptions: [String] { map(\.description) }
}

// Shorthands for what the app does inline, so tests can drive one step at a time.

@MainActor
@discardableResult
func navigateWorkspaceBySwipe(on monitor: Monitor, isNext: Bool) -> Bool {
    guard let target = workspaceSwipeTarget(on: monitor, isNext: isNext) else { return false }
    return activateWorkspaceForUser(target, on: monitor)
}

func matchRestartWindow(
    id: UInt32,
    identity: RestartWindowIdentity,
    saved: [FrozenWindow],
    live: [(UInt32, RestartWindowIdentity)]
) -> UInt32? {
    matchRestartWindowIndex(id: id, identity: identity, saved: saved, live: live).map { saved[$0].id }
}

@MainActor
func debugPendingWindowDragIntentSummary() -> (kind: WindowDragIntentKind, previewRect: Rect, interactionRect: Rect)? {
    guard let pendingWindowDragIntent else { return nil }
    return (
        kind: pendingWindowDragIntent.kind,
        previewRect: pendingWindowDragIntent.previewRect,
        interactionRect: pendingWindowDragIntent.interactionRect,
    )
}

@MainActor
func shouldBringActivatedWindowHere(_ window: Window, activation: RefreshActivationContext?) -> Bool {
    bringActivatedWindowHereVerdict(window, activation: activation) == nil
}

@MainActor
func deleteWorkspaceProject(_ projectId: WorkspaceProjectId) throws {
    try deleteWorkspaceProjectMovingWindowsToFallback(projectId)
}
