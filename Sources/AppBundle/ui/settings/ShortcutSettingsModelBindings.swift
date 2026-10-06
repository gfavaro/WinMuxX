import AppKit
import Common
import Foundation
import MASShortcut

extension ShortcutSettingsModel {
    var managedCommands: Set<String> {
        Set(actionsById.values.map(\.canonicalCommand)).union(workspaceManagedCommands)
    }

    func bindingNotation(for actionId: String) -> String? {
        assignments[actionId]
    }

    func shortcutValue(for actionId: String) -> MASShortcut? {
        guard let notation = bindingNotation(for: actionId) else { return nil }
        return masShortcut(from: notation)
    }

    func setShortcutValue(_ shortcut: MASShortcut?, for actionId: String) {
        errorMessage = nil
        if let shortcut, let notation = notation(from: shortcut) {
            applyBindingNotation(notation, to: actionId)
        } else {
            clearBinding(for: actionId)
        }
    }

    func clearBinding(for actionId: String) {
        errorMessage = nil
        var updatedAssignments = assignments
        updatedAssignments[actionId] = nil
        persistBindings(updatedAssignments)
    }

    func applyBindingNotation(_ notation: String, to actionId: String) {
        if let conflict = customCommandConflict(for: notation) {
            errorMessage = "'\(notation)' is already used by custom binding: \(conflict)"
            reload()
            return
        }

        var updatedAssignments = assignments
        for (otherActionId, otherNotation) in assignments where otherActionId != actionId && otherNotation == notation {
            updatedAssignments[otherActionId] = nil
        }
        updatedAssignments[actionId] = notation
        persistBindings(updatedAssignments)
    }

    func persistBindings(_ updatedAssignments: [String: String]) {
        assignments = updatedAssignments
        bindingsDraftRevision += 1
        let submittedRevision = bindingsDraftRevision
        let rendered = Result { try renderedManagedAssignments(from: updatedAssignments) }
        let commands = managedCommands
        let previousSave = pendingSettingsSave
        pendingSettingsSave = Task { @MainActor in
            await previousSave?.value
            let settingID = "mode.main.binding"
            savingSettingIDs.insert(settingID)
            defer { savingSettingIDs.remove(settingID) }
            retrySettingsSave = nil
            failedSettingID = nil
            failedSettingTitle = nil
            errorMessage = nil
            do {
                let targetUrl = try persistMainModeBindings(
                    assignments: rendered.get(),
                    managedCommands: commands,
                )
                guard try await reloadConfig(forceConfigUrl: targetUrl) else {
                    throw shortcutSettingsError("Saved shortcuts, but could not reload the config.")
                }
                savedBindingsRevision = submittedRevision
                reload()
            } catch {
                errorMessage = error.localizedDescription
                failedSettingID = settingID
                failedSettingTitle = "shortcuts"
                failedSaveRevision += 1
                retrySettingsSave = { [weak self] in
                    guard let self else { return }
                    self.persistBindings(self.assignments)
                }
            }
        }
    }

    func customCommandConflict(for notation: String) -> String? {
        guard let binding = config.modes[mainModeId]?.bindings.values.first(where: { $0.descriptionWithKeyNotation == notation }) else {
            return nil
        }
        let command = binding.commands.prettyDescription
        return actionIdByCommand[command] == nil ? command : nil
    }
}
