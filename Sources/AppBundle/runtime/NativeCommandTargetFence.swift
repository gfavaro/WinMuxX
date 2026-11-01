import Common

/// A command requests a fresh read itself, so observation generations cannot be
/// its target identity. Retain the original workspace/display and window instead.
/// An incoming desktop must never inherit a command queued on the outgoing one.
@MainActor
struct NativeCommandTargetFence {
    private struct Target {
        let workspace: Workspace
        let displayUUID: String
        let window: Window?
        let usesDefaultFocus: Bool
    }
    private let targets: [Target]

    init?(_ commands: [any Command], env: CmdEnv, defaultFocus: LiveFocus?, layouts: NativeSpaceLayouts) {
        var targets: [Target] = []
        for command in commands where !(command is DoctorCommand || command is ReloadConfigCommand || command is ModeCommand) {
            let id = command.args.windowId ?? env.windowId
            let workspaceName = command.args.workspaceName?.raw ?? env.workspaceName
            let workspace: Workspace?
            if let id { workspace = Window.get(byId: id)?.nodeWorkspace }
            else if let workspaceName {
                // A desktop number wins over a leftover virtual workspace of the same name.
                workspace = runtime.workspaceBackend.current.workspace(named: workspaceName) ?? Workspace.existing(byName: workspaceName)
            }
            else { workspace = defaultFocus?.workspace }
            guard let workspace,
                  layouts.retainedByUUID.values.contains(where: { $0 === workspace }),
                  let display = workspace.visibleMonitor?.displayUUID else { return nil }
            let usesDefault = id == nil && workspaceName == nil
            targets.append(Target(workspace: workspace, displayUUID: display,
                window: usesDefault ? defaultFocus?.windowOrNil : id.flatMap(Window.get(byId:)), usesDefaultFocus: usesDefault))
        }
        self.targets = targets
    }

    func matches(_ layouts: NativeSpaceLayouts, defaultFocus: LiveFocus?, allowDefaultFocusChanges: Bool = false) -> Bool {
        guard layouts.snapshot != nil else { return false }
        return targets.allSatisfy { target in
            guard target.workspace.visibleMonitor?.displayUUID == target.displayUUID else { return false }
            if target.usesDefaultFocus {
                guard defaultFocus?.workspace === target.workspace else { return false }
                if allowDefaultFocusChanges { return layouts.activeWorkspace(on: target.displayUUID) === target.workspace }
                guard defaultFocus?.windowOrNil === target.window else { return false }
            }
            if let expected = target.window {
                guard let window = Window.get(byId: expected.windowId), window === expected, window.nativeLayoutEligible,
                      window.nodeWorkspace === target.workspace,
                      layouts.registrationWorkspace(for: window.windowId) === target.workspace else { return false }
            }
            return layouts.activeWorkspace(on: target.displayUUID) === target.workspace
        }
    }
}
