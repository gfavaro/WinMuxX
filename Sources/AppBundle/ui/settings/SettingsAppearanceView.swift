import SwiftUI

struct ShortcutAppearanceSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var menuBarIndicator = ExperimentalUISettings().indicator
    @State private var menuBarIconAppearance = ExperimentalUISettings().iconAppearance
    @SettingsDraft("workspace-sidebar.chrome-style", load: { config.workspaceSidebar.chromeStyle }) private var chromeStyle: ChromeStyle
    @SettingsDraft("workspace-sidebar.solid-chrome-color", load: { config.workspaceSidebar.solidChromeColor }) private var solidChromeColor: ChromeSolidColor
    @SettingsDraft("workspace-sidebar.solid-chrome-custom-color", load: { config.workspaceSidebar.solidChromeCustomColor }) private var solidChromeCustomColor: String
    @SettingsDraft("animations.enabled", load: { config.animations.enabled }) private var glideEnabled: Bool
    @SettingsDraft("animations.duration-ms", load: { min(max(config.animations.durationMs, 50), 1000) }) private var glideDurationMs: Int
    @SettingsDraft("gaps.inner.horizontal", load: { settingsConstantValue(config.gaps.inner.horizontal) }) private var innerHorizontalGap: Int
    @SettingsDraft("gaps.inner.vertical", load: { settingsConstantValue(config.gaps.inner.vertical) }) private var innerVerticalGap: Int
    @SettingsDraft("gaps.outer.left", load: { settingsConstantValue(config.gaps.outer.left) }) private var outerLeftGap: Int
    @SettingsDraft("gaps.outer.right", load: { settingsConstantValue(config.gaps.outer.right) }) private var outerRightGap: Int
    @SettingsDraft("gaps.outer.top", load: { settingsConstantValue(config.gaps.outer.top) }) private var outerTopGap: Int
    @SettingsDraft("gaps.outer.bottom", load: { settingsConstantValue(config.gaps.outer.bottom) }) private var outerBottomGap: Int
    @SettingsDraft("borders.enabled", load: { config.windowBorders.enabled }) private var bordersEnabled: Bool
    @SettingsDraft("borders.width", load: { config.windowBorders.width }) private var borderWidth: Double
    @SettingsDraft("borders.active-color", load: { config.windowBorders.activeColor }) private var activeBorderColor: String
    @SettingsDraft("borders.inactive-color", load: { config.windowBorders.inactiveColor }) private var inactiveBorderColor: String
    @SettingsDraft("borders.order", load: { config.windowBorders.order }) private var borderOrder: WindowBorderOrder
    @SettingsDraft("borders.exclude-apps", load: { config.windowBorders.excludeApps.joined(separator: ", ") }) private var excludedBorderApps: String

    @State private var showsInnerSpacing = true
    @State private var showsOuterSpacing = true

    var body: some View {
        SettingsScrollView {
            SettingsSection("Shared style") {
                SettingsPicker("Shared appearance", id: "workspace-sidebar.chrome-style", selection: $chromeStyle,
                               help: "Choose the shared appearance for the sidebar, tab groups and switcher.") {
                    Text("Liquid Glass").tag(ChromeStyle.liquidGlass)
                    Text("Solid color").tag(ChromeStyle.solid)
                } onChange: { persist("workspace-sidebar", "chrome-style", "'\(chromeStyle.rawValue)'") }
                if chromeStyle == .solid {
                    SettingsSolidColorPalette(
                        selection: $solidChromeColor,
                        customColor: $solidChromeCustomColor,
                        isEnabled: true,
                        onSelectionChange: { persist("workspace-sidebar", "solid-chrome-color", "'\(solidChromeColor.rawValue)'") },
                        onCustomColorChange: { persist("workspace-sidebar", "solid-chrome-custom-color", "'\(solidChromeCustomColor)'") },
                    )
                }

            }
            SettingsSection("Menu bar") {
                SettingsPicker("Menu bar indicator", id: "ui.menu-bar-indicator", selection: $menuBarIndicator,
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
                    SettingsPicker("Icon appearance", id: "ui.menu-bar-icon-appearance", selection: $menuBarIconAppearance, help: "Choose a color or monochrome tray icon.") {
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



            SettingsSection("Window motion") {
                SettingsToggle("Glide windows", id: "animations.enabled", isOn: $glideEnabled,
                               help: "Animate windows as they move into their layout tiles. Reduce Motion disables the glide.") {
                    persist("animations", "enabled", glideEnabled ? "true" : "false")
                }
                SettingsStepper("Glide duration", id: "animations.duration-ms", value: $glideDurationMs, range: 50...1000,
                                help: "Duration of the window glide. Lower values are faster.", unit: "ms") {
                    persist("animations", "duration-ms", "\(glideDurationMs)")
                }
                .disabled(!glideEnabled)
            }
            SettingsSection("Window spacing") {
                if hasPerMonitorGaps {
                    Text("These values edit the default spacing. Per-display overrides in your config are preserved.")
                    .font(.callout).foregroundStyle(.secondary)
                }
                SettingsGapPreview(values: SettingsGapPreviewValues(horizontal: innerHorizontalGap, vertical: innerVerticalGap,
                    left: outerLeftGap, right: outerRightGap, top: outerTopGap, bottom: outerBottomGap))
                DisclosureGroup("Space between windows", isExpanded: $showsInnerSpacing) {
                    SettingsGapSlider(id: "gaps.inner.horizontal", title: "Horizontal", value: $innerHorizontalGap, range: 0...80,
                        help: "Space between windows side by side.", savedValue: settingsConstantValue(config.gaps.inner.horizontal)) {
                        persist("gaps", "inner.horizontal", settingsGapValue(config.gaps.inner.horizontal, replacingDefaultWith: innerHorizontalGap))
                    }
                    SettingsGapSlider(id: "gaps.inner.vertical", title: "Vertical", value: $innerVerticalGap, range: 0...80,
                        help: "Space between vertically stacked windows.", savedValue: settingsConstantValue(config.gaps.inner.vertical)) {
                        persist("gaps", "inner.vertical", settingsGapValue(config.gaps.inner.vertical, replacingDefaultWith: innerVerticalGap))
                    }
                }
                DisclosureGroup("Space around windows", isExpanded: $showsOuterSpacing) {
                    SettingsGapSlider(id: "gaps.outer.left", title: "Left", value: $outerLeftGap, range: 0...120,
                        help: "Space from the sidebar or the left display edge.", savedValue: settingsConstantValue(config.gaps.outer.left)) {
                        persist("gaps", "outer.left", settingsGapValue(config.gaps.outer.left, replacingDefaultWith: outerLeftGap))
                    }
                    SettingsGapSlider(id: "gaps.outer.right", title: "Right", value: $outerRightGap, range: 0...120,
                        help: "Space from the right display edge.", savedValue: settingsConstantValue(config.gaps.outer.right)) {
                        persist("gaps", "outer.right", settingsGapValue(config.gaps.outer.right, replacingDefaultWith: outerRightGap))
                    }
                    SettingsGapSlider(id: "gaps.outer.top", title: "Top", value: $outerTopGap, range: 0...120,
                        help: "Space from the top of the usable display area.", savedValue: settingsConstantValue(config.gaps.outer.top)) {
                        persist("gaps", "outer.top", settingsGapValue(config.gaps.outer.top, replacingDefaultWith: outerTopGap))
                    }
                    SettingsGapSlider(id: "gaps.outer.bottom", title: "Bottom", value: $outerBottomGap, range: 0...120,
                        help: "Space from the bottom display edge.", savedValue: settingsConstantValue(config.gaps.outer.bottom)) {
                        persist("gaps", "outer.bottom", settingsGapValue(config.gaps.outer.bottom, replacingDefaultWith: outerBottomGap))
                    }
                }
            }
            SettingsSection("Window borders") {
                SettingsToggle("Show window borders", id: "borders.enabled", isOn: $bordersEnabled, help: "Draw a border around each visible managed window.") {
                    persist("borders", "enabled", bordersEnabled ? "true" : "false")
                }
                SettingsDoubleStepper(title: "Border width", value: $borderWidth, range: 0...20, step: 0.5, help: "Width in points; zero hides the border.") {
                    persist("borders", "width", String(borderWidth))
                }
                .disabled(!bordersEnabled)
                SettingsBorderColor("Focused window color", id: "borders.active-color", text: $activeBorderColor) {
                    persist("borders", "active-color", "'\(activeBorderColor)'")
                }
                .disabled(!bordersEnabled)
                SettingsBorderColor("Other window color", id: "borders.inactive-color", text: $inactiveBorderColor) {
                    persist("borders", "inactive-color", "'\(inactiveBorderColor)'")
                }
                .disabled(!bordersEnabled)
                SettingsPicker("Border placement", id: "borders.order", selection: $borderOrder, help: "Draw the border behind or over the window.") {
                    Text("Behind").tag(WindowBorderOrder.below)
                    Text("In front").tag(WindowBorderOrder.above)
                } onChange: {
                    persist("borders", "order", "'\(borderOrder.rawValue)'")
                }
                .disabled(!bordersEnabled)
                DisclosureGroup("App exclusions") {
                    SettingsTextField("Excluded app bundle IDs", id: "borders.exclude-apps", text: $excludedBorderApps, help: "Comma-separated bundle IDs, for example com.apple.finder.") {
                        persist("borders", "exclude-apps", tomlCommaSeparatedStringArray(excludedBorderApps))
                    }
                }
            }
        }
        .navigationTitle("Appearance")
    }

    private var hasPerMonitorGaps: Bool {
        [config.gaps.inner.horizontal, config.gaps.inner.vertical, config.gaps.outer.left,
        config.gaps.outer.right, config.gaps.outer.top, config.gaps.outer.bottom].contains {
            if case .perMonitor = $0 { return true }
            return false
        }
    }

    private func persist(_ section: String?, _ key: String, _ value: String) { persistSettingsConfig(section: section, key: key, renderedValue: value, model: model) }
}

private func settingsConstantValue(_ value: DynamicConfigValue<Int>) -> Int {
    switch value {
        case .constant(let value): value
        case .perMonitor(_, let `default`): `default`
    }
}
