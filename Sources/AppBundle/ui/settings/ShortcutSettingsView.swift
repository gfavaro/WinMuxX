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
        ShortcutSettingsWindowContent(model: model)
            .frame(minWidth: settingsWindowWidth,
                   minHeight: settingsWindowMinimumHeight, maxHeight: .infinity)
            .onAppear {
                NSApp.setActivationPolicy(.accessory)
                // SwiftUI may materialize a Window scene during app launch even
                // when no openWindow request was made. Settings is opt-in, so
                // dismiss that implicit scene and keep explicit requests intact.
                if model.openRequestId == 0 {
                    DispatchQueue.main.async {
                        guard model.openRequestId == 0 else { return }
                        shortcutSettingsWindow()?.close()
                    }
                }
            }
    }
    .defaultSize(width: settingsWindowWidth, height: 700)
    .windowResizability(.contentSize)
    // The generated Window command bypasses requestWindowOpen and the launch
    // suppression guard. Route explicit menu opens through the tray's path.
    .commandsReplaced {
        CommandGroup(after: .windowArrangement) {
            Button("WinMuxX Settings") { model.requestWindowOpen() }
        }
    }
}

@MainActor
public func openShortcutSettingsWindow(_ openWindow: OpenWindowAction) {
    ShortcutSettingsModel.shared.reload()
    ShortcutSettingsModel.shared.isWindowShown = true
    _ = releaseSettingsPagesOnClose
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

/// SwiftUI keeps a closed Window scene, and it builds this one at launch even when
/// Settings is never opened, so every page used to stay in memory for the app's life.
@MainActor
private let releaseSettingsPagesOnClose: Void = {
    _ = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
        let window = note.object as? NSWindow
        MainActor.assumeIsolated {
            guard window?.identifier?.rawValue == shortcutSettingsWindowId else { return }
            ShortcutSettingsModel.shared.isWindowShown = false
        }
    }
}()

/// Holds the pages while the window is open. The rule and display editors live here so
/// their unsaved edits outlast a close, like the other setting drafts.
struct ShortcutSettingsWindowContent: View {
    @ObservedObject var model: ShortcutSettingsModel
    @StateObject private var displays = SettingsDisplaysModel()
    @StateObject private var rules = SettingsWindowRulesModel()

    var body: some View {
        if model.isWindowShown {
            ShortcutSettingsView(model: model, displays: displays, rules: rules)
        } else {
            Color.clear
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

    var isAdvanced: Bool { self == .automation || self == .configuration }

    @MainActor
    func matchesSearch(_ query: String) -> Bool {
        settingsPageSearchResults(query, pages: [self]).contains(self)
    }

    var searchAliases: [String] {
        switch self {
            case .shortcuts: ["keyboard hotkeys bindings presets modifier keys"]
            case .displays: ["monitor display assignment workspace resolution connected screen"]
            case .windows: ["mouse trackpad gestures drag swipe hover"]
            default: []
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
    @ObservedObject var displays: SettingsDisplaysModel
    @ObservedObject var rules: SettingsWindowRulesModel
    @AppStorage("settings.selectedPage") private var storedPage = SettingsSidebarItem.general.rawValue
    @State private var shortcutSearch = ""
    @State private var settingsSearch = ""
    @State private var searchTarget: SettingsSearchDestination?
    @State private var selectedControl: SettingsControl?
    @State private var showsAdvanced = false

    private var selectedItem: SettingsSidebarItem? {
        get { SettingsSidebarItem.restored(storedPage) }
        nonmutating set {
            guard let newValue else { return }
            searchTarget = nil
            selectedControl = nil
            storedPage = newValue.rawValue
        }
    }
    private var selection: Binding<SettingsSidebarSelection?> {
        Binding(get: { selectedControl.map { .control($0) } ?? selectedItem.map { .page($0) } }, set: { select($0) })
    }

    /// Choosing a control result again issues a fresh request, so it scrolls back to the control.
    private func select(_ selection: SettingsSidebarSelection?) {
        switch selection {
            case .page(let page): selectedItem = page
            case .control(let control):
                selectedItem = control.page
                searchTarget = SettingsSearchDestination(id: control.id)
                selectedControl = control
            case nil: break
        }
    }

    private let sidebarItems: [SettingsSidebarItem] = [.general, .workspaces, .displays, .windows, .sidebar, .appearance, .shortcuts, .automation, .configuration]

    var body: some View {
        let hasSearchQuery = !settingsSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let controlResults = settingsControlSearchResults(settingsSearch)
        let matchingPages = settingsPageSearchResults(settingsSearch, pages: sidebarItems)

        NavigationSplitView {
            List(selection: selection) {
                if hasSearchQuery {
                    Section("Settings") {
                        ForEach(controlResults) { result in
                            NavigationLink(value: SettingsSidebarSelection.control(result)) {
                                VStack(alignment: .leading) {
                                    Text(result.title)
                                    Text(result.page.label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityLabel("\(result.title), \(result.page.label)")
                        }
                    }
                }
                Section("Everyday") {
                    ForEach(matchingPages.filter { !$0.isAdvanced }) { item in
                        NavigationLink(value: SettingsSidebarSelection.page(item)) { Label(item.label, systemImage: item.icon) }
                    }
                }
                if !hasSearchQuery {
                    DisclosureGroup("Advanced", isExpanded: $showsAdvanced) {
                        ForEach(sidebarItems.filter(\.isAdvanced)) { item in
                            NavigationLink(value: SettingsSidebarSelection.page(item)) { Label(item.label, systemImage: item.icon) }
                        }
                    }
                } else {
                    Section("Advanced") {
                        ForEach(matchingPages.filter(\.isAdvanced)) { item in
                            NavigationLink(value: SettingsSidebarSelection.page(item)) { Label(item.label, systemImage: item.icon) }
                        }
                    }
                    if matchingPages.isEmpty && controlResults.isEmpty {
                        Text("No matching settings pages").foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                SettingsSearchField(text: $settingsSearch) {
                    select(settingsSearchSubmitSelection(controls: controlResults, pages: matchingPages))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .onAppear { showsAdvanced = selectedItem?.isAdvanced == true }
            .onChange(of: storedPage) { _ in
                if selectedItem?.isAdvanced == true { showsAdvanced = true }
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

            .environment(\.settingsSearchTarget, searchTarget)
            .onChange(of: settingsSearch) { _ in searchTarget = nil; selectedControl = nil }
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
                if let conflict = model.shortcutConflict(for: action.id) {
                    Label(conflict, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Shortcut conflict: \(conflict)")
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
