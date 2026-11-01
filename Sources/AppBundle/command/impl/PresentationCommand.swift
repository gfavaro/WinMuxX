import AppKit
import Common

struct PresentationCommand: Command {
    let args: PresentationCmdArgs
    let shouldResetClosedWindowsCache = false
    let isPresentation = true

    @MainActor func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        switch args.action {
        case .off:
            await WorkspacePresentationController.shared.end(reason: .explicit)
        case .on, .toggle:
            if args.action == .toggle, WorkspacePresentationController.shared.isActive {
                await WorkspacePresentationController.shared.end(reason: .explicit)
                return true
            }
            guard let target = args.resolveTargetOrReportError(env, io) else { return false }
            return await WorkspacePresentationController.shared.start(target: target.windowOrNil, io: io)
        }
        return true
    }
}
