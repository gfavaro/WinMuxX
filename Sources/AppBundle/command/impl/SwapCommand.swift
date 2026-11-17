import AppKit
import Common

struct SwapCommand: Command {
    let args: SwapCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = true

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else {
            return false
        }

        guard let currentWindow = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }

        let targetWindow: Window?
        switch args.target.val {
            case .direction(let direction):
                if target.workspace.arrangement == .master {
                    targetWindow = dwindleDirectionalFocusTarget(from: currentWindow, direction: direction,
                        excludingMoveNode: currentWindow.moveNode) ?? (args.wrapAround
                            ? spatialWrapFocusTarget(in: target.workspace, from: currentWindow, direction: direction,
                                excludingMoveNode: currentWindow.moveNode) : nil)
                    break
                }
                if let (parent, ownIndex) = currentWindow.closestParent(hasChildrenInDirection: direction, withLayout: nil) {
                    targetWindow = parent.children[ownIndex + direction.focusOffset].findLeafWindowRecursive(snappedTo: direction.opposite)
                } else if args.wrapAround {
                    targetWindow = target.workspace.findLeafWindowRecursive(snappedTo: direction.opposite)
                } else {
                    return false
                }
            case .dfsRelative(let nextPrev):
                guard case .window(let neighbor) = treeOrderNeighbor(of: target.windowOrNil, in: target.workspace, nextPrev,
                                                                     wrap: args.wrapAround) else { return false }
                targetWindow = neighbor
        }

        guard let targetWindow else {
            return false
        }

        swapWindows(currentWindow, targetWindow)

        if args.swapFocus {
            return targetWindow.focusWindow()
        }
        return true
    }
}
