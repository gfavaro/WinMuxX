import AppKit
import Common

struct VolumeCommand: Command {
    let args: VolumeCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        let output = SystemVolume.native
        output.apply(args.action.val)
        if args.gui, let volume = output.readVolume() {
            VolumePanel.shared.update(with: output.readMuted() ? 0 : volume)
        }
        return true
    }
}
