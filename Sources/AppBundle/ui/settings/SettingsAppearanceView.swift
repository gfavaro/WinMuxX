import SwiftUI

struct ShortcutAppearanceSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var menuBarIndicator = ExperimentalUISettings().indicator
    @State private var menuBarIconAppearance = ExperimentalUISettings().iconAppearance
    @State private var sidebarEnabled = config.workspaceSidebar.enabled
    @State private var sidebarFocusEnabled = config.workspaceSidebar.enableFocus
    @State private var sidebarDisplayMode = SettingsSidebarDisplayMode(config.workspaceSidebar)
    @State private var showStatusPills = config.workspaceSidebar.showStatusPills
    @State private var showClock = config.workspaceSidebar.showClock
    @State private var showSeconds = config.workspaceSidebar.showSeconds
    @State private var showDate = config.workspaceSidebar.showDate
    @State private var showWeekday = config.workspaceSidebar.showWeekday
    @State private var chromeStyle = config.workspaceSidebar.chromeStyle
    @State private var menuBarBackground = config.workspaceSidebar.menuBarBackground
    @State private var solidChromeColor = config.workspaceSidebar.solidChromeColor
    @State private var solidChromeCustomColor = config.workspaceSidebar.solidChromeCustomColor
    @State private var sidebarWidth = config.workspaceSidebar.width
    @State private var collapsedWidth = config.workspaceSidebar.collapsedWidth
    @State private var tabEnabled = config.windowTabs.enabled
    @State private var tabHeight = max(36, config.windowTabs.height)
    @State private var glideEnabled = config.animations.enabled
    @State private var glideDurationMs = min(max(config.animations.durationMs, 50), 1000)
    @State private var sidebarPosition = config.workspaceSidebar.position
    @State private var sidebarHeightMode = config.workspaceSidebar.heightMode ?? .standard
    @State private var innerHorizontalGap = settingsConstantValue(config.gaps.inner.horizontal)
    @State private var innerVerticalGap = settingsConstantValue(config.gaps.inner.vertical)
    @State private var outerLeftGap = settingsConstantValue(config.gaps.outer.left)
    @State private var outerRightGap = settingsConstantValue(config.gaps.outer.right)
    @State private var outerTopGap = settingsConstantValue(config.gaps.outer.top)
    @State private var outerBottomGap = settingsConstantValue(config.gaps.outer.bottom)
    @State private var bordersEnabled = config.windowBorders.enabled
    @State private var borderWidth = config.windowBorders.width
    @State private var activeBorderColor = config.windowBorders.activeColor
    @State private var inactiveBorderColor = config.windowBorders.inactiveColor
    @State private var borderOrder = config.windowBorders.order
    @State private var excludedBorderApps = config.windowBorders.excludeApps.joined(separator: ", ")

    var body: some View {
        SettingsScrollView {
            if let error = model.errorMessage {
                SettingsSection("Could not save setting") {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            SettingsSection("Menu bar") {
                SettingsPicker("Menu bar indicator", selection: $menuBarIndicator,
                               help: "Workspace follows the focused display: label initial when named, workspace number otherwise.") {
                    Text("Icon").tag(MenuBarIndicator.icon)
                    Text("Workspace").tag(MenuBarIndicator.workspace)
                } onChange: {
                    var settings = ExperimentalUISettings()
                    settings.indicator = menuBarIndicator
                    TrayMenuModel.shared.experimentalUISettings = settings
                    updateTrayText()
                }
                if menuBarIndicator == .icon {
                    SettingsPicker("Icon appearance", selection: $menuBarIconAppearance, help: "Choose a color or monochrome tray icon.") {
                        ForEach(MenuBarIconAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    } onChange: {
                        var settings = ExperimentalUISettings()
                        settings.iconAppearance = menuBarIconAppearance
                        TrayMenuModel.shared.experimentalUISettings = settings
                    }
                }
            }
            SettingsSection("Sidebar") {
                SettingsToggle("Show sidebar", isOn: $sidebarEnabled, help: "Show the workspace rail on configured displays.") { sidebarBool("enabled", sidebarEnabled) }
                SettingsPicker("Sidebar appearance", selection: $chromeStyle,
                               help: "Liquid Glass uses native glass and wallpaper-adaptive contrast. Solid color uses the selected opaque color. This choice also applies to tab strips and the switcher.") {
                    Text("Liquid Glass").tag(ChromeStyle.liquidGlass)
                    Text("Solid color").tag(ChromeStyle.solid)
                } onChange: { persist("workspace-sidebar", "chrome-style", "'\(chromeStyle.rawValue)'") }
                Text("Also applies to tab strips and the switcher.")
                    .font(.caption).foregroundStyle(.secondary)
                if chromeStyle == .solid {
                    SettingsSolidColorPalette(
                        selection: $solidChromeColor,
                        customColor: $solidChromeCustomColor,
                        isEnabled: true,
                        onSelectionChange: { persist("workspace-sidebar", "solid-chrome-color", "'\(solidChromeColor.rawValue)'") },
                        onCustomColorChange: { persist("workspace-sidebar", "solid-chrome-custom-color", "'\(solidChromeCustomColor)'") },
                    )
                } else {
                    SettingsToggle("Show background", isOn: $menuBarBackground,
                                   help: "Show native glass when collapsed. The expanded sidebar always uses a frosted background. Reduce Transparency takes priority.") {
                        sidebarBool("menu-bar-background", menuBarBackground)
                    }
                    .disabled(!sidebarEnabled)
                }
                SettingsToggle("Show focused-display filter", isOn: $sidebarFocusEnabled, help: "Add Focused to the sidebar's monitor selector. This filters the listed workspaces; it does not hide sidebars on other displays.") { sidebarBool("enable-focus", sidebarFocusEnabled) }
                .disabled(!sidebarEnabled)
                SettingsPicker("Sidebar display", selection: $sidebarDisplayMode, help: "Choose a compact rail, reveal at the display edge, or keep the sidebar expanded with reserved window space.") {
                    Text("Compact rail").tag(SettingsSidebarDisplayMode.compact)
                    Text("Auto-hide").tag(SettingsSidebarDisplayMode.autoHide)
                    Text("Always expanded").tag(SettingsSidebarDisplayMode.expanded)
                } onChange: { persistSidebarDisplayMode() }
                .disabled(!sidebarEnabled)
                SettingsPicker("Expanded sidebar size", selection: $sidebarWidth,
                               help: "Width of the expanded sidebar: Small 200 pt, Medium 240 pt, Large 280 pt.") {
                    Text("Small").tag(200).disabled(collapsedWidth >= 200)
                    Text("Medium").tag(240).disabled(collapsedWidth >= 240)
                    Text("Large").tag(280).disabled(collapsedWidth >= 280)
                    if ![200, 240, 280].contains(sidebarWidth) {
                        Text("Custom (\(sidebarWidth) pt)").tag(sidebarWidth)
                    }
                } onChange: { sidebarInt("width", sidebarWidth) }
                .disabled(!sidebarEnabled)
                SettingsPicker("Collapsed sidebar size", selection: $collapsedWidth,
                               help: "Width of the collapsed rail: Small 36 pt, Medium 44 pt, Large 56 pt. Auto-hide uses this size when revealing the rail.") {
                    Text("Small").tag(36).disabled(sidebarWidth <= 36)
                    Text("Medium").tag(44).disabled(sidebarWidth <= 44)
                    Text("Large").tag(56).disabled(sidebarWidth <= 56)
                    if ![36, 44, 56].contains(collapsedWidth) {
                        Text("Custom (\(collapsedWidth) pt)").tag(collapsedWidth)
                    }
                } onChange: { sidebarInt("collapsed-width", collapsedWidth) }
                .disabled(!sidebarEnabled || sidebarDisplayMode == .expanded)
                SettingsPicker("Sidebar position", selection: $sidebarPosition, help: "Choose the display edge. Windows reserve space on the selected side.") {
                    Text("Left").tag(WorkspaceSidebarPosition.left)
                    Text("Right").tag(WorkspaceSidebarPosition.right)
                } onChange: { persist("workspace-sidebar", "position", "'\(sidebarPosition.rawValue)'") }
                .disabled(!sidebarEnabled)
                SettingsPicker("Sidebar height", selection: $sidebarHeightMode, help: "Standard and Full fill the safe height below the menu bar. Centered fits content up to 90% of that height. The menu bar always stays clear.") {
                    Text("Standard").tag(WorkspaceSidebarHeightMode.standard)
                    Text("Centered").tag(WorkspaceSidebarHeightMode.centered)
                    Text("Full").tag(WorkspaceSidebarHeightMode.full)
                } onChange: { persist("workspace-sidebar", "height-mode", "'\(sidebarHeightMode.rawValue)'") }
                .disabled(!sidebarEnabled)

            }
            SettingsSection("Sidebar content") {
                if !showClock { Text("Enable Show clock to display seconds, date, and weekday.").font(.caption).foregroundStyle(.secondary) }
                if !sidebarEnabled { Text("Enable Show sidebar to change its content.").font(.caption).foregroundStyle(.secondary) }
                SettingsToggle("Show status pills", isOn: $showStatusPills) { sidebarBool("show-status-pills", showStatusPills) }
                .disabled(!sidebarEnabled)
                SettingsToggle("Show clock", isOn: $showClock) { sidebarBool("show-clock", showClock) }
                .disabled(!sidebarEnabled)
                SettingsToggle("Show seconds", isOn: $showSeconds) { sidebarBool("show-seconds", showSeconds) }
                .disabled(!sidebarEnabled || !showClock)
                SettingsToggle("Show date", isOn: $showDate) { sidebarBool("show-date", showDate) }
                .disabled(!sidebarEnabled || !showClock)
                SettingsToggle("Show weekday", isOn: $showWeekday) { sidebarBool("show-weekday", showWeekday) }
                .disabled(!sidebarEnabled || !showClock)
            }
            SettingsSection("Window tabs") {
                if !tabEnabled { Text("Enable Show tab strips to change their dimensions.").font(.caption).foregroundStyle(.secondary) }
                SettingsToggle("Show tab strips", isOn: $tabEnabled, help: "Display browser-like tabs for stacked windows.") { persist("window-tabs", "enabled", tabEnabled ? "true" : "false") }
                SettingsStepper("Tab strip height", value: $tabHeight, range: 36...80, help: "Height of the window tab strip.") { persist("window-tabs", "height", "\(tabHeight)") }
                .disabled(!tabEnabled)

            }
            SettingsSection("Window motion") {
                SettingsToggle("Glide windows", isOn: $glideEnabled,
                               help: "Animate windows as they move into their layout tiles. Reduce Motion disables the glide.") {
                    persist("animations", "enabled", glideEnabled ? "true" : "false")
                }
                SettingsStepper("Glide duration", value: $glideDurationMs, range: 50...1000,
                                help: "Duration of the window glide. Lower values are faster.", unit: "ms") {
                    persist("animations", "duration-ms", "\(glideDurationMs)")
                }
                .disabled(!glideEnabled)
            }
            SettingsSection("Window spacing") {
                if hasPerMonitorGaps {
                    Text("These values edit the default spacing. Per-display overrides in your config are preserved.")
                    .font(.caption).foregroundStyle(.secondary)
                }
                SettingsStepper("Inner horizontal", value: $innerHorizontalGap, range: 0...80, help: "Space between windows side by side.") { persist("gaps", "inner.horizontal", settingsGapValue(config.gaps.inner.horizontal, replacingDefaultWith: innerHorizontalGap)) }
                SettingsStepper("Inner vertical", value: $innerVerticalGap, range: 0...80, help: "Space between vertically stacked windows.") { persist("gaps", "inner.vertical", settingsGapValue(config.gaps.inner.vertical, replacingDefaultWith: innerVerticalGap)) }
                SettingsStepper("Outer left", value: $outerLeftGap, range: 0...120, help: "Space between the sidebar and tiled windows, or the left display edge when the sidebar is hidden.") { persist("gaps", "outer.left", settingsGapValue(config.gaps.outer.left, replacingDefaultWith: outerLeftGap)) }
                SettingsStepper("Outer right", value: $outerRightGap, range: 0...120, help: "Inset at the right display edge.") { persist("gaps", "outer.right", settingsGapValue(config.gaps.outer.right, replacingDefaultWith: outerRightGap)) }
                SettingsStepper("Outer top", value: $outerTopGap, range: 0...120, help: "Inset at the top display edge.") { persist("gaps", "outer.top", settingsGapValue(config.gaps.outer.top, replacingDefaultWith: outerTopGap)) }
                SettingsStepper("Outer bottom", value: $outerBottomGap, range: 0...120, help: "Inset at the bottom display edge.") { persist("gaps", "outer.bottom", settingsGapValue(config.gaps.outer.bottom, replacingDefaultWith: outerBottomGap)) }
            }
            SettingsSection("Window borders") {
                SettingsToggle("Show window borders", isOn: $bordersEnabled, help: "Draw a border around each visible managed window.") {
                    persist("borders", "enabled", bordersEnabled ? "true" : "false")
                }
                SettingsDoubleStepper(title: "Border width", value: $borderWidth, range: 0...20, step: 0.5, help: "Width in points; zero hides the border.") {
                    persist("borders", "width", String(borderWidth))
                }
                .disabled(!bordersEnabled)
                SettingsBorderColor("Focused window color", text: $activeBorderColor) {
                    persist("borders", "active-color", "'\(activeBorderColor)'")
                }
                .disabled(!bordersEnabled)
                SettingsBorderColor("Other window color", text: $inactiveBorderColor) {
                    persist("borders", "inactive-color", "'\(inactiveBorderColor)'")
                }
                .disabled(!bordersEnabled)
                SettingsPicker("Border placement", selection: $borderOrder, help: "Draw the border behind or over the window.") {
                    Text("Behind").tag(WindowBorderOrder.below)
                    Text("In front").tag(WindowBorderOrder.above)
                } onChange: {
                    persist("borders", "order", "'\(borderOrder.rawValue)'")
                }
                .disabled(!bordersEnabled)
                DisclosureGroup("App exclusions") {
                    SettingsTextField("Excluded app bundle IDs", text: $excludedBorderApps, help: "Comma-separated bundle IDs, for example com.apple.finder.") {
                        persist("borders", "exclude-apps", tomlCommaSeparatedStringArray(excludedBorderApps))
                    }
                }
            }
        }
        .navigationTitle("Sidebar & Appearance")
    }

    private var hasPerMonitorGaps: Bool {
        [config.gaps.inner.horizontal, config.gaps.inner.vertical, config.gaps.outer.left,
        config.gaps.outer.right, config.gaps.outer.top, config.gaps.outer.bottom].contains {
            if case .perMonitor = $0 { return true }
            return false
        }
    }

    private func persistSidebarDisplayMode() {
        persistSettingsConfigEdits(sidebarDisplayMode.edits, model: model)
    }

    private func sidebarBool(_ key: String, _ value: Bool) { persist("workspace-sidebar", key, value ? "true" : "false") }
    private func sidebarInt(_ key: String, _ value: Int) { persist("workspace-sidebar", key, "\(value)") }
    private func persist(_ section: String?, _ key: String, _ value: String) { persistSettingsConfig(section: section, key: key, renderedValue: value, model: model) }
}

private func settingsConstantValue(_ value: DynamicConfigValue<Int>) -> Int {
    switch value {
        case .constant(let value): value
        case .perMonitor(_, let `default`): `default`
    }
}
