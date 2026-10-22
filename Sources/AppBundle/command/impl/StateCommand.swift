import Common
import Foundation

struct StateCommand: Command {
    let args: StateCmdArgs
    let isQuery = true
    let shouldResetClosedWindowsCache = false
    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        if runtime.publicState.transactionDepth > 0, runtime.publicState.committed == nil {
            return io.err("State is settling; retry after the active command completes")
        }
        return JSONEncoder.winMuxDefault.encodeToString(publicStateSnapshot()).map(io.out)
            ?? io.err("Failed to encode state snapshot")
    }
}
