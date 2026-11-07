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
        // In a Tabbed workspace the tab joins the tab group on that side.
        if target.workspace.arrangement == .tabbed {
            target.workspace.syncTabbedGroups()
            let group = target.workspace.tabbedGroup(containing: currentWindow.windowId)
            let neighbor = group.flatMap { target.workspace.tabbedGroup(beside: $0, direction) }
            if !(neighbor.map { target.workspace.moveTabbedTab(currentWindow.windowId, into: $0) } ?? false) {
                io.out("join-with: nothing to do")
            }
            return true
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
