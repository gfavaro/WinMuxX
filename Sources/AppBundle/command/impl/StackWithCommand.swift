import AppKit
import Common

struct StackWithCommand: Command {
    let args: StackWithCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let currentWindow = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }
        let direction = args.direction.val

        // If the window is already in a tab group, pop it out in the specified direction
        if let parent = currentWindow.parent as? TilingContainer, parent.layout == .tabGroup {
            guard removeWindowFromTabStack(currentWindow) else {
                return io.err("Failed to remove window from tab group")
            }
            // After removal, move the window in the specified direction
            // so it lands on the correct side of the (former) tab group
            let moveArgs = MoveCmdArgs(rawArgs: [], direction)
            return MoveCommand(args: moveArgs).run(env, io)
        }

        // In a Scrolling workspace left and right make the window a tab of the column on that side,
        // as join-with stacks it there.
        if target.workspace.arrangement == .scrolling, direction.orientation == .h {
            let workspace = target.workspace
            let columns = workspace.scrollingColumns
            guard let own = workspace.scrollingColumn(of: currentWindow),
                  let index = columns.firstIndex(where: { $0 === own }),
                  let neighbor = columns.getOrNil(atIndex: index + direction.focusOffset)?.mostRecentWindowRecursive else {
                return io.err("No windows in the specified direction")
            }
            createOrAppendWindowTabStack(sourceWindow: currentWindow, onto: neighbor)
            workspace.lastScrollingFocusWindowId = nil
            return true
        }

        // Normal: stack with window in the specified direction
        guard let (parent, ownIndex) = currentWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) else {
            return io.err("No windows in the specified direction")
        }
        guard let targetWindow = parent.children[ownIndex + direction.focusOffset].findLeafWindowRecursive(snappedTo: direction.opposite) else {
            return io.err("No windows in the specified direction")
        }
        createOrAppendWindowTabStack(sourceWindow: currentWindow, onto: targetWindow)
        return true
    }
}
