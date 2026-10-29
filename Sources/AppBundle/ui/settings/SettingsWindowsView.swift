import AppKit
import SwiftUI
import Common

struct ShortcutBehaviorSettingsView: View {
    @ObservedObject private var workspaceTouch = RawWorkspaceTouchSource.shared
    @ObservedObject private var minimums = PersistedAppMinimums.shared
    @ObservedObject var model: ShortcutSettingsModel
    @SettingsDraft("window-tabs.enabled", load: { config.windowTabs.enabled }) private var tabEnabled: Bool
    @SettingsDraft("window-tabs.height", load: { config.windowTabs.height }) private var tabHeight: Int
    @SettingsDraft("drag-stack-layout", load: { config.dragStackLayout }) private var dragStackLayout: Layout
    @SettingsDraft("workspace-swipe.animation-duration-ms", load: { config.workspaceSwipe.animationDurationMs }) private var swipeAnimationDuration: Int
    @SettingsDraft("workspace-overview.three-finger-up", load: { config.workspaceOverview.threeFingerUp }) private var overviewGesture: Bool
    @SettingsDraft("workspace-swipe.enabled", load: { config.workspaceSwipe.enabled }) private var workspaceSwipes: Bool
    @SettingsDraft("workspace-swipe.reverse-direction", load: { config.workspaceSwipe.reverseDirection }) private var reverseWorkspaceSwipes: Bool
    @SettingsDraft("scrolling.column-width", load: { Int((config.scrolling.columnWidth * 100).rounded()) }) private var scrollingColumnWidth: Int
    @SettingsDraft("scrolling.width-presets", load: { config.scrolling.widthPresets.map { String($0 * 100) }.joined(separator: ", ") }) private var scrollingWidthPresets: String
    @SettingsDraft("scrolling.gesture-enabled", load: { config.scrolling.gestureEnabled }) private var scrollingGestureEnabled: Bool
    @SettingsDraft("scrolling.gesture-sensitivity", load: { String(config.scrolling.gestureSensitivity) }) private var scrollingSensitivity: String
    @SettingsDraft("scrolling.minimap-enabled", load: { config.scrolling.minimapEnabled }) private var scrollingMinimapEnabled: Bool
    @SettingsDraft("scrolling.center-focused-column", load: { config.scrolling.centerFocusedColumn }) private var scrollingCenterMode: ScrollingCenterMode
    @SettingsDraft("scrolling.minimap-hold-modifiers", load: { minimapHoldModifierNames(config.scrolling.minimapHoldModifiers) }) private var minimapHoldModifiers: String
    @SettingsDraft("master.size", load: { Int((config.master.size * 100).rounded()) }) private var masterSize: Int
    @SettingsDraft("master.side", load: { config.master.side }) private var masterSide: MasterSide
    @SettingsDraft("master.stack-layout", load: { config.master.stackLayout }) private var masterStackLayout: Layout
    @SettingsDraft("master.ultrawide-mains", load: { config.master.ultrawideMains }) private var masterUltrawideMains: Int
    @SettingsDraft("hover-bar.enabled", load: { config.hoverBar.enabled }) private var hoverBarEnabled: Bool
    @SettingsDraft("follow-app-activation.enabled", load: { config.followAppActivation.enabled }) private var followAppActivation: Bool
    @SettingsDraft("follow-app-activation.exclude-apps", load: { config.followAppActivation.excludeApps.joined(separator: ", ") }) private var followAppActivationExcluded: String
    @SettingsDraft("window-tabs.double-sided-windows", load: { config.windowTabs.doubleSidedWindows }) private var doubleSidedWindows: Bool
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
    @State private var confirmsForgetAllMinimums = false
    @State private var fitIssues: [WorkspaceFitIssue] = []

    @SettingsDraft("single-window-alignment", load: { config.singleWindowAlignment }) private var singleWindowAlignment: SingleWindowAlignment
    @SettingsDraft("fullscreen-width", load: { config.fullscreenWidth ?? 1.0 }) private var fullscreenWidth: Double

    var body: some View {
        SettingsScrollView {
            SettingsSection("New windows") {
                SettingsToggle("Tile new windows automatically", id: "automatically-tile-new-windows", isOn: $automaticallyTileNewWindows, help: "Place new windows in the current tiled layout.") { persistRootBool("automatically-tile-new-windows", automaticallyTileNewWindows) }
                SettingsToggle("Add new windows to the current tab group", id: "auto-add-new-windows-to-tab-group", isOn: $autoAddNewWindowsToTabGroup, help: "Keep new windows in the selected stack instead of creating a new tile.") { persistRootBool("auto-add-new-windows-to-tab-group", autoAddNewWindowsToTabGroup) }
                SettingsToggle("Unhide macOS-hidden apps", id: "automatically-unhide-macos-hidden-apps", isOn: $automaticallyUnhideMacosHiddenApps, help: "Restore apps macOS has hidden when they receive focus.") { persistRootBool("automatically-unhide-macos-hidden-apps", automaticallyUnhideMacosHiddenApps) }
            }
            learnedMinimumsSection
            fitDiagnosticsSection
            SettingsSection("Default layout") {
                SettingsPicker("Default drag stack", id: "drag-stack-layout", selection: $dragStackLayout, help: "Layout for a new group created by dropping a window onto another. Existing groups keep their layout; edge drops still split.") {
                    Text("Accordion").tag(Layout.stacked)
                    Text("Tabbed").tag(Layout.tabGroup)
                } onChange: { persistRootString("drag-stack-layout", dragStackLayout.rawValue) }
                SettingsPicker("Root layout", id: "default-root-container-layout", selection: $defaultLayout, help: "Used for new workspaces. Selecting Dwindle also updates existing tiled workspaces.") {
                    Text("Dwindle").tag(Layout.dwindle)
                    Text("Master").tag(Layout.master)
                    Text("Tiles").tag(Layout.tiles)
                    Text("Stacked: Tabbed").tag(Layout.tabGroup)
                    Text("Stacked: Accordion").tag(Layout.stacked)
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
            SettingsSection("Lone windows and fullscreen") {
                SettingsStepper("Width", id: "fullscreen-width", value: Binding(
                    get: { Int((fullscreenWidth * 100).rounded()) },
                    set: { fullscreenWidth = Double($0) / 100 }), range: 10...100,
                    help: "Share of the available width for a lone tiled window or WinMuxX fullscreen. Display and workspace overrides take priority.", unit: "%") {
                    persistConfig(section: nil, key: "fullscreen-width", value: String(fullscreenWidth))
                }
                Text("Applies after sidebar and outer gaps on any display. Fullscreen stays centered; alignment below applies to lone tiled windows.")
                    .font(.callout).foregroundStyle(.secondary)
                if let width = focus.workspace.windowWidthSettings.fullscreenWidth {
                    Text("Current workspace: \(Int((width * 100).rounded()))% · \(focus.workspace.windowWidthSettings.singleWindowAlignment?.rawValue ?? "center") · \(focus.workspace.workspaceMonitor.name)")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Current workspace uses the legacy aspect-ratio setting. Saving a width switches to percentage sizing.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                SettingsPicker("Alignment", id: "single-window-alignment", selection: $singleWindowAlignment,
                    help: "Position a lone tiled window within the available area after sidebar and gaps.") {
                    Text("Centered").tag(SingleWindowAlignment.center)
                    Text("Left").tag(SingleWindowAlignment.left)
                    Text("Right").tag(SingleWindowAlignment.right)
                } onChange: { persistRootString("single-window-alignment", singleWindowAlignment.rawValue) }
                Text("Resizing width keeps the window tiled. Changing height makes it floating and preserves the gesture’s size and position.")
                    .font(.callout).foregroundStyle(.secondary)

            }
            if runtime.workspaceBackend.kind == .native {
                SettingsSection("Gestures") {
                    Text("WinMuxX is using macOS Spaces, so macOS swipes between desktops and opens Mission Control. Hold Option and scroll with two fingers to pan a scrolling desktop.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                SettingsSection("Workspace swipes — experimental") {
                    SettingsToggle("Enable workspace swipes", id: "workspace-swipe.enabled", isOn: $workspaceSwipes, help: "Three-finger horizontal swipes switch existing workspaces on the display under the pointer. Stops at either end.") {
                        persistConfig(section: "workspace-swipe", key: "enabled", value: workspaceSwipes ? "true" : "false")
                    }
                    SettingsToggle("Reverse swipe direction", id: "workspace-swipe.reverse-direction", isOn: $reverseWorkspaceSwipes, help: "Default: swipe left for next, right for previous.") {
                        persistConfig(section: "workspace-swipe", key: "reverse-direction", value: reverseWorkspaceSwipes ? "true" : "false")
                    }
                    .disabled(!workspaceSwipes)
                    SettingsStepper("Swipe settle duration", id: "workspace-swipe.animation-duration-ms", value: $swipeAnimationDuration, range: 0...1000,
                        help: "Workspace previews follow your fingers. Flick to switch, or drag past halfway. Pull back before releasing to return. Zero disables the visual preview. Respects Reduce Motion and the global animation setting.", unit: "ms") {
                        persistConfig(section: "workspace-swipe", key: "animation-duration-ms", value: String(swipeAnimationDuration))
                    }
                    .disabled(!workspaceSwipes)
                    Text(workspaceTouch.status + (workspaceTouch.maximumFingerCount > 0 ? " · Detected up to \(workspaceTouch.maximumFingerCount) fingers" : ""))
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Uses the private macOS raw-touch API. Exactly three fingers. Flick to switch, or drag past halfway. Pull back before releasing to return. Set Swipe between full-screen apps to four fingers or off in macOS Trackpad settings to avoid conflicts. Normal two-finger scrolling stays with your apps.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                SettingsSection("Workspace overview") {
                    SettingsToggle("Three-finger swipe up", id: "workspace-overview.three-finger-up", isOn: $overviewGesture, help: "Show the current project's workspaces on each display.") {
                        persistConfig(section: "workspace-overview", key: "three-finger-up", value: overviewGesture ? "true" : "false")
                    }
                    Text("Use workspace-overview from a shortcut or the CLI. For the gesture, assign macOS Mission Control to four fingers or turn its gesture off in Trackpad settings. Minimized windows, hidden apps and native full-screen windows are excluded.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            masterSettingsSection
            scrollingSettingsSection
            SettingsSection("Hover bar") {
                SettingsToggle("Show quick actions above windows", id: "hover-bar.enabled", isOn: $hoverBarEnabled,
                    help: "Rest the pointer on the middle of a tiled window's top edge for Main (Master), Focus and Float; a focused window offers Unfocus.") {
                    persistConfig(section: "hover-bar", key: "enabled", value: hoverBarEnabled ? "true" : "false")
                }
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
                SettingsToggle("Follow app activation", id: "follow-app-activation.enabled", isOn: $followAppActivation,
                    help: "When another app comes to the front (Dock, Cmd-Tab, a notification), focus follows it to its workspace.") {
                    persistConfig(section: "follow-app-activation", key: "enabled", value: followAppActivation ? "true" : "false")
                }
                SettingsTextField("Apps not followed", id: "follow-app-activation.exclude-apps", text: $followAppActivationExcluded,
                    help: "Comma-separated bundle IDs whose activation leaves focus where it is, for example com.apple.finder.") {
                    persistConfig(section: "follow-app-activation", key: "exclude-apps", value: tomlCommaSeparatedStringArray(followAppActivationExcluded))
                }
                .disabled(!followAppActivation)
            }
            SettingsSection("Window tabs") {
                if !tabEnabled { Text("Tab strip height is available when Show tab strips is enabled.").font(.callout).foregroundStyle(.secondary) }
                SettingsToggle("Show tab strips", id: "window-tabs.enabled", isOn: $tabEnabled, help: "Display browser-like tabs for stacked windows.") { persistConfig(section: "window-tabs", key: "enabled", value: tabEnabled ? "true" : "false") }
                SettingsStepper("Tab strip height", id: "window-tabs.height", value: $tabHeight, range: 36...80, help: "Height of the window tab strip.") { persistConfig(section: "window-tabs", key: "height", value: "\(tabHeight)") }
                .disabled(!tabEnabled)


                SettingsToggle("Double-sided windows", id: "window-tabs.double-sided-windows", isOn: $doubleSidedWindows, help: "Replace two-window tab strips with two sides. Option-click anywhere in the window or press Option-Tab to flip.") {
                    persistSettingsConfig(section: "window-tabs", key: "double-sided-windows",
                        renderedValue: doubleSidedWindows ? "true" : "false", model: model) {
                        if config.windowTabs.doubleSidedWindows { requestScreenRecordingPermissionsIfNeeded() }
                    }
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
        .onAppear { refreshFitDiagnostics() }
        .onChange(of: minimums.revision) { _ in refreshFitDiagnostics() }
        .confirmationDialog("Forget all learned minimum sizes?", isPresented: $confirmsForgetAllMinimums, titleVisibility: .visible) {
            Button("Forget All", role: .destructive) { minimums.forgetAll() }
        } message: {
            Text("WinMuxX will relearn app minimums from future resize attempts.")
        }

    }

    private var learnedMinimumsSection: some View {
        SettingsSection("Learned minimum sizes") {
            if minimums.snapshot.isEmpty {
                Text("No confirmed app minimum sizes have been saved.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(minimums.snapshot) { evidence in
                    HStack(spacing: 12) {
                        Image(nsImage: minimumAppIcon(evidence.bundleId))
                            .resizable().frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(minimumAppName(evidence.bundleId)).font(.body)
                            Text(evidence.bundleId).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(minimumSizeDescription(evidence.size)).font(.callout.monospacedDigit())
                            if !evidence.unknownAxes.isEmpty {
                                Text("Unknown \(evidence.unknownAxes.joined(separator: ", "))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button("Forget") { minimums.forget(evidence.bundleId) }
                            .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
                Button("Forget All…", role: .destructive) { confirmsForgetAllMinimums = true }
                    .padding(.top, 4)
            }
            Text("Only stable, confirmed resize refusals are saved. Forgetting an app also clears its current evidence and prevents an older saved snapshot from restoring it.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var fitDiagnosticsSection: some View {
        SettingsSection("Layout fit diagnostics") {
            if fitIssues.isEmpty {
                Text("No tiled group or visible scrolling column exceeds its available layout area.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(fitIssues) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.kind == .tiledGroup ? "Tiled group minimum exceeds its layout area" : "Scrolling column minimum exceeds the viewport")
                            .font(.body)
                        Text("Workspace \(workspaceDisplayName(runtime.workspaces.workspaceById[issue.workspaceId]?.name ?? issue.workspaceId.rawValue)) · minimum \(minimumSizeDescription(issue.minimumSize)) · available \(minimumSizeDescription(issue.availableSize))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            Text("Offscreen scrolling columns are intentionally reachable by scrolling and are not reported as fit failures.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func refreshFitDiagnostics() {
        fitIssues = workspaceFitIssues(in: orderedWorkspacesForPresentation())
    }

    private var scrollingSettingsSection: some View {
        SettingsSection("Scrolling workspaces") {
            SettingsStepper("Default column width", id: "scrolling.column-width", value: $scrollingColumnWidth,
                range: 10...100, help: "Preferred share of the usable display width. A lone column still fills the display.", unit: "%") {
                persistConfig(section: "scrolling", key: "column-width", value: String(Double(scrollingColumnWidth) / 100))
            }
            SettingsTextField("Width presets (%)", id: "scrolling.width-presets", text: $scrollingWidthPresets,
                help: "Comma-separated ascending percentages from 10 to 100.", validate: scrollingPresetError) {
                if let values = scrollingPresetValues(scrollingWidthPresets) {
                    persistConfig(section: "scrolling", key: "width-presets", value: "[" + values.map { String($0) }.joined(separator: ", ") + "]")
                }
            }
            SettingsToggle("Option + three-finger pan", id: "scrolling.gesture-enabled", isOn: $scrollingGestureEnabled,
                help: "Pan the horizontal strip. Plain horizontal swipes still switch workspaces.") {
                persistConfig(section: "scrolling", key: "gesture-enabled", value: scrollingGestureEnabled ? "true" : "false")
            }
            SettingsTextField("Gesture sensitivity", id: "scrolling.gesture-sensitivity", text: $scrollingSensitivity,
                help: "Multiplier for the default pan distance. Enter a finite value greater than zero.", validate: scrollingSensitivityError) {
                if let value = Double(scrollingSensitivity), value.isFinite, value > 0 {
                    persistConfig(section: "scrolling", key: "gesture-sensitivity", value: String(value))
                }
            }
            SettingsToggle("Show scrolling minimap", id: "scrolling.minimap-enabled", isOn: $scrollingMinimapEnabled,
                help: "Show the workspace map while panning and allow it to be opened from Layout or a shortcut.") {
                persistConfig(section: "scrolling", key: "minimap-enabled", value: scrollingMinimapEnabled ? "true" : "false")
            }
            SettingsTextField("Hold to keep the minimap up", id: "scrolling.minimap-hold-modifiers", text: $minimapHoldModifiers,
                help: "Comma-separated keys from ctrl, alt, cmd and shift; while they are held the minimap stays open. Empty turns this off.",
                validate: minimapHoldModifierError) {
                if minimapHoldModifierError(minimapHoldModifiers) == nil {
                    persistConfig(section: "scrolling", key: "minimap-hold-modifiers", value: tomlCommaSeparatedStringArray(minimapHoldModifiers))
                }
            }
            SettingsPicker("Centre the focused column", id: "scrolling.center-focused-column", selection: $scrollingCenterMode,
                help: "Where focusing a column scrolls the strip.") {
                Text("Never: just bring it into view").tag(ScrollingCenterMode.never)
                Text("Only when the strip overflows").tag(ScrollingCenterMode.onOverflow)
                Text("Always").tag(ScrollingCenterMode.always)
            } onChange: { persistConfig(section: "scrolling", key: "center-focused-column", value: "'\(scrollingCenterMode.rawValue)'") }
        }
    }

    private var masterSettingsSection: some View {
        SettingsSection("Master workspaces") {
            SettingsStepper("Main window size", id: "master.size", value: $masterSize, range: 10...90,
                help: "Share of the display the main window takes. Dragging the split changes it per workspace.", unit: "%") {
                persistConfig(section: "master", key: "size", value: String(Double(masterSize) / 100))
            }
            SettingsPicker("Main window side", id: "master.side", selection: $masterSide, help: "Where the main window sits; the stack takes the other side.") {
                Text("Left").tag(MasterSide.left)
                Text("Right").tag(MasterSide.right)
                Text("Top").tag(MasterSide.top)
                Text("Bottom").tag(MasterSide.bottom)
            } onChange: { persistConfig(section: "master", key: "side", value: "'\(masterSide.rawValue)'") }
            SettingsPicker("Stack layout", id: "master.stack-layout", selection: $masterStackLayout, help: "How the windows beside the main one share their space.") {
                Text("Tiles").tag(Layout.tiles)
                Text("Accordion").tag(Layout.stacked)
            } onChange: { persistConfig(section: "master", key: "stack-layout", value: "'\(masterStackLayout.rawValue)'") }
            SettingsPicker("Main windows on ultrawide displays", id: "master.ultrawide-mains", selection: $masterUltrawideMains,
                help: "On a display at least twice as wide as tall, two puts the next window beside the main one and stacks the rest in a narrow column. Left or right side only.") {
                Text("One").tag(1)
                Text("Two, side by side").tag(2)
            } onChange: { persistConfig(section: "master", key: "ultrawide-mains", value: String(masterUltrawideMains)) }
        }
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

private let minimapHoldModifierFlags: [(String, NSEvent.ModifierFlags)] = [("ctrl", .control), ("alt", .option), ("cmd", .command), ("shift", .shift)]

func minimapHoldModifierNames(_ flags: NSEvent.ModifierFlags) -> String {
    minimapHoldModifierFlags.filter { flags.contains($0.1) }.map(\.0).joined(separator: ", ")
}

func minimapHoldModifierError(_ text: String) -> String? {
    let names = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let unknown = names.filter { name in !minimapHoldModifierFlags.contains { $0.0 == name } }
    return unknown.isEmpty ? nil : "Unknown key: \(unknown.joined(separator: ", ")). Use ctrl, alt, cmd or shift."
}

private func minimumAppName(_ bundleId: String) -> String {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.localizedName
        ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId).flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String }
        ?? bundleId
}

private func minimumAppIcon(_ bundleId: String) -> NSImage {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "Application") ?? NSImage(size: NSSize(width: 24, height: 24))
}

private func minimumSizeDescription(_ size: CGSize) -> String {
    let width = size.width == 0 ? "?" : String(Int(size.width.rounded()))
    let height = size.height == 0 ? "?" : String(Int(size.height.rounded()))
    return "\(width) × \(height)"
}

private func scrollingPresetValues(_ text: String) -> [Double]? {
    let parts = text.split(separator: ",", omittingEmptySubsequences: false)
    let values = parts.compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.map { $0 / 100 }
    guard values.count == parts.count, !values.isEmpty,
          values.allSatisfy({ $0.isFinite && (0.1...1).contains($0) }),
          zip(values, values.dropFirst()).allSatisfy(<) else { return nil }
    return values
}

private func scrollingPresetError(_ text: String) -> String? {
    scrollingPresetValues(text) == nil ? "Enter ascending percentages between 10 and 100, separated by commas." : nil
}

private func scrollingSensitivityError(_ text: String) -> String? {
    guard let value = Double(text), value.isFinite, value > 0 else { return "Enter a finite value greater than zero." }
    return nil
}
