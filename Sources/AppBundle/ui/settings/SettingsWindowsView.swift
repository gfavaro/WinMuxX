import SwiftUI
import Common

struct ShortcutBehaviorSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @SettingsDraft("window-tabs.enabled", load: { config.windowTabs.enabled }) private var tabEnabled: Bool
    @SettingsDraft("window-tabs.height", load: { config.windowTabs.height }) private var tabHeight: Int
    @State private var doubleSidedWindows = ExperimentalUISettings().doubleSidedWindows
    @SettingsDraft("automatically-tile-new-windows", load: { config.automaticallyTileNewWindows }) private var automaticallyTileNewWindows: Bool
    @SettingsDraft("auto-add-new-windows-to-tab-group", load: { config.autoAddNewWindowsToTabGroup }) private var autoAddNewWindowsToTabGroup: Bool
    @SettingsDraft("enable-shake-to-toggle-tiling", load: { config.enableShakeToToggleTiling }) private var enableShakeToToggleTiling: Bool
    @SettingsDraft("automatically-unhide-macos-hidden-apps", load: { config.automaticallyUnhideMacosHiddenApps }) private var automaticallyUnhideMacosHiddenApps: Bool
    @SettingsDraft("default-root-container-layout", load: { config.defaultRootContainerLayout }) private var defaultLayout: Layout
    @SettingsDraft("default-root-container-orientation", load: { config.defaultRootContainerOrientation }) private var defaultOrientation: DefaultContainerOrientation
    @SettingsDraft("enable-normalization-flatten-containers", load: { config.enableNormalizationFlattenContainers }) private var flattenContainers: Bool
    @SettingsDraft("enable-normalization-opposite-orientation-for-nested-containers", load: { config.enableNormalizationOppositeOrientationForNestedContainers }) private var normalizeNestedContainers: Bool
    @SettingsDraft("focus-follows-mouse", load: { config.focusFollowsMouse }) private var focusFollowsMouse: Bool
    @SettingsDraft("focus-follows-mouse-dwell", load: { config.focusFollowsMouseDwell }) private var focusFollowsMouseDwell: Int

    @SettingsDraft("single-window-alignment", load: { config.singleWindowAlignment }) private var singleWindowAlignment: SingleWindowAlignment
    @SettingsDraft("single-window-aspect-ratio", load: { config.singleWindowAspectRatio }) private var aspectRatio: DynamicConfigValue<Double>

    var body: some View {
        SettingsScrollView {
            SettingsSection("New windows") {
                SettingsToggle("Tile new windows automatically", id: "automatically-tile-new-windows", isOn: $automaticallyTileNewWindows, help: "Place new windows in the current tiled layout.") { persistRootBool("automatically-tile-new-windows", automaticallyTileNewWindows) }
                SettingsToggle("Add new windows to the current tab group", id: "auto-add-new-windows-to-tab-group", isOn: $autoAddNewWindowsToTabGroup, help: "Keep new windows in the selected stack instead of creating a new tile.") { persistRootBool("auto-add-new-windows-to-tab-group", autoAddNewWindowsToTabGroup) }
                SettingsToggle("Unhide macOS-hidden apps", id: "automatically-unhide-macos-hidden-apps", isOn: $automaticallyUnhideMacosHiddenApps, help: "Restore apps macOS has hidden when they receive focus.") { persistRootBool("automatically-unhide-macos-hidden-apps", automaticallyUnhideMacosHiddenApps) }
            }
            SettingsSection("Default layout") {
                SettingsPicker("Root layout", id: "default-root-container-layout", selection: $defaultLayout, help: "Used for new workspaces. Selecting Dwindle also updates existing tiled workspaces.") {
                    Text("Dwindle").tag(Layout.dwindle)
                    Text("Tiles").tag(Layout.tiles)
                    Text("Tab group").tag(Layout.tabGroup)
                } onChange: { persistRootString("default-root-container-layout", defaultLayout.rawValue) }
                Text("Defaults apply to new workspaces. Selecting Dwindle also updates existing tiled workspaces.")
                    .font(.callout).foregroundStyle(.secondary)
                SettingsPicker("Root orientation", id: "default-root-container-orientation", selection: $defaultOrientation, help: "Controls how new tiled containers split.") {
                    Text("Automatic").tag(DefaultContainerOrientation.auto)
                    Text("Horizontal").tag(DefaultContainerOrientation.horizontal)
                    Text("Vertical").tag(DefaultContainerOrientation.vertical)
                } onChange: { persistRootString("default-root-container-orientation", defaultOrientation.rawValue) }
                .pickerStyle(.segmented)

            }
            SettingsSection("Single window on ultrawide") {
                SettingsPicker("Alignment", id: "single-window-alignment", selection: $singleWindowAlignment,
                    help: "Position a lone ultrawide tile within the available area after sidebar and gaps.") {
                    Text("Centered").tag(SingleWindowAlignment.center)
                    Text("Left").tag(SingleWindowAlignment.left)
                    Text("Right").tag(SingleWindowAlignment.right)
                } onChange: { persistRootString("single-window-alignment", singleWindowAlignment.rawValue) }
                Text("Resizing width keeps the window tiled. Changing height makes it floating and preserves the gesture’s size and position.")
                    .font(.callout).foregroundStyle(.secondary)
                ratioControl("Maximum aspect ratio", value: Binding(get: { aspectRatio.defaultAspectRatio }, set: { updateRatio(defaultValue: $0) }))
                Text("1.5 equals 3:2. 0 disables the limit. Applies only to screens with width/height ≥ 2.3.")
                    .font(.callout).foregroundStyle(.secondary)

            }
            SettingsSection("Pointer focus") {
                SettingsToggle("Focus windows under the pointer", id: "focus-follows-mouse", isOn: $focusFollowsMouse, help: "Focus the tiled window after the pointer rests over it.") {
                    persistRootBool("focus-follows-mouse", focusFollowsMouse)
                }
                SettingsStepper("Hover delay", id: "focus-follows-mouse-dwell", value: $focusFollowsMouseDwell, range: 0...2000, help: "Time the pointer must remain still before focusing the window.", unit: "ms") {
                    persistRootInt("focus-follows-mouse-dwell", focusFollowsMouseDwell)
                }
                .disabled(!focusFollowsMouse)
                Text("A delay of 0 focuses immediately. Mouse clicks and window manipulation always take priority.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            SettingsSection("Window tabs") {
                if !tabEnabled { Text("Tab strip height is available when Show tab strips is enabled.").font(.callout).foregroundStyle(.secondary) }
                SettingsToggle("Show tab strips", id: "window-tabs.enabled", isOn: $tabEnabled, help: "Display browser-like tabs for stacked windows.") { persistConfig(section: "window-tabs", key: "enabled", value: tabEnabled ? "true" : "false") }
                SettingsStepper("Tab strip height", id: "window-tabs.height", value: $tabHeight, range: 36...80, help: "Height of the window tab strip.") { persistConfig(section: "window-tabs", key: "height", value: "\(tabHeight)") }
                .disabled(!tabEnabled)


                SettingsToggle("Double-sided windows", id: "ui.double-sided-windows", isOn: $doubleSidedWindows, help: "Replace two-window tab strips with two sides. Option-click anywhere in the window or press Option-Tab to flip.") {
                    var settings = ExperimentalUISettings()
                    settings.doubleSidedWindows = doubleSidedWindows
                    if doubleSidedWindows { requestScreenRecordingPermissionsIfNeeded() }
                    scheduleRefreshSession(.menuBarButton)
                }
                .disabled(!tabEnabled)
                Text("Option-click anywhere in the window or press Option-Tab to flip between two windows. Three or more windows use tabs. Show tab strips must be enabled. When it is off, groups use overlapping windows with offsets. Rotation uses Screen Recording access and respects Reduce Motion.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)

            }
            SettingsSection("Advanced layout") {
                SettingsToggle("Shake to toggle tiling", id: "enable-shake-to-toggle-tiling", isOn: $enableShakeToToggleTiling, help: "Shake a window by its title bar to switch between floating and tiled.") { persistRootBool("enable-shake-to-toggle-tiling", enableShakeToToggleTiling) }
                DisclosureGroup("Container normalization") {
                SettingsToggle("Flatten matching containers", id: "enable-normalization-flatten-containers", isOn: $flattenContainers, help: "Simplify adjacent containers with the same layout orientation.") { persistRootBool("enable-normalization-flatten-containers", flattenContainers) }
                SettingsToggle("Normalize nested orientations", id: "enable-normalization-opposite-orientation-for-nested-containers", isOn: $normalizeNestedContainers, help: "Avoid nested tiled containers with the same orientation.") { persistRootBool("enable-normalization-opposite-orientation-for-nested-containers", normalizeNestedContainers) }
                }
            }

        }
        .navigationTitle("Windows")

    }

    private func ratioControl(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Ratio", value: value, format: .number)
                .frame(width: 80, height: 28)
                .accessibilityLabel(title + " aspect ratio")
                .accessibilityHint("1.5 means 3:2. Zero disables the limit.")
            Stepper(title + " aspect ratio", value: value, in: 0...max(100, value.wrappedValue), step: 0.1)
                .labelsHidden().frame(minHeight: 28)
                .accessibilityValue(String(value.wrappedValue))
        }
    }

    private func updateRatio(defaultValue: Double) {
        guard defaultValue.isFinite && defaultValue >= 0 else { return }
        let rules = aspectRatio.aspectRatioRules
        aspectRatio = rules.isEmpty ? .constant(defaultValue) : .perMonitor(rules, default: defaultValue)
        persistConfig(section: nil, key: "single-window-aspect-ratio", value: renderedAspectRatio(aspectRatio))
    }

    private func persistRootBool(_ key: String, _ value: Bool) {
        persistConfig(section: nil, key: key, value: value ? "true" : "false")
    }

    private func persistRootString(_ key: String, _ value: String) { persistConfig(section: nil, key: key, value: "'\(value)'") }
    private func persistRootInt(_ key: String, _ value: Int) { persistConfig(section: nil, key: key, value: "\(value)") }
    private func persistConfig(section: String?, key: String, value: String) {
        persistSettingsConfig(section: section, key: key, renderedValue: value, model: model)
    }
}
