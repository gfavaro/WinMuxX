import Common

struct WorkspaceOverviewCommand: Command {
    let args: WorkspaceOverviewCmdArgs
    let shouldResetClosedWindowsCache = false
    let isPresentation = true
    @MainActor func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let controller = WorkspaceOverviewController.shared
        switch args.action {
        case .hide: controller.dismiss()
        case .show: return controller.show() || io.err("Workspace overview is unavailable during this interaction.")
        case .toggle:
            if controller.isOpen { controller.dismiss() }
            else { return controller.show() || io.err("Workspace overview is unavailable during this interaction.") }
        }
        return true
    }
}
