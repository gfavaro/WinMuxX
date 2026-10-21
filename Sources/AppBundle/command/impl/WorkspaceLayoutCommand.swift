import Common

struct WorkspaceLayoutCommand: Command {
    let args: WorkspaceLayoutCmdArgs
    let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else { return io.err(noWindowIsFocused) }
        guard window.parent is TilingContainer else { return io.err("The window is non-tiling") }
        let workspace = target.workspace
        let current: WorkspaceLayoutName = workspace.rootTilingContainer.layout == .master ? .master : .dwindle
        let layout = nextLayout(in: args.layouts.val, matching: { $0 == current })
        switch layout {
            case .master:
                workspace.configureMasterLayout(focused: window)
            case .dwindle:
                let root = workspace.rootTilingContainer
                guard root.layout != .dwindle else { return false }
                if root.layout == .tabGroup {
                    // A workspace switch preserves a tab group as one atomic pane.
                    root.unbindFromParent()
                    let replacement = TilingContainer(parent: workspace, adaptiveWeight: 1,
                        root.orientation, .dwindle, index: 0)
                    root.bind(to: replacement, adaptiveWeight: 1, index: 0)
                } else {
                    // Keep existing containers, including the master's chosen stack
                    // mode. Configuration defaults must not rebuild them on exit.
                    for child in root.children { (child as? TilingContainer)?.isMasterStack = false }
                    root.layout = .dwindle
                }
        }
        return true
    }
}

extension Workspace {
    @MainActor
    var layoutName: String {
        switch rootTilingContainer.layout {
            case .dwindle: "dwindle"
            case .master: "master"
            case .tiles, .stacked, .tabGroup: "fixed"
        }
    }
}
