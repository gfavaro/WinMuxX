import AppKit
import Common

struct JoinWithCommand: Command {
    let args: JoinWithCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        let direction = args.direction.val
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let currentWindow = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        guard currentWindow.parent is TilingContainer else {
            return io.err("join-with does not support non-tiling windows")
        }
        if target.workspace.arrangement == .scrolling {
            return joinScrolling(currentWindow, direction: direction, workspace: target.workspace)
        }
        guard let (parent, ownIndex) = currentWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) else {
            io.out("join-with: nothing to do")
            return true
        }
        let joinWithTarget = parent.children[ownIndex + direction.focusOffset]
        let prevBinding = joinWithTarget.unbindFromParent()
        let newParent = TilingContainer(
            parent: parent,
            adaptiveWeight: prevBinding.adaptiveWeight,
            parent.orientation.opposite,
            .tiles,
            index: prevBinding.index,
        )
        currentWindow.unbindFromParent()

        joinWithTarget.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
        currentWindow.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: direction.isPositive ? 0 : INDEX_BIND_LAST)
        return true
    }
}

@MainActor
private func joinScrolling(_ window: Window, direction: CardinalDirection, workspace: Workspace) -> Bool {
    if direction.orientation == .v {
        let group = window.topLevelWorkspaceGroup
        guard let (parent, ownIndex) = window.closestParent(hasChildrenInDirection: direction, withLayout: nil),
              parent !== workspace.rootTilingContainer,
              parent === group || parent.parents.contains(where: { $0 === group }) else { return false }
        let targetIndex = ownIndex + direction.focusOffset
        guard parent.children.indices.contains(targetIndex) else { return false }
        return joinScrollingNodes(window.moveNode, with: parent.children[targetIndex], in: parent,
                                  direction: direction, width: nil)
    }
    let sourceColumn = window.topLevelWorkspaceGroup
    guard let initialRoot = sourceColumn.parent as? TilingContainer,
          initialRoot === workspace.rootTilingContainer,
          let sourceIndex = initialRoot.children.firstIndex(where: { $0 === sourceColumn }) else { return false }
    let neighborIndex = sourceIndex + direction.focusOffset
    guard initialRoot.children.indices.contains(neighborIndex) else { return false }
    let neighbor = initialRoot.children[neighborIndex]
    return joinScrollingNodes(window.moveNode, with: neighbor, in: initialRoot, direction: direction,
                              width: neighbor.scrollingColumnWidth, workspace: workspace)
}

@MainActor
private func joinScrollingNodes(_ source: TreeNode, with target: TreeNode, in parent: TilingContainer,
                                direction: CardinalDirection, width: CGFloat?, workspace: Workspace? = nil) -> Bool {
    let adoptedWidth = width
    source.unbindFromParent()
    // An atomic tab/accordion root becomes an ordinary column if a second
    // column is explicitly added; the old container remains nested intact.
    let host = workspace.map { ensureScrollingRootSupportsColumns($0) } ?? parent
    guard let currentTargetIndex = host.children.firstIndex(where: { $0 === target }) else { return false }
    let targetBinding = target.unbindFromParent()
    // The pair takes the target's place; the source may have come from another container.
    let insertion = currentTargetIndex
    let joined = TilingContainer(parent: host, adaptiveWeight: targetBinding.adaptiveWeight,
                                 parent.orientation.opposite, .tiles, index: insertion)
    joined.scrollingColumnWidth = adoptedWidth
    let sourceFirst = direction.isPositive
    (sourceFirst ? source : target).bind(to: joined, adaptiveWeight: WEIGHT_AUTO, index: 0)
    (sourceFirst ? target : source).bind(to: joined, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    workspace?.normalizeContainers()
    scheduleRefreshSession(.globalObserver("joinScrolling"))
    return true
}
