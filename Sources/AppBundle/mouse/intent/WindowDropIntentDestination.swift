import Common
import CoreGraphics

@MainActor
func destinationFromWindowDropIntent(
    _ resolution: WindowDropIntentResolution,
    sourceWindow: Window,
    targetWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    windowDragArrangement(for: targetWindow.nodeWorkspace)
        .dropIntentDestination(resolution: resolution, sourceWindow: sourceWindow, targetWindow: targetWindow,
                               mouseLocation: mouseLocation, subject: subject, detachOrigin: detachOrigin)
        .map { windowDropIntentOverlayDestination($0, resolution: resolution) }
}

/// A destination's overlay for the drop zone it came from: the active zone's frame, and the
/// zones the target says are unavailable.
@MainActor
func windowDropIntentOverlayDestination(
    _ destination: WindowDragIntentDestination,
    resolution: WindowDropIntentResolution,
) -> WindowDragIntentDestination {
    var result = destination
    result.previewRect = windowDropIntentActivePreviewRect(for: resolution)
    result.interactionRect = resolution.targetFrame
    result.dropIntentOverlay = WindowDropIntentOverlayModel(
        targetFrame: resolution.targetFrame,
        activeZone: resolution.intent.zone,
        cornerRadius: resolution.targetCornerRadius.map(CGFloat.init),
        unavailableZones: destination.dropIntentOverlay?.unavailableZones ?? [],
        unavailableReason: destination.dropIntentOverlay?.unavailableReason,
    )
    return result
}

func windowDropIntentActivePreviewRect(for resolution: WindowDropIntentResolution) -> Rect {
    resolution.zones.first { $0.zone == resolution.intent.zone }?.frame ?? resolution.targetFrame
}

@MainActor
func resolveWindowDropIntent(
    sourceWindow: Window,
    targetWindow: Window,
    targetNode: TreeNode,
    mouseLocation: CGPoint,
) -> WindowDropIntentResolution? {
    let targetFrame: Rect?
    if let tabGroup = targetNode as? TilingContainer, tabGroup.layout == .tabGroup {
        targetFrame = tabGroup.lastAppliedLayoutPhysicalRect
    } else {
        targetFrame = targetNode.windowDragVisibleRect
    }
    guard let targetFrame else { return nil }
    return WindowDropIntentResolver().resolve(
        sourceWindowId: sourceWindow.windowId,
        targetWindowId: targetWindow.windowId,
        pointer: mouseLocation,
        targetFrame: targetFrame,
    )
}
