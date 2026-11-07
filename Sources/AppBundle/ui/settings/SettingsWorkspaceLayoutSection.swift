import SwiftUI

/// One workspace's own arrangement, beside the default it overrides. It was a form on the
/// Displays page, away from the layout it changes; a card choice now saves directly.
struct SettingsWorkspaceLayoutSection: View {
    @ObservedObject var model: ShortcutSettingsModel
    @ObservedObject private var tray = TrayMenuModel.shared
    @State private var workspace = ""
    @State private var choice = "inherit"
    @State private var error: String?

    var body: some View {
        SettingsSection("Workspace layout") {
            Picker("Workspace", selection: $workspace) {
                Text("Choose workspace").tag("")
                ForEach(tray.workspaces, id: \.name) { row in Text(row.displayName).tag(row.name) }
            }
            SettingsPictogramPicker(title: "Layout for this workspace", id: "workspace-layout", selection: $choice, options: [
                .init(value: "inherit", title: "Default", pictogram: .inherit),
                .init(value: "dwindle", title: "Dwindle", pictogram: .dwindle),
                .init(value: "master", title: "Master", pictogram: .master),
            ], help: "Sets the workspace-wide arrangement. Each existing top-level group keeps its nested splits and tabs. A matching display override may take precedence.") {
                save()
            }
            .disabled(workspace.isEmpty)
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .onAppear { load() }
        .onChange(of: workspace) { _ in load() }
    }

    private var saved: String {
        guard !workspace.isEmpty else { return "inherit" }
        return config.workspaceLayouts[workspace]?.defaults.layout?.rawValue ?? "inherit"
    }

    private func load() { choice = saved }

    private func save() {
        guard !workspace.isEmpty, choice != saved else { return }
        let name = workspace, selected = choice, previous = saved
        model.activeSettingTitle = "Workspace layout: \(workspaceDisplayName(name))"
        persistSettingsDocumentEdit(model: model, settingIDs: ["workspace.\(name).layout"], onSaved: {
            error = nil
        }, onFailure: { failure in
            error = failure.localizedDescription
            load()
        }) { current in
            let parsed = parseConfig(current)
            guard parsed.errors.isEmpty,
                  (parsed.config.workspaceLayouts[name]?.defaults.layout?.rawValue ?? "inherit") == previous else {
                throw ConfigFileStore.Conflict()
            }
            let rendered = selected == "inherit" ? nil : settingsQuotedString(selected)
            return applyingSettingsConfigEdits([
                .init(section: "workspace.\(settingsQuotedString(name))", key: "layout", renderedValue: rendered),
            ], to: current)
        }
    }
}
