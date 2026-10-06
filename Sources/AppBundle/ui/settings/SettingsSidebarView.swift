import SwiftUI

struct ShortcutSidebarSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @SettingsDraft("workspace-sidebar.enabled", load: { config.workspaceSidebar.enabled }) private var sidebarEnabled: Bool
    @SettingsDraft("workspace-sidebar.enable-focus", load: { config.workspaceSidebar.enableFocus }) private var sidebarFocusEnabled: Bool
    @SettingsDraft("workspace-sidebar.display-mode", load: { SettingsSidebarDisplayMode(config.workspaceSidebar) }) private var sidebarDisplayMode: SettingsSidebarDisplayMode
    @SettingsDraft("workspace-sidebar.show-status-pills", load: { config.workspaceSidebar.showStatusPills }) private var showStatusPills: Bool
    @SettingsDraft("workspace-sidebar.show-clock", load: { config.workspaceSidebar.showClock }) private var showClock: Bool
    @SettingsDraft("workspace-sidebar.show-seconds", load: { config.workspaceSidebar.showSeconds }) private var showSeconds: Bool
    @SettingsDraft("workspace-sidebar.show-date", load: { config.workspaceSidebar.showDate }) private var showDate: Bool
    @SettingsDraft("workspace-sidebar.show-weekday", load: { config.workspaceSidebar.showWeekday }) private var showWeekday: Bool
    @SettingsDraft("workspace-sidebar.chrome-style", load: { config.workspaceSidebar.chromeStyle }) private var chromeStyle: ChromeStyle
    @SettingsDraft("workspace-sidebar.menu-bar-background", load: { config.workspaceSidebar.menuBarBackground }) private var menuBarBackground: Bool
    @SettingsDraft("workspace-sidebar.width", load: { config.workspaceSidebar.width }) private var sidebarWidth: Int
    @SettingsDraft("workspace-sidebar.collapsed-width", load: { config.workspaceSidebar.collapsedWidth }) private var collapsedWidth: Int
    @SettingsDraft("workspace-sidebar.position", load: { config.workspaceSidebar.position }) private var sidebarPosition: WorkspaceSidebarPosition
    @SettingsDraft("workspace-sidebar.height-mode", load: { config.workspaceSidebar.heightMode ?? .standard }) private var sidebarHeightMode: WorkspaceSidebarHeightMode

    var body: some View {
        SettingsScrollView {
            SettingsSection("Sidebar") {
                SettingsToggle("Show sidebar", id: "workspace-sidebar.enabled", isOn: $sidebarEnabled, help: "Show the workspace rail on configured displays.") { sidebarBool("enabled", sidebarEnabled) }
                if chromeStyle == .liquidGlass {
                    SettingsToggle("Show background", id: "workspace-sidebar.menu-bar-background", isOn: $menuBarBackground,
                                   help: "Show native glass when collapsed. The expanded sidebar always uses a frosted background. Reduce Transparency takes priority.") {
                        sidebarBool("menu-bar-background", menuBarBackground)
                    }
                    .disabled(!sidebarEnabled)
                }
                SettingsToggle("Show focused-display filter", id: "workspace-sidebar.enable-focus", isOn: $sidebarFocusEnabled, help: "Add Focused to the sidebar's monitor selector. This filters the listed workspaces; it does not hide sidebars on other displays.") { sidebarBool("enable-focus", sidebarFocusEnabled) }
                .disabled(!sidebarEnabled)
                SettingsPicker("Sidebar display", id: "workspace-sidebar.display-mode", selection: $sidebarDisplayMode, help: "Choose a compact rail, reveal at the display edge, or keep the sidebar expanded with reserved window space.") {
                    Text("Compact rail").tag(SettingsSidebarDisplayMode.compact)
                    Text("Auto-hide").tag(SettingsSidebarDisplayMode.autoHide)
                    Text("Always expanded").tag(SettingsSidebarDisplayMode.expanded)
                } onChange: { persistSidebarDisplayMode() }
                .disabled(!sidebarEnabled)
                SettingsPicker("Expanded sidebar size", id: "workspace-sidebar.width", selection: $sidebarWidth,
                               help: "Width of the expanded sidebar: Small 200 pt, Medium 240 pt, Large 280 pt.") {
                    Text("Small").tag(200).disabled(collapsedWidth >= 200)
                    Text("Medium").tag(240).disabled(collapsedWidth >= 240)
                    Text("Large").tag(280).disabled(collapsedWidth >= 280)
                    if ![200, 240, 280].contains(sidebarWidth) {
                        Text("Custom (\(sidebarWidth) pt)").tag(sidebarWidth)
                    }
                } onChange: { sidebarInt("width", sidebarWidth) }
                .disabled(!sidebarEnabled)
                SettingsPicker("Collapsed sidebar size", id: "workspace-sidebar.collapsed-width", selection: $collapsedWidth,
                               help: "Width of the collapsed rail: Small 36 pt, Medium 44 pt, Large 56 pt. Auto-hide uses this size when revealing the rail.") {
                    Text("Small").tag(36).disabled(sidebarWidth <= 36)
                    Text("Medium").tag(44).disabled(sidebarWidth <= 44)
                    Text("Large").tag(56).disabled(sidebarWidth <= 56)
                    if ![36, 44, 56].contains(collapsedWidth) {
                        Text("Custom (\(collapsedWidth) pt)").tag(collapsedWidth)
                    }
                } onChange: { sidebarInt("collapsed-width", collapsedWidth) }
                .disabled(!sidebarEnabled || sidebarDisplayMode == .expanded)
                SettingsPicker("Sidebar position", id: "workspace-sidebar.position", selection: $sidebarPosition, help: "Choose the display edge. Windows reserve space on the selected side.") {
                    Text("Left").tag(WorkspaceSidebarPosition.left)
                    Text("Right").tag(WorkspaceSidebarPosition.right)
                } onChange: { persist("workspace-sidebar", "position", "'\(sidebarPosition.rawValue)'") }
                .disabled(!sidebarEnabled)
                SettingsPicker("Sidebar height", id: "workspace-sidebar.height-mode", selection: $sidebarHeightMode, help: "Standard and Full fill the safe height below the menu bar. Centered fits content up to 90% of that height. The menu bar always stays clear.") {
                    Text("Standard").tag(WorkspaceSidebarHeightMode.standard)
                    Text("Centered").tag(WorkspaceSidebarHeightMode.centered)
                    Text("Full").tag(WorkspaceSidebarHeightMode.full)
                } onChange: { persist("workspace-sidebar", "height-mode", "'\(sidebarHeightMode.rawValue)'") }
                .disabled(!sidebarEnabled)

            }
            SettingsSection("Sidebar content") {
                if !showClock { Text("Enable Show clock to display seconds, date, and weekday.").font(.callout).foregroundStyle(.secondary) }
                if !sidebarEnabled { Text("Enable Show sidebar to change its content.").font(.callout).foregroundStyle(.secondary) }
                SettingsToggle("Show status pills", id: "workspace-sidebar.show-status-pills", isOn: $showStatusPills) { sidebarBool("show-status-pills", showStatusPills) }
                .disabled(!sidebarEnabled)
                SettingsToggle("Show clock", id: "workspace-sidebar.show-clock", isOn: $showClock) { sidebarBool("show-clock", showClock) }
                .disabled(!sidebarEnabled)
                SettingsToggle("Show seconds", id: "workspace-sidebar.show-seconds", isOn: $showSeconds) { sidebarBool("show-seconds", showSeconds) }
                .disabled(!sidebarEnabled || !showClock)
                SettingsToggle("Show date", id: "workspace-sidebar.show-date", isOn: $showDate, help: "Show the month and day below the clock when the sidebar is expanded.") { sidebarBool("show-date", showDate) }
                .disabled(!sidebarEnabled || !showClock)
                SettingsToggle("Show weekday", id: "workspace-sidebar.show-weekday", isOn: $showWeekday, help: "Show the day of the week below the clock when the sidebar is expanded.") { sidebarBool("show-weekday", showWeekday) }
                .disabled(!sidebarEnabled || !showClock)
            }
        }
        .navigationTitle("Sidebar")
    }

    private func persistSidebarDisplayMode() {
        persistSettingsConfigEdits(sidebarDisplayMode.edits, model: model, draftIDs: ["workspace-sidebar.display-mode"])
    }
    private func sidebarBool(_ key: String, _ value: Bool) { persist("workspace-sidebar", key, value ? "true" : "false") }
    private func sidebarInt(_ key: String, _ value: Int) { persist("workspace-sidebar", key, "\(value)") }
    private func persist(_ section: String?, _ key: String, _ value: String) { persistSettingsConfig(section: section, key: key, renderedValue: value, model: model) }
}
