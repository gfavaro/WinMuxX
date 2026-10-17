import Common
import Foundation
import TOMLKit

struct SettingsAssignmentDraft: Equatable {
    var workspace = ""
    var selector = ""
    var advanced = false
    private var originalWorkspace: String?
    private var originalSelectors: [String]?
    private var originalValue = ""

    var isEditing: Bool { originalWorkspace != nil }
    var isDirty: Bool {
        isEditing ? selector != originalValue : !workspace.isEmpty || !selector.isEmpty
    }

    static func editing(workspace: String, selectors: [String], connectedSelectors: Set<String>) -> Self {
        var draft = Self()
        draft.workspace = workspace
        draft.selector = selectors.count == 1 ? selectors[0] : "[" + selectors.map(settingsQuotedString).joined(separator: ", ") + "]"
        draft.advanced = selectors.count != 1 || !connectedSelectors.contains(draft.selector)
        draft.originalWorkspace = workspace
        draft.originalSelectors = selectors
        draft.originalValue = draft.selector
        return draft
    }

    @MainActor
    func applying(to text: String) throws -> String {
        guard !workspace.isEmpty else { throw SettingsDisplayError("Choose a workspace.") }
        let parsed = parseConfig(text)
        guard parsed.errors.isEmpty else { throw SettingsDisplayError("Fix the existing configuration errors before saving an assignment.") }
        let current = parsed.config.workspaceToMonitorForceAssignment[workspace]?.map(\.selector)
        if isEditing {
            guard workspace == originalWorkspace, current == originalSelectors else { throw ConfigFileStore.Conflict() }
            guard isDirty else { return text }
        } else if current != nil {
            throw SettingsDisplayError("This workspace already has an assignment. Select Edit to change it.")
        }
        let rendered = try renderedSelectors()
        let result = applyingSettingsConfigEdits([
            .init(section: "workspace-to-monitor-force-assignment", key: settingsQuotedString(workspace), renderedValue: rendered),
        ], to: text)
        try validateSecondarySettingsAssignments(result)
        return result
    }

    func renderedSelectors() throws -> String {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") {
            guard let array = try TOMLTable(string: "value = " + trimmed)["value"]?.array, !array.isEmpty else {
                throw SettingsDisplayError("Enter a display selector or a nonempty array of selectors.")
            }
            let values = try array.map { value -> String in
                guard let raw = value.string ?? value.int.map(String.init),
                      let parsed = parseMonitorDescription(raw).getOrNil() else {
                    throw SettingsDisplayError("Every array entry must be a valid display selector.")
                }
                return settingsQuotedString(parsed.selector)
            }
            return "[" + values.joined(separator: ", ") + "]"
        }
        guard let parsed = parseMonitorDescription(trimmed).getOrNil() else {
            throw SettingsDisplayError("Enter a valid display selector.")
        }
        return settingsQuotedString(parsed.selector)
    }
}
