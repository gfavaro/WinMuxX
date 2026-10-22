import AppKit
import Common
import MASShortcut
import SwiftUI

// Measured from System Settings on macOS 27: resizable settings window.
let settingsWindowWidth: CGFloat = 757
let settingsWindowMinimumHeight: CGFloat = 470

public let shortcutSettingsWindowId = "\(winMuxAppName).shortcutSettings"

@MainActor
public func getShortcutSettingsWindow(model: ShortcutSettingsModel) -> some Scene {
    SwiftUI.Window("WinMuxX Settings", id: shortcutSettingsWindowId) {
        ShortcutSettingsView(model: model)
            .frame(minWidth: settingsWindowWidth,
                   minHeight: settingsWindowMinimumHeight, maxHeight: .infinity)
            .onAppear {
                NSApp.setActivationPolicy(.accessory)
                // SwiftUI may materialize a Window scene during app launch even
                // when no openWindow request was made. Settings is opt-in, so
                // dismiss that implicit scene and keep explicit requests intact.
                if model.openRequestId == 0 {
                    DispatchQueue.main.async {
                        shortcutSettingsWindow()?.close()
                    }
                }
            }
    }
    .defaultSize(width: settingsWindowWidth, height: 700)
    .windowResizability(.contentSize)
}

@MainActor
public func openShortcutSettingsWindow(_ openWindow: OpenWindowAction) {
    ShortcutSettingsModel.shared.reload()
    if let existingWindow = shortcutSettingsWindow() {
        presentShortcutSettingsWindow(existingWindow)
    } else {
        openWindow(id: shortcutSettingsWindowId)
        DispatchQueue.main.async {
            if let createdWindow = shortcutSettingsWindow() {
                presentShortcutSettingsWindow(createdWindow)
            }
        }
    }
}

enum SettingsSidebarItem: String, Hashable, Identifiable, CaseIterable {
    case general
    case shortcuts
    case workspaces
    case displays
    case sidebar
    case appearance
    case windows
    case automation
    case configuration

    static func restored(_ value: String) -> Self { Self(rawValue: value) ?? .general }

    var id: Self { self }

    var label: String {
        switch self {
            case .general: "General"
            case .shortcuts: "Shortcuts"
            case .workspaces: "Workspaces"
            case .displays: "Displays"
            case .windows: "Windows"
            case .sidebar: "Sidebar"
            case .appearance: "Appearance"
            case .automation: "Automation"
            case .configuration: "Configuration"
        }
    }

    var icon: String {
        switch self {
            case .general: "gearshape"
            case .shortcuts: "keyboard"
            case .workspaces: "rectangle.3.group"
            case .displays: "display.2"
            case .windows: "macwindow.on.rectangle"
            case .sidebar: "sidebar.left"
            case .appearance: "paintpalette"
            case .automation: "gearshape.2"
            case .configuration: "doc.text"
        }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @StateObject private var displays = SettingsDisplaysModel()
    @StateObject private var rules = SettingsWindowRulesModel()
    @AppStorage("settings.selectedPage") private var storedPage = SettingsSidebarItem.general.rawValue
    @State private var shortcutSearch = ""

    private var selectedItem: SettingsSidebarItem? {
        get { SettingsSidebarItem.restored(storedPage) }
        nonmutating set { if let newValue { storedPage = newValue.rawValue } }
    }
    private var selection: Binding<SettingsSidebarItem?> {
        Binding(get: { selectedItem }, set: { selectedItem = $0 })
    }

    private let sidebarItems: [SettingsSidebarItem] = [.general, .workspaces, .displays, .windows, .sidebar, .appearance, .shortcuts, .automation, .configuration]

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(sidebarItems) { item in
                    NavigationLink(value: item) {
                        Label(item.label, systemImage: item.icon)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                SettingsSaveSummary(model: model, additionalUnsaved: rules.isDirty || displays.assignment.isDirty).padding(.horizontal, 20)
                Group {
                switch selectedItem {
                    case .general:
                        ShortcutGeneralSettingsView(model: model)
                    case .shortcuts:
                        ShortcutSettingsShortcutsView(model: model, query: $shortcutSearch)
                    case .workspaces:
                        ShortcutSettingsWorkspacePane(model: model)
                    case .displays:
                        SettingsDisplaysView(model: model, displays: displays, onGeneral: { selectedItem = .general })
                    case .windows:
                        ShortcutBehaviorSettingsView(model: model)
                    case .sidebar:
                        ShortcutSidebarSettingsView(model: model)
                    case .appearance:
                        ShortcutAppearanceSettingsView(model: model)

                    case .automation:
                        ShortcutAutomationSettingsView(model: model, rules: rules, onRawEditor: { selectedItem = .configuration })
                    case .configuration:
                        SettingsConfigurationView(model: model, onNavigate: { selectedItem = $0 })
                    case nil:
                        Text("Select an item")
                }
                }
            }

            .navigationTitle(selectedItem?.label ?? "")
        }
    }
}

struct ShortcutSettingsShortcutsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @Binding var query: String

    var body: some View {
        ShortcutCategoryView(model: model, category: .managed, query: $query)
    }
}

struct ShortcutSettingsWorkspacePane: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        ShortcutCategoryView(model: model, category: .common)
    }
}

struct ShortcutCategoryView: View {
    @ObservedObject var model: ShortcutSettingsModel
    let category: ShortcutSettingsModel.Category
    @Binding var query: String

    init(model: ShortcutSettingsModel, category: ShortcutSettingsModel.Category, query: Binding<String> = .constant("")) {
        self.model = model; self.category = category; self._query = query
    }
    @SettingsDraft("shortcuts-preset", load: { config.shortcutsPreset.rawValue }) private var shortcutsPreset: String
    @SettingsDraft("modifiers.alt", load: { config.modifierSides.alt.rawValue }) private var altSide: String
    @SettingsDraft("modifiers.cmd", load: { config.modifierSides.cmd.rawValue }) private var cmdSide: String
    @SettingsDraft("modifiers.ctrl", load: { config.modifierSides.ctrl.rawValue }) private var ctrlSide: String
    @SettingsDraft("modifiers.shift", load: { config.modifierSides.shift.rawValue }) private var shiftSide: String
    @SettingsDraft("workspace-sidebar.project-deletion-action", load: { config.workspaceSidebar.projectDeletionAction }) private var projectDeletionAction: WorkspaceProjectDeletionAction
    @SettingsDraft("persistent-workspaces", load: { config.persistentWorkspaces.joined(separator: ", ") }) private var persistentWorkspaces: String

    var body: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Form {
            if category == .managed {
                Section {
                    HStack {
                        TextField("Search shortcuts", text: $query, prompt: Text("Action, command or shortcut"))
                            .accessibilityIdentifier("settings.shortcuts.search")
                        if !query.isEmpty { Button("Clear") { query = "" }.accessibilityLabel("Clear shortcut search") }
                    }
                }
            }

            if category == .common {
                Section("Workspace availability") {
                    SettingsTextField("Persistent workspaces", id: "persistent-workspaces", text: $persistentWorkspaces,
                        help: "Comma-separated names in sidebar order, for example 1, 3, 5, Code. These workspaces stay available when empty.") {
                        persistSettingsConfig(section: nil, key: "persistent-workspaces",
                            renderedValue: tomlCommaSeparatedStringArray(persistentWorkspaces), model: model)
                    }
                    SettingsDescription("Persistent workspaces keep their configured order and names. Other empty workspaces close automatically; each project and display keeps a usable workspace.")
                }
                Section("Projects") {
                    SettingsPicker("Deleting projects", id: "workspace-sidebar.project-deletion-action", selection: $projectDeletionAction,
                        help: "Choose what happens to the windows in a project when you delete it.") {
                        Text("Close project windows").tag(WorkspaceProjectDeletionAction.closeWindows)
                        Text("Move windows elsewhere").tag(WorkspaceProjectDeletionAction.moveWindowsToFallback)
                    } onChange: {
                        persistSettingsConfig(section: "workspace-sidebar", key: "project-deletion-action",
                            renderedValue: "'\(projectDeletionAction.rawValue)'", model: model)
                    }
                }
            }

            if category == .managed && !searching {
                SettingsModeOptionsView(model: model)
                Section("Modifier keys") {
                    modifierSidePicker("Option", key: "alt", selection: $altSide)
                    modifierSidePicker("Command", key: "cmd", selection: $cmdSide)
                    modifierSidePicker("Control", key: "ctrl", selection: $ctrlSide)
                    modifierSidePicker("Shift", key: "shift", selection: $shiftSide)
                    SettingsDescription("Choose which side triggers shortcuts. The other side passes through for typing. Modifier-only taps keep their explicit left/right bindings.")
                }
                Section("Shortcut preset") {
                    SettingsPicker("Preset", id: "shortcuts-preset", selection: $shortcutsPreset,
                        help: "Custom preserves your own shortcuts. Rectangle uses the familiar Rectangle bindings.") {
                        Text("Custom").tag("none")
                        Text("Rectangle").tag("rectangle")
                    } onChange: {
                        persistSettingsConfig(section: nil, key: "shortcuts-preset",
                            renderedValue: "'\(shortcutsPreset)'", model: model)
                    }
                }
            }

            let candidates = model.sections.filter { $0.category == category && (searching || $0.id != "managed-move") }
            let sections = filteredShortcutSections(candidates, assignments: model.assignments, query: query)
            ForEach(sections) { section in
                if searching {
                    Section(section.title) {
                        ForEach(section.actions) { action in ShortcutRow(model: model, action: action) }
                    }
                } else {
                    ShortcutSectionView(model: model, section: section)
                }
            }
            if searching && sections.isEmpty {
                Section {
                    Text("No matching shortcuts").font(.headline)
                    SettingsDescription("Try an action name, command or shortcut notation such as alt-h.")
                    Button("Clear search") { query = "" }
                }
            }
        }
        .formStyle(.grouped)

    }
    private func modifierSidePicker(_ title: String, key: String, selection: Binding<String>) -> some View {
        SettingsPicker(title, id: "modifiers.\(key)", selection: selection,
            help: "Applies to shortcut combinations using this modifier. Both preserves the default behavior.") {
            Text("Both").tag("both")
            Text("Left").tag("left")
            Text("Right").tag("right")
        } onChange: {
            persistSettingsConfig(section: "modifiers", key: key,
                renderedValue: "'\(selection.wrappedValue)'", model: model)
        }
    }



}

struct ShortcutSectionView: View {
    @ObservedObject var model: ShortcutSettingsModel
    let section: ShortcutSettingsModel.Section

    var body: some View {
        Section {
            if section.id == "managed-focus" {
                ManagedDirectionalShortcutsView(model: model)
            } else if section.id == "managed-move" {
                EmptyView()
            } else if section.id == "managed-splits" {
                CompassPad(model: model, title: "Split", prefix: "split") {
                    SplitDemoView()
                }
            } else if section.id == "workspaces" {
                WorkspaceShortcutSectionView(model: model)
            } else {
                ForEach(section.actions) { action in
                    ShortcutRow(model: model, action: action)
                }
            }
        } header: {
            if section.id != "managed-focus" {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                    if let summary = section.summary {
                        Text(summary).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}


struct ShortcutRow: View {
    @ObservedObject var model: ShortcutSettingsModel
    let action: ShortcutSettingsModel.Action

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body.weight(.medium))
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShortcutRecorderView(
                title: action.title + " shortcut",
                shortcut: .init(get: { model.shortcutValue(for: action.id) },
                                set: { model.setShortcutValue($0, for: action.id) }),
                onChange: { _ in }
            )
            .frame(width: 160, height: 28)
        }
        .padding(.vertical, 6)
    }
}
