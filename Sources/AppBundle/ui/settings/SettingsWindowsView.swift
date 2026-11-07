import AppKit
import SwiftUI
import Common

struct ShortcutBehaviorSettingsView: View {
    @ObservedObject private var minimums = PersistedAppMinimums.shared
    @ObservedObject var model: ShortcutSettingsModel
    @SettingsDraft("window-tabs.enabled", load: { config.windowTabs.enabled }) private var tabEnabled: Bool
    @SettingsDraft("window-tabs.height", load: { config.windowTabs.height }) private var tabHeight: Int
    @SettingsDraft("workspace-overview.three-finger-up", load: { config.workspaceOverview.threeFingerUp }) private var overviewGesture: Bool
    @SettingsDraft("workspace-swipe.enabled", load: { config.workspaceSwipe.enabled }) private var workspaceSwipes: Bool
    @SettingsDraft("master.size", load: { Int((config.master.size * 100).rounded()) }) private var masterSize: Int
    @SettingsDraft("master.side", load: { config.master.side }) private var masterSide: MasterSide
    @SettingsDraft("master.stack-layout", load: { config.master.stackLayout }) private var masterStackLayout: Layout
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
    @State private var confirmsForgetAllMinimums = false
    @State private var fitIssues: [WorkspaceFitIssue] = []

    @SettingsDraft("fullscreen-width", load: { config.fullscreenWidth ?? 1.0 }) private var fullscreenWidth: Double

    var body: some View {
        SettingsScrollView {
            SettingsSection("New windows") {
                SettingsToggle(.automaticallyTileNewWindows, isOn: $automaticallyTileNewWindows, help: "Place new windows in the current tiled layout.") { persistRootBool("automatically-tile-new-windows", automaticallyTileNewWindows) }
                SettingsToggle(.autoAddNewWindowsToTabGroup, isOn: $autoAddNewWindowsToTabGroup, help: "Keep new windows in the selected stack instead of creating a new tile.") { persistRootBool("auto-add-new-windows-to-tab-group", autoAddNewWindowsToTabGroup) }
                SettingsToggle(.automaticallyUnhideApps, isOn: $automaticallyUnhideMacosHiddenApps, help: "Restore apps macOS has hidden when they receive focus.") { persistRootBool("automatically-unhide-macos-hidden-apps", automaticallyUnhideMacosHiddenApps) }
            }
            learnedMinimumsSection
            fitDiagnosticsSection
            SettingsSection("Default layout") {
                SettingsLayoutPreviews()
                SettingsPicker(.defaultLayout, selection: $defaultLayout, help: "Used for new workspaces. Selecting Dwindle also updates existing tiled workspaces.") {
                    Text("Dwindle").tag(Layout.dwindle)
                    Text("Master").tag(Layout.master)
                    Text("Tiles").tag(Layout.tiles)
                    Text("Stacked: Tabbed").tag(Layout.tabGroup)
                    Text("Stacked: Accordion").tag(Layout.stacked)
                } onChange: { persistRootString("default-root-container-layout", defaultLayout.rawValue) }
                Text("Defaults apply to new workspaces. Selecting Dwindle also updates existing tiled workspaces.")
                    .font(.callout).foregroundStyle(.secondary)
                SettingsPicker(.defaultOrientation, selection: $defaultOrientation, help: "Controls how new tiled containers split.") {
                    Text("Automatic").tag(DefaultContainerOrientation.auto)
                    Text("Horizontal").tag(DefaultContainerOrientation.horizontal)
                    Text("Vertical").tag(DefaultContainerOrientation.vertical)
                } onChange: { persistRootString("default-root-container-orientation", defaultOrientation.rawValue) }
                .pickerStyle(.segmented)

            }
            SettingsSection("Lone windows and fullscreen") {
                SettingsStepper(.fullscreenWidth, value: Binding(
                    get: { Int((fullscreenWidth * 100).rounded()) },
                    set: { fullscreenWidth = Double($0) / 100 }), range: 10...100,
                    help: "Share of the available width for a lone tiled window or WinMuxX fullscreen. Display and workspace overrides take priority.", unit: "%") {
                    persistConfig(section: nil, key: "fullscreen-width", value: String(fullscreenWidth))
                }
                Text("Applies after sidebar and outer gaps on any display. Fullscreen stays centered; alignment below applies to lone tiled windows.")
                    .font(.callout).foregroundStyle(.secondary)
                if let width = focus.workspace.windowWidthSettings.fullscreenWidth {
                    Text("Current workspace: \(Int((width * 100).rounded()))% · \(focus.workspace.workspaceMonitor.name)")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Current workspace uses the legacy aspect-ratio setting. Saving a width switches to percentage sizing.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("Resizing width keeps the window tiled. Changing height makes it floating and preserves the gesture’s size and position.")
                    .font(.callout).foregroundStyle(.secondary)

            }
            SettingsSection("Workspace swipes") {
                SettingsToggle(.workspaceSwipes, isOn: $workspaceSwipes, help: "Three-finger horizontal swipes switch existing workspaces on the display under the pointer. Stops at either end.") {
                    persistConfig(section: "workspace-swipe", key: "enabled", value: workspaceSwipes ? "true" : "false")
                }
                Text(DockWorkspaceSwipeSource.shared.status)
                    .font(.callout).foregroundStyle(.secondary)
                Text("Needs Swipe between full-screen apps on three fingers in macOS Trackpad settings: macOS recognizes the swipe and WinMuxX switches workspaces with it; at the last workspace macOS gets the swipe. Normal two-finger scrolling stays with your apps.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            SettingsSection("Workspace overview") {
                SettingsToggle(.overviewGesture, isOn: $overviewGesture, help: "Show the current project's workspaces on each display.") {
                    persistConfig(section: "workspace-overview", key: "three-finger-up", value: overviewGesture ? "true" : "false")
                }
                Text("Use workspace-overview from a shortcut or the CLI. The swipe needs Mission Control on three fingers in macOS Trackpad settings: macOS recognizes it and it opens the overview instead; Mission Control stays on its keyboard shortcut. Minimized windows, hidden apps and native full-screen windows are excluded.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            masterSettingsSection
            SettingsSection("Hover bar") {
            }
            SettingsSection("Pointer focus") {
                SettingsToggle(.focusFollowsMouse, isOn: $focusFollowsMouse, help: "Focus the tiled window after the pointer rests over it.") {
                    persistRootBool("focus-follows-mouse", focusFollowsMouse)
                }
                Text("A delay of 0 focuses immediately. Mouse clicks and window manipulation always take priority.")
                    .font(.callout).foregroundStyle(.secondary)
                SettingsToggle(.followAppActivation, isOn: $followAppActivation,
                    help: "When another app comes to the front (Dock, Cmd-Tab, a notification), focus follows it to its workspace. A floating window on a hidden workspace comes to the current one instead.") {
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
                SettingsToggle(.tabEnabled, isOn: $tabEnabled, help: "Display browser-like tabs for stacked windows.") { persistConfig(section: "window-tabs", key: "enabled", value: tabEnabled ? "true" : "false") }
                SettingsStepper("Tab strip height", id: "window-tabs.height", value: $tabHeight, range: 36...80, help: "Height of the tab strip, and of the zone at the top of a tab group that accepts a dragged window as a new tab.") { persistConfig(section: "window-tabs", key: "height", value: "\(tabHeight)") }
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
                SettingsToggle(.shakeToToggleTiling, isOn: $enableShakeToToggleTiling, help: "Shake a window by its title bar to switch between floating and tiled.") { persistRootBool("enable-shake-to-toggle-tiling", enableShakeToToggleTiling) }
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
                Text("No tiled group exceeds its available layout area.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(fitIssues) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tiled group minimum exceeds its layout area")
                            .font(.body)
                        Text("\(workspaceDisplayName(runtime.workspaces.workspaceById[issue.workspaceId]?.name ?? issue.workspaceId.rawValue)) · minimum \(minimumSizeDescription(issue.minimumSize)) · available \(minimumSizeDescription(issue.availableSize))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func refreshFitDiagnostics() {
        fitIssues = workspaceFitIssues(in: orderedWorkspacesForPresentation())
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

private struct SettingsLayoutPreviews: View {
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            preview("Dwindle", description: "Each new window splits the focused area.", master: false)
            preview("Master", description: "One main window with the others beside it.", master: true)
        }
    }

    private func tile(_ number: Int) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.accentColor.opacity(0.15))
            .overlay(Text("\(number)").font(.caption).foregroundStyle(.primary))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor.opacity(0.5)))
    }

    private func preview(_ title: String, description: String, master: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    tile(1).frame(width: geometry.size.width * (master ? 0.6 : 0.5) - 2)
                    VStack(spacing: 4) {
                        tile(2)
                        if master { tile(3) }
                        else { HStack(spacing: 4) { tile(3); tile(4) } }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 76)
            .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(description).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
