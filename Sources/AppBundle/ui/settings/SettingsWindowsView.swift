import SwiftUI

struct ShortcutBehaviorSettingsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var doubleSidedWindows = ExperimentalUISettings().doubleSidedWindows
    @State private var automaticallyTileNewWindows = config.automaticallyTileNewWindows
    @State private var autoAddNewWindowsToTabGroup = config.autoAddNewWindowsToTabGroup
    @State private var enableShakeToToggleTiling = config.enableShakeToToggleTiling
    @State private var automaticallyUnhideMacosHiddenApps = config.automaticallyUnhideMacosHiddenApps
    @State private var defaultLayout = config.defaultRootContainerLayout
    @State private var defaultOrientation = config.defaultRootContainerOrientation
    @State private var flattenContainers = config.enableNormalizationFlattenContainers
    @State private var normalizeNestedContainers = config.enableNormalizationOppositeOrientationForNestedContainers
    @State private var focusFollowsMouse = config.focusFollowsMouse
    @State private var focusFollowsMouseDwell = config.focusFollowsMouseDwell

    var body: some View {
        SettingsScrollView {
            if let error = model.errorMessage {
                SettingsSection("Could not save setting") {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            SettingsSection("New windows") {
                SettingsToggle("Tile new windows automatically", isOn: $automaticallyTileNewWindows, help: "Place new windows in the current tiled layout.") { persistRootBool("automatically-tile-new-windows", automaticallyTileNewWindows) }
                SettingsToggle("Add new windows to the current tab group", isOn: $autoAddNewWindowsToTabGroup, help: "Keep new windows in the selected stack instead of creating a new tile.") { persistRootBool("auto-add-new-windows-to-tab-group", autoAddNewWindowsToTabGroup) }
                SettingsToggle("Unhide macOS-hidden apps", isOn: $automaticallyUnhideMacosHiddenApps, help: "Restore apps macOS has hidden when they receive focus.") { persistRootBool("automatically-unhide-macos-hidden-apps", automaticallyUnhideMacosHiddenApps) }
            }
            SettingsSection("Pointer focus") {
                SettingsToggle("Focus windows under the pointer", isOn: $focusFollowsMouse, help: "Focus the tiled window after the pointer rests over it.") {
                    persistRootBool("focus-follows-mouse", focusFollowsMouse)
                }
                SettingsStepper("Hover delay", value: $focusFollowsMouseDwell, range: 0...2000, help: "Time the pointer must remain still before focusing the window.", unit: "ms") {
                    persistRootInt("focus-follows-mouse-dwell", focusFollowsMouseDwell)
                }
                .disabled(!focusFollowsMouse)
                Text("A delay of 0 focuses immediately. Mouse clicks and window manipulation always take priority.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsSection("Window pairs") {
                SettingsToggle("Double-sided windows", isOn: $doubleSidedWindows, help: "Replace two-window tab strips with two sides. Option-click anywhere in the window or press Option-Tab to flip.") {
                    var settings = ExperimentalUISettings()
                    settings.doubleSidedWindows = doubleSidedWindows
                    if doubleSidedWindows { requestScreenRecordingPermissionsIfNeeded() }
                    scheduleRefreshSession(.menuBarButton)
                }
                Text("Option-click anywhere in the window or press Option-Tab to flip between two windows. Three or more windows use tabs. Window tabs must be enabled. Rotation uses Screen Recording access and respects Reduce Motion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }
            SettingsSection("Advanced layout") {
                SettingsToggle("Shake to toggle tiling", isOn: $enableShakeToToggleTiling, help: "Shake a window by its title bar to switch between floating and tiled.") { persistRootBool("enable-shake-to-toggle-tiling", enableShakeToToggleTiling) }
                DisclosureGroup("Container normalization") {
                SettingsToggle("Flatten matching containers", isOn: $flattenContainers, help: "Simplify adjacent containers with the same layout orientation.") { persistRootBool("enable-normalization-flatten-containers", flattenContainers) }
                SettingsToggle("Normalize nested orientations", isOn: $normalizeNestedContainers, help: "Avoid nested tiled containers with the same orientation.") { persistRootBool("enable-normalization-opposite-orientation-for-nested-containers", normalizeNestedContainers) }
                }
            }
            SettingsSection("Default layout") {
                SettingsPicker("Root layout", selection: $defaultLayout, help: "Used for new workspaces. Selecting Dwindle also updates existing tiled workspaces.") {
                    Text("Dwindle").tag(Layout.dwindle)
                    Text("Tiles").tag(Layout.tiles)
                    Text("Tab group").tag(Layout.tabGroup)
                } onChange: { persistRootString("default-root-container-layout", defaultLayout.rawValue) }
                Text("Defaults apply to new workspaces. Selecting Dwindle also updates existing tiled workspaces.")
                    .font(.caption).foregroundStyle(.secondary)
                SettingsPicker("Root orientation", selection: $defaultOrientation, help: "Controls how new tiled containers split.") {
                    Text("Automatic").tag(DefaultContainerOrientation.auto)
                    Text("Horizontal").tag(DefaultContainerOrientation.horizontal)
                    Text("Vertical").tag(DefaultContainerOrientation.vertical)
                } onChange: { persistRootString("default-root-container-orientation", defaultOrientation.rawValue) }
                .pickerStyle(.segmented)

            }
        }
        .navigationTitle("Windows")
        .id(model.settingsRevision)
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
