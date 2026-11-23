import Foundation

/// One entry of a `[workspace-sidebar.<table>]` table; a nil value removes it. The key is quoted
/// because workspace names and project ids may contain dots, which a TOML path would split.
private func workspaceSidebarEntryEdit(table: String, key: String, value: String?) -> SettingsConfigEdit {
    SettingsConfigEdit(
        section: "workspace-sidebar.\(table)",
        key: settingsQuotedString(key),
        renderedValue: value.map(settingsQuotedString),
    )
}

func workspaceSidebarLabelEdit(workspaceName: String, label: String?) -> SettingsConfigEdit {
    workspaceSidebarEntryEdit(table: "workspace-labels", key: workspaceName, value: label)
}

func workspaceSidebarProjectLabelEdit(projectId: String, label: String?) -> SettingsConfigEdit {
    workspaceSidebarEntryEdit(table: "project-labels", key: projectId, value: label)
}

func workspaceSidebarProjectColorEdit(projectId: String, colorHex: String?) -> SettingsConfigEdit {
    workspaceSidebarEntryEdit(table: "project-colors", key: projectId, value: colorHex)
}

@MainActor
func persistWorkspaceSidebarLabel(workspaceName: String, label: String?) throws {
    try persistWorkspaceSidebarEdit(workspaceSidebarLabelEdit(workspaceName: workspaceName, label: label))
}

@MainActor
func persistWorkspaceSidebarProjectLabel(projectId: String, label: String?) throws {
    try persistWorkspaceSidebarEdit(workspaceSidebarProjectLabelEdit(projectId: projectId, label: label))
}

@MainActor
func persistWorkspaceSidebarProjectColor(projectId: String, colorHex: String?) throws {
    try persistWorkspaceSidebarEdit(workspaceSidebarProjectColorEdit(projectId: projectId, colorHex: colorHex))
}

@MainActor
private func persistWorkspaceSidebarEdit(_ edit: SettingsConfigEdit) throws {
    try ConfigFileStore.edit(at: preferredEditableConfigUrl()) { applyingSettingsConfigEdits([edit], to: $0) }
}
