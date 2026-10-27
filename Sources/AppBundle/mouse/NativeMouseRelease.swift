import AppKit
import Common

enum NativeMouseReleaseOutcome: Equatable {
    case none, resized, swapped(with: UInt32)
}

/// Native mode has no live drag driver; the layout pauses while a button is down.
/// On release, a tiled window the user resized keeps its new size through the same
/// weight changes as a virtual mouse resize, and one dropped onto another tile on
/// its desktop swaps with it. Anything else snaps back on the next layout.
@MainActor
func adoptNativeMouseRelease(_ window: Window, actual: Rect, pointer: CGPoint) -> NativeMouseReleaseOutcome {
    guard window.parent is TilingContainer, let workspace = window.nodeWorkspace, workspace.isVisible,
          let target = window.lastAppliedLayoutPhysicalRect else { return .none }
    defer { workspace.rootTilingContainer.resetResizeWeightBeforeResizeRecursive() }
    let resized = abs(actual.width - target.width) > 5 || abs(actual.height - target.height) > 5
    if resized {
        if abs(actual.width - target.width) > 1, applySingleWindowManualResize(window, width: actual.width) { return .resized }
        guard let weightMap = proposedResizeWeightMap(window, rect: actual) else { return .none }
        for change in weightMap.changes { change.node.setWeight(change.orientation, change.weight) }
        for change in weightMap.dwindleChanges { change.container.setDwindleSplitRatio(change.ratio, at: change.index) }
        return weightMap.changes.isEmpty && weightMap.dwindleChanges.isEmpty ? .none : .resized
    }
    guard hypot(actual.center.x - target.center.x, actual.center.y - target.center.y) > 30,
          let drop = workspace.allLeafWindowsRecursive.first(where: {
              $0 !== window && $0.parent is TilingContainer && $0.nativeLayoutEligible &&
                  $0.lastAppliedLayoutPhysicalRect?.contains(pointer) == true
          }) else { return .none }
    swapNodes(window, drop)
    return .swapped(with: drop.windowId)
}
