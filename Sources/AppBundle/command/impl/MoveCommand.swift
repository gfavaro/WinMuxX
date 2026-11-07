import AppKit
import Common

struct MoveCommand: Command {
    let args: MoveCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        let direction = args.direction.val
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let currentWindow = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        let currentNode = currentWindow.moveNode
        // In a Tabbed workspace left and right move the tab along its bar, folded tabs included; past
        // the end, or up and down, it moves into the tab group on that side.
        if target.workspace.arrangement == .tabbed { target.workspace.syncTabbedGroups() }
        if target.workspace.arrangement == .tabbed, currentWindow.parent is TilingContainer,
           let group = target.workspace.tabbedGroup(containing: currentWindow.windowId) {
            let bar = group.barGroup.barWindowIds
            if direction.orientation == .h, let index = bar.firstIndex(of: currentWindow.windowId),
               bar.indices.contains(index + direction.focusOffset) {
                return target.workspace.insertTabbedTab(currentWindow.windowId, intoBarOf: group.barGroup, at: index + direction.focusOffset,
                                                        activate: focus.windowOrNil === currentWindow)
            }
            if let neighbor = target.workspace.tabbedGroup(beside: group, direction) {
                return target.workspace.moveTabbedTab(currentWindow.windowId, into: neighbor)
            }
            return hitWorkspaceBoundaries(currentNode, target.workspace, io, args, direction, env)
        }
        // Inside a strip, left and right reorder its columns; at either end the whole strip moves.
        if direction.orientation == .h, let strip = currentWindow.nearestWindowTabGroup, strip.isWindowStrip,
           let column = currentWindow.directChild(in: strip), let index = column.ownIndex,
           let neighbor = strip.children.getOrNil(atIndex: index + direction.focusOffset) {
            swapNodes(column, neighbor)
            return true
        }
        if target.workspace.arrangement == .master {
            // Swap with the window on that side, as master always did. Master is tracked by its
            // group, so a move between master and stack also hands the master role across.
            if let neighbor = dwindleDirectionalFocusTarget(from: currentWindow, direction: direction, excludingMoveNode: currentNode) {
                swapMasterAware(currentWindow, neighbor, in: target.workspace)
                return true
            }
            // Master slots stay fixed; crossing a pane edge must not wrap the master root
            // in an implicit split. Other displays and the boundary action still apply.
            if args.boundaries == .workspace { return args.boundariesAction == .stop }
            return hitWorkspaceBoundaries(currentNode, target.workspace, io, args, direction, env)
        }
        if currentWindow.nodeWorkspace?.rootTilingContainer.layout == .dwindle,
           let neighbor = dwindleDirectionalFocusTarget(
               from: currentWindow,
               direction: direction,
               excludingMoveNode: currentNode,
           )
        {
            return moveDwindleNode(currentNode, beside: neighbor.moveNode, direction: direction)
        }
        guard let parent = currentNode.parent else { return false }
        switch parent.cases {
            case .tilingContainer(let parent):
                if parent.layout == .dwindle {
                    return moveOut(node: currentNode, direction: direction, io, args, env)
                }
                let indexOfCurrent = currentNode.ownIndex.orDie()
                let indexOfSiblingTarget = indexOfCurrent + direction.focusOffset
                if parent.navigationOrientation == direction.orientation && parent.children.indices.contains(indexOfSiblingTarget) {
                    let siblingTarget = parent.children[indexOfSiblingTarget]
                    if currentNode is TilingContainer || (siblingTarget as? TilingContainer)?.layout == .tabGroup {
                        return moveNodeToSiblingIndex(currentNode, parent, indexOfSiblingTarget)
                    }
                    switch siblingTarget.tilingTreeNodeCasesOrDie() {
                        case .tilingContainer(let topLevelSiblingTargetContainer):
                            return deepMoveIn(node: currentNode, into: topLevelSiblingTargetContainer, moveDirection: direction)
                        case .window: // "swap windows"
                            return moveNodeToSiblingIndex(currentNode, parent, indexOfSiblingTarget)
                    }
                } else {
                    return moveOut(node: currentNode, direction: direction, io, args, env)
                }
            case .workspace: // floating window
                return io.err("moving floating windows isn't yet supported") // todo
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
                return io.err(moveOutMacosUnconventionalWindow)
            case .macosPopupWindowsContainer:
                return false // Impossible
        }
    }
}

@MainActor
@discardableResult
func ensureRootSupportsColumns(_ workspace: Workspace) -> TilingContainer {
    let previousRoot = workspace.rootTilingContainer
    guard previousRoot.layout == .tabGroup else { return previousRoot }
    let orientation = previousRoot.orientation
    previousRoot.unbindFromParent()
    let root = TilingContainer(parent: workspace, adaptiveWeight: WEIGHT_AUTO, orientation, .tiles, index: 0)
    previousRoot.bind(to: root, adaptiveWeight: WEIGHT_AUTO, index: 0)
    return root
}

@MainActor
private func swapMasterAware(_ window: Window, _ neighbor: Window, in workspace: Workspace) {
    let mine = window.topLevelWorkspaceGroup
    let theirs = neighbor.topLevelWorkspaceGroup
    let master = workspace.workspaceLayoutUnits.indices.contains(workspace.masterGroupIndex)
        ? workspace.workspaceLayoutUnits[workspace.masterGroupIndex] : nil
    guard mine !== theirs, master === mine || master === theirs else { return swapWindows(window, neighbor) }
    swapNodes(mine, theirs)
    // The group now in the master's place takes the role.
    let incoming = master === mine ? theirs : mine
    if let index = workspace.workspaceLayoutUnits.firstIndex(where: { $0 === incoming }) { workspace.masterGroupIndex = index }
    scheduleRefreshSession(.globalObserver("moveMaster"))
}

@MainActor
private func moveNodeToSiblingIndex(_ node: TreeNode, _ parent: TilingContainer, _ targetIndex: Int) -> Bool {
    let prevBinding = node.unbindFromParent()
    node.bind(to: parent, adaptiveWeight: prevBinding.adaptiveWeight, index: targetIndex)
    return true
}

@MainActor private func hitWorkspaceBoundaries(
    _ node: TreeNode,
    _ workspace: Workspace,
    _ io: CmdIo,
    _ args: MoveCmdArgs,
    _ direction: CardinalDirection,
    _ env: CmdEnv,
) -> Bool {
    switch args.boundaries {
        case .workspace:
            return hitAllMonitorsOuterFrameBoundaries(node, workspace, args, direction)
        case .allMonitorsOuterFrame:
            guard let (monitors, index) = node.nodeMonitor?.findRelativeMonitor(inDirection: direction) else {
                return io.err("Should never happen. Can't find the current monitor")
            }

            if monitors.indices.contains(index) {
                let focusWindow = node.mostRecentWindowRecursive
                guard let focusWindow else { return false }
                let moveNodeToMonitorArgs = MoveNodeToMonitorCmdArgs(target: .direction(direction))
                    .copy(\.windowId, focusWindow.windowId)
                    .copy(\.focusFollowsWindow, focus.windowOrNil == focusWindow)
                return MoveNodeToMonitorCommand(args: moveNodeToMonitorArgs).run(env, io)
            } else {
                return hitAllMonitorsOuterFrameBoundaries(node, workspace, args, direction)
            }
    }
}

@MainActor private func hitAllMonitorsOuterFrameBoundaries(
    _ node: TreeNode,
    _ workspace: Workspace,
    _ args: MoveCmdArgs,
    _ direction: CardinalDirection,
) -> Bool {
    switch args.boundariesAction {
        case .stop: return true
        case .fail: return false
        case .createImplicitContainer:
            // A Tabbed workspace's tab opens a new group along that edge; the tree kept for other
            // arrangements stays as it was.
            if workspace.arrangement == .tabbed {
                if let window = node as? Window { _ = workspace.moveTabbedTabToEdge(window.windowId, on: direction) }
                return true
            }
            createImplicitContainerAndMoveNode(node, workspace, direction)
            return true
    }
}

private let moveOutMacosUnconventionalWindow = "moving macOS fullscreen, minimized windows and windows of hidden apps isn't yet supported. This behavior is subject to change"

@MainActor private func moveOut(
    node: TreeNode,
    direction: CardinalDirection,
    _ io: CmdIo,
    _ args: MoveCmdArgs,
    _ env: CmdEnv,
) -> Bool {
    let innerMostChild = node.parents.first(where: {
        return switch $0.parent?.cases {
            case .tilingContainer(let parent): parent.navigationOrientation == direction.orientation
            // Stop searching
            case .workspace, .macosMinimizedWindowsContainer, nil, .macosFullscreenWindowsContainer,
                 .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer: true
        }
    }) as? TilingContainer
    guard let innerMostChild else { return false }
    guard let parent = innerMostChild.parent else { return false }
    switch parent.cases {
        case .tilingContainer(let parent):
            check(parent.navigationOrientation == direction.orientation)
            guard let ownIndex = innerMostChild.ownIndex else { return false }
            node.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: ownIndex + direction.insertionOffset)
            return true
        case .workspace(let parent):
            return hitWorkspaceBoundaries(node, parent, io, args, direction, env)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
            return io.err(moveOutMacosUnconventionalWindow)
        case .macosPopupWindowsContainer:
            return false // Impossible
    }
}

@MainActor private func createImplicitContainerAndMoveNode(
    _ node: TreeNode,
    _ workspace: Workspace,
    _ direction: CardinalDirection,
) {
    let prevRoot = workspace.rootTilingContainer
    prevRoot.unbindFromParent()
    // Force tiles layout
    let nextRoot = TilingContainer(parent: workspace, adaptiveWeight: WEIGHT_AUTO, direction.orientation,
        prevRoot.layout == .dwindle ? .dwindle : .tiles, index: 0)
    if prevRoot.layout == .dwindle {
        nextRoot.dwindleOrientation = direction.orientation
        nextRoot.dwindleChildRatios = []
    }
    check(prevRoot != workspace.rootTilingContainer)
    prevRoot.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: 0)
    node.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: direction.insertionOffset)
}

@MainActor private func deepMoveIn(node: TreeNode, into container: TilingContainer, moveDirection: CardinalDirection) -> Bool {
    let deepTarget = container.tilingTreeNodeCasesOrDie().findDeepMoveInTargetRecursive(moveDirection.orientation)
    switch deepTarget {
        case .tilingContainer(let deepTarget):
            node.bind(to: deepTarget, adaptiveWeight: WEIGHT_AUTO, index: 0)
        case .window(let deepTarget):
            guard let parent = deepTarget.parent as? TilingContainer else { return false }
            node.bind(
                to: parent,
                adaptiveWeight: WEIGHT_AUTO,
                index: deepTarget.ownIndex.orDie() + 1,
            )
    }
    return true
}

extension TilingTreeNodeCases {
    @MainActor fileprivate func findDeepMoveInTargetRecursive(_ orientation: Orientation) -> TilingTreeNodeCases {
        return switch self {
            case .window:
                self
            case .tilingContainer(let container):
                if container.navigationOrientation == orientation {
                    .tilingContainer(container)
                } else {
                    container.mostRecentChild.orDie("Empty containers must be detached during normalization")
                        .tilingTreeNodeCasesOrDie()
                        .findDeepMoveInTargetRecursive(orientation)
                }
        }
    }
}

extension Window {
    @MainActor
    var moveNode: TreeNode {
        // In a Tabbed workspace a window moves as its own tab, even inside a tab group the tree
        // keeps underneath: its siblings there are tabs of their own.
        if parent is TilingContainer, nodeWorkspace?.arrangement == .tabbed {
            return self
        } else if let parent = parent as? TilingContainer, parent.layout == .tabGroup {
            return parent
        } else {
            return self
        }
    }
}

@MainActor
private func moveDwindleNode(_ node: TreeNode, beside neighbor: TreeNode, direction: CardinalDirection) -> Bool {
    guard let parent = neighbor.parent as? TilingContainer,
          !neighbor.parents.contains(where: { $0 === node }) else { return false }
    if node.parent === parent {
        swapNodes(node, neighbor)
        return true
    }
    if (parent.layout == .tiles || parent.isExplicitDwindle), parent.navigationOrientation == direction.orientation {
        node.unbindFromParent()
        node.bind(to: parent, adaptiveWeight: WEIGHT_AUTO,
            index: neighbor.ownIndex.orDie() + (direction.isPositive ? 0 : 1))
        return true
    }
    let ratios = parent.dwindleSplitRatios
    let siblingRatios = parent.dwindleChildRatios
    let binding = neighbor.unbindFromParent()
    let split = TilingContainer(parent: parent, adaptiveWeight: binding.adaptiveWeight,
        direction.orientation, .dwindle, index: binding.index)
    split.dwindleOrientation = direction.orientation
    split.dwindleChildRatios = []
    parent.dwindleSplitRatios = ratios
    parent.dwindleChildRatios = siblingRatios
    neighbor.bind(to: split, adaptiveWeight: 1, index: 0)
    node.bind(to: split, adaptiveWeight: 1, index: direction.isPositive ? 0 : 1)
    return true
}
