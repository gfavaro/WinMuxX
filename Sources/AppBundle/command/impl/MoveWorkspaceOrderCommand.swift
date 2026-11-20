import AppKit
import Common

struct MoveWorkspaceOrderCommand: Command {
    let args: MoveWorkspaceOrderCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        moveWorkspaceInOrder(target.workspace, by: args.direction.val == .up ? -1 : 1)
        return true
    }
}
