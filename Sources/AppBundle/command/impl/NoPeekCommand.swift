import AppKit
import Common

struct NoPeekCommand: Command {
    let args: NoPeekCmdArgs
    let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let dimmer = InactiveWindowDimmer.shared
        let enabled = switch args.action ?? .toggle {
            case .on: true
            case .off: false
            case .toggle: !dimmer.noPeek
        }
        dimmer.setNoPeek(enabled)
        return io.out(enabled ? "No peek on" : "No peek off")
    }
}
