import AppKit
import Common

@MainActor
func dwindleDirectionalFocusTarget(
    from current: Window,
    direction: CardinalDirection,
    excludingMoveNode: TreeNode? = nil,
) -> Window? {
    guard let workspace = current.nodeWorkspace
    else { return nil }
    let frames = dwindleFocusFrames(in: workspace)
    guard let currentRect = frames[current.windowId] else { return nil }
    let candidates = workspace.rootTilingContainer.allLeafWindowsRecursive.compactMap { window -> (Window, [CGFloat])? in
        guard window != current,
              window.moveNode != excludingMoveNode,
              window.participatesInWorkspaceFocus,
              let rect = frames[window.windowId]
        else { return nil }

        let deltaX = rect.center.x - currentRect.center.x
        let deltaY = rect.center.y - currentRect.center.y
        let primaryDelta = direction.orientation == .h ? deltaX : deltaY
        guard (direction.isPositive ? primaryDelta > 0 : primaryDelta < 0) else { return nil }

        let primaryGap: CGFloat
        if direction.orientation == .h {
            primaryGap = direction == .right
                ? max(0, rect.minX - currentRect.maxX)
                : max(0, currentRect.minX - rect.maxX)
        } else {
            primaryGap = direction == .down
                ? max(0, rect.minY - currentRect.maxY)
                : max(0, currentRect.minY - rect.maxY)
        }
        let overlap = direction.orientation == .h
            ? min(currentRect.maxY, rect.maxY) - max(currentRect.minY, rect.minY)
            : min(currentRect.maxX, rect.maxX) - max(currentRect.minX, rect.minX)
        guard overlap > 0 else { return nil }
        let crossDelta = direction.orientation == .h ? rect.center.y - currentRect.center.y : deltaX
        // Only aligned slots qualify; prefer their nearest edge, then center.
        return (window, [primaryGap, abs(crossDelta), abs(primaryDelta)])
    }

    return candidates.min { lhs, rhs in
        if lhs.1 != rhs.1 { return lhs.1.lexicographicallyPrecedes(rhs.1) }
        return lhs.0.windowId < rhs.0.windowId
    }?.0
}

/// Directional selection uses logical slots; hidden tabs stay on explicit tab commands.
@MainActor
func dwindleFocusFrames(in workspace: Workspace) -> [UInt32: Rect] {
    let geometry = dwindleGeometry(in: workspace)
    return Dictionary(uniqueKeysWithValues: workspace.rootTilingContainer.allLeafWindowsRecursive.compactMap { window in
        geometry[ObjectIdentifier(window)].map { (window.windowId, $0) }
    })
}
