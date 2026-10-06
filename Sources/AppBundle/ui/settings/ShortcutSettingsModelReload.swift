import Common
import Foundation

extension ShortcutSettingsModel {
    func reload() {
        let workspaceNumbers = shortcutSettingsWorkspaceNumbers()
        let sections = buildShortcutSections()
        self.sections = sections
        self.workspaceNumbers = workspaceNumbers
        let actions = sections.flatMap(\.actions)
        self.actionsById = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        self.actionIdByCommand = Dictionary(uniqueKeysWithValues: actions.map { ($0.canonicalCommand, $0.id) })

        var nextAssignments: [String: String] = [:]
        var nextCustomBindings: [Summary] = []
        let mainBindingEntries = config.modes[mainModeId]?.bindings.values.map {
            (notation: $0.descriptionWithKeyNotation, command: $0.commands.prettyDescription)
        } ?? []
        let workspaceState = inferWorkspaceShortcutState(
            from: Dictionary(uniqueKeysWithValues: mainBindingEntries.map { ($0.notation, $0.command) }),
            workspaceNumbers: workspaceNumbers,
            defaultSwitchModifiers: defaultWorkspaceSwitchModifiers,
            defaultMoveModifiers: defaultWorkspaceMoveModifiers,
        )
        collectMainBindings(workspaceNumbers: workspaceNumbers, assignments: &nextAssignments, customBindings: &nextCustomBindings)

        if bindingsDraftRevision == savedBindingsRevision {
            self.assignments = nextAssignments
            self.tapBindings = nextTapBindings()
            self.customBindings = nextCustomBindings
            self.workspaceSwitchModifiers = workspaceState.switchModifiers
            self.workspaceMoveModifiers = workspaceState.moveModifiers
            self.workspaceOverrides = workspaceNumbers.map {
                WorkspaceOverride(
                    workspaceName: $0,
                    switchNotation: workspaceState.switchOverrides[$0],
                    moveNotation: workspaceState.moveOverrides[$0],
                )
            }
        }
        SettingsDraftStore.shared.refreshSavedValues()
        settingsRevision += 1
    }

    func requestWindowOpen() {
        reload()
        openRequestId += 1
    }

    private func collectMainBindings(
        workspaceNumbers: [String],
        assignments nextAssignments: inout [String: String],
        customBindings nextCustomBindings: inout [Summary],
    ) {
        let mainBindings = config.modes[mainModeId]?.bindings.values.sorted {
            $0.descriptionWithKeyNotation < $1.descriptionWithKeyNotation
        } ?? []
        for binding in mainBindings {
            let command = binding.commands.prettyDescription
            if let workspace = parseWorkspaceCommandTarget(command, kind: .switchTo), workspaceNumbers.contains(workspace) {
                continue
            }
            if let workspace = parseWorkspaceCommandTarget(command, kind: .moveTo), workspaceNumbers.contains(workspace) {
                continue
            }
            if let actionId = actionIdByCommand[command] {
                nextAssignments[actionId] = binding.descriptionWithKeyNotation
            } else {
                nextCustomBindings.append(.init(
                    id: "binding:\(binding.descriptionWithKeyNotation)",
                    notation: binding.descriptionWithKeyNotation,
                    command: command,
                ))
            }
        }
    }

    private func nextTapBindings() -> [Summary] {
        config.modes[mainModeId]?.tapBindings.values.sorted {
            $0.descriptionWithKeyNotation < $1.descriptionWithKeyNotation
        }.map { binding in
            Summary(
                id: "tap:\(binding.descriptionWithKeyNotation)",
                notation: binding.descriptionWithKeyNotation,
                command: binding.commands.prettyDescription,
            )
        } ?? []
    }
}
