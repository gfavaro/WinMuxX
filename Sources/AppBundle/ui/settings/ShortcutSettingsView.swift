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

enum SettingsSidebarItem: Hashable, Identifiable, CaseIterable {
    case general
    case shortcuts
    case workspaces
    case sidebar
    case appearance
    case windows
    case automation
    case configuration

    var id: Self { self }

    var label: String {
        switch self {
            case .general: "General"
            case .shortcuts: "Shortcuts"
            case .workspaces: "Workspaces"
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
    @State private var selectedItem: SettingsSidebarItem? = .general

    private let sidebarItems: [SettingsSidebarItem] = [.general, .workspaces, .windows, .sidebar, .appearance, .shortcuts, .automation, .configuration]

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
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
                SettingsSaveSummary(model: model).padding(.horizontal, 20)
                Group {
                switch selectedItem {
                    case .general:
                        ShortcutGeneralSettingsView(model: model)
                    case .shortcuts:
                        ShortcutSettingsShortcutsView(model: model)
                    case .workspaces:
                        ShortcutSettingsWorkspacePane(model: model)
                    case .windows:
                        ShortcutBehaviorSettingsView(model: model)
                    case .sidebar:
                        ShortcutSidebarSettingsView(model: model)
                    case .appearance:
                        ShortcutAppearanceSettingsView(model: model)

                    case .automation:
                        ShortcutAutomationSettingsView(model: model)
                    case .configuration:
                        SettingsConfigurationView(model: model)
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

    var body: some View {
        ShortcutCategoryView(model: model, category: .managed)
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
    @SettingsDraft("shortcuts-preset", load: { config.shortcutsPreset.rawValue }) private var shortcutsPreset: String
    @SettingsDraft("workspace-sidebar.project-deletion-action", load: { config.workspaceSidebar.projectDeletionAction }) private var projectDeletionAction: WorkspaceProjectDeletionAction
    @SettingsDraft("minimum-workspace-count", load: { config.effectiveMinimumWorkspaceCount }) private var minimumWorkspaceCount: Int

    var body: some View {
        Form {

            if category == .common {
                Section("Workspace availability") {
                    SettingsStepper("Workspaces to keep", id: "minimum-workspace-count", value: $minimumWorkspaceCount,
                        range: 0...Int.max, help: "Keep at least this many workspaces across all projects. 0 disables the configured minimum.", unit: "") {
                        saveMinimumWorkspaceCount()
                    }
                    SettingsDescription("Each project and active display still keeps its required workspace. Occupied workspaces count toward this minimum.")
                    if config.minimumWorkspaceCount == nil && !config.persistentWorkspaces.isEmpty {
                        SettingsDescription("Saving this number replaces the old list of persistent names with a global minimum.")
                        Button("Use this quantity") { saveMinimumWorkspaceCount() }
                            .frame(minHeight: 28)
                    }
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

            if category == .managed {
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

            let sections = model.sections.filter { $0.category == category && $0.id != "managed-move" }
            ForEach(sections) { section in
                ShortcutSectionView(model: model, section: section)
            }
        }
        .formStyle(.grouped)

    }
    private func saveMinimumWorkspaceCount() {
        model.activeSettingTitle = "Workspaces to keep"
        persistSettingsConfigEdits([
            SettingsConfigEdit(section: nil, key: "minimum-workspace-count", renderedValue: String(minimumWorkspaceCount)),
            SettingsConfigEdit(section: nil, key: "persistent-workspaces", renderedValue: nil),
        ], model: model)
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
