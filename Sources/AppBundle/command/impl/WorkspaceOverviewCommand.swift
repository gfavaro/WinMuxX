import Common

struct WorkspaceOverviewCommand: Command {
    let args: WorkspaceOverviewCmdArgs
    let shouldResetClosedWindowsCache = false
    let isPresentation = true
    @MainActor func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        await WorkspacePresentationController.shared.end(reason: .invalidated)
        let controller = WorkspaceOverviewController.shared
        switch args.action {
        case .hide: WorkspaceControlsPanelController.shared.dismiss(); controller.dismiss()
        case .show:
            WorkspaceControlsPanelController.shared.dismiss()
            return controller.show() || io.err("Workspace overview is unavailable during this interaction.")
        case .toggle:
            if controller.isOpen { controller.dismiss() }
            else {
                WorkspaceControlsPanelController.shared.dismiss()
                return controller.show() || io.err("Workspace overview is unavailable during this interaction.")
            }
        }
        return true
    }
}
