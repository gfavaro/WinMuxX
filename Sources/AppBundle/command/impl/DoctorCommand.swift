import AppKit
import Common

struct DoctorCommand: Command {
    let args: DoctorCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        io.out(await buildDiagnosticsReport())
        return true
    }
}
