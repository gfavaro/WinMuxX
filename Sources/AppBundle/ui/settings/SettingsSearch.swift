import SwiftUI

struct SettingsSearchDestination: Equatable {
    let id: String
    let request = UUID()
}

/// One selection for every sidebar row. Control results used to be plain buttons beside the
/// page links, so arrow keys and Tab skipped them and Return in the search field did nothing.
enum SettingsSidebarSelection: Hashable {
    case page(SettingsSidebarItem)
    case control(SettingsControl)
}

/// What Return in the search field opens: the first control result, otherwise the first page.
func settingsSearchSubmitSelection(controls: [SettingsControl], pages: [SettingsSidebarItem]) -> SettingsSidebarSelection? {
    if let control = controls.first { return .control(control) }
    return pages.first.map { .page($0) }
}

/// Emitted by the requested field during SwiftUI's layout preference pass.
struct SettingsSearchReadyKey: PreferenceKey {
    static let defaultValue: SettingsSearchDestination? = nil
    static func reduce(value: inout SettingsSearchDestination?, nextValue: () -> SettingsSearchDestination?) {
        if let next = nextValue() { value = next }
    }
}

extension EnvironmentValues {
    @Entry var settingsSearchTarget: SettingsSearchDestination? = nil
}

/// Shared by the page controls and their direct search results.
enum SettingsControl: String, CaseIterable, Identifiable {
    case startWorkspacesOnMain = "start-workspaces-on-main-monitor"
    case startAtLogin = "start-at-login"
    case autoReloadConfig = "auto-reload-config"
    case appearance = "appearance"
    case chromeStyle = "workspace-sidebar.chrome-style"
    case menuBarIndicator = "menu-bar.indicator"
    case glideEnabled = "animations.enabled"
    case glideDuration = "animations.duration-ms"
    case bordersEnabled = "borders.enabled"
    case borderOrder = "borders.order"
    case dimInactive = "dimming.inactive-windows"
    case sidebarEnabled = "workspace-sidebar.enabled"
    case sidebarDisplayMode = "workspace-sidebar.display-mode"
    case sidebarPosition = "workspace-sidebar.position"
    case showClock = "workspace-sidebar.show-clock"
    case showSeconds = "workspace-sidebar.show-seconds"
    case showDate = "workspace-sidebar.show-date"
    case showWeekday = "workspace-sidebar.show-weekday"
    case automaticallyTileNewWindows = "automatically-tile-new-windows"
    case autoAddNewWindowsToTabGroup = "auto-add-new-windows-to-tab-group"
    case automaticallyUnhideApps = "automatically-unhide-macos-hidden-apps"
    case defaultLayout = "default-root-container-layout"
    case defaultOrientation = "default-root-container-orientation"
    case fullscreenWidth = "fullscreen-width"
    case workspaceSwipes = "workspace-swipe.enabled"
    case focusFollowsMouse = "focus-follows-mouse"
    case followAppActivation = "follow-app-activation.enabled"
    case tabEnabled = "window-tabs.enabled"
    case shakeToToggleTiling = "enable-shake-to-toggle-tiling"
    case sidebarMenuBarBackground = "workspace-sidebar.menu-bar-background"
    case sidebarFocusFilter = "workspace-sidebar.enable-focus"
    case sidebarWidth = "workspace-sidebar.width"
    case sidebarCollapsedWidth = "workspace-sidebar.collapsed-width"
    case sidebarHeightMode = "workspace-sidebar.height-mode"
    case followAppActivationExcluded = "follow-app-activation.exclude-apps"
    case tabHeight = "window-tabs.height"
    case doubleSidedWindows = "window-tabs.double-sided-windows"
    case scrollingColumnWidth = "scrolling.column-width"
    case scrollingWidthPresets = "scrolling.width-presets"
    case scrollingEdgePreview = "scrolling.edge-preview"
    case scrollingCenter = "scrolling.center-focused-column"
    case scrollingMinimap = "scrolling.minimap-enabled"
    case masterSize = "master.size"
    case masterSide = "master.side"
    case menuBarIconAppearance = "menu-bar.icon-appearance"
    case inactiveBorderColor = "borders.inactive-color"
    case accentColor = "accent-color"
    case gapInnerHorizontal = "gaps.inner.horizontal"
    case gapInnerVertical = "gaps.inner.vertical"
    case gapOuterLeft = "gaps.outer.left"
    case gapOuterRight = "gaps.outer.right"
    case gapOuterTop = "gaps.outer.top"
    case gapOuterBottom = "gaps.outer.bottom"

    var id: String { rawValue }

    var title: String {
        switch self {
            case .startWorkspacesOnMain: "Start workspaces on main display"
            case .startAtLogin: "Start at login"
            case .autoReloadConfig: "Reload config when it changes"
            case .appearance: "Theme"
            case .chromeStyle: "Shared appearance"
            case .menuBarIndicator: "Menu bar indicator"
            case .glideEnabled: "Glide windows"
            case .glideDuration: "Glide duration"
            case .bordersEnabled: "Show window borders"
            case .borderOrder: "Border placement"
            case .dimInactive: "Dim inactive windows"
            case .sidebarEnabled: "Show sidebar"
            case .sidebarDisplayMode: "Sidebar display"
            case .sidebarPosition: "Sidebar position"
            case .showClock: "Show clock"
            case .showSeconds: "Show seconds"
            case .showDate: "Show date"
            case .showWeekday: "Show weekday"
            case .automaticallyTileNewWindows: "Tile new windows automatically"
            case .autoAddNewWindowsToTabGroup: "Add new windows to the current tab group"
            case .automaticallyUnhideApps: "Unhide macOS-hidden apps"
            case .defaultLayout: "Root layout"
            case .defaultOrientation: "Root orientation"
            case .fullscreenWidth: "Width"
            case .workspaceSwipes: "Enable workspace swipes"
            case .focusFollowsMouse: "Focus windows under the pointer"
            case .followAppActivation: "Follow app activation"
            case .tabEnabled: "Show tab strips"
            case .shakeToToggleTiling: "Shake to toggle tiling"
            case .sidebarMenuBarBackground: "Show background"
            case .sidebarFocusFilter: "Show focused-display filter"
            case .sidebarWidth: "Expanded sidebar size"
            case .sidebarCollapsedWidth: "Collapsed sidebar size"
            case .sidebarHeightMode: "Sidebar height"
            case .followAppActivationExcluded: "Apps not followed"
            case .tabHeight: "Tab strip height"
            case .doubleSidedWindows: "Double-sided windows"
            case .scrollingColumnWidth: "New column width"
            case .scrollingWidthPresets: "Width presets"
            case .scrollingEdgePreview: "Edge preview"
            case .scrollingCenter: "Scroll to focus"
            case .scrollingMinimap: "Show the strip map"
            case .masterSize: "Main window size"
            case .masterSide: "Main window side"
            case .menuBarIconAppearance: "Icon appearance"
            case .inactiveBorderColor: "Other window color"
            case .accentColor: "Accent color"
            case .gapInnerHorizontal: "Inner horizontal gap"
            case .gapInnerVertical: "Inner vertical gap"
            case .gapOuterLeft: "Outer left gap"
            case .gapOuterRight: "Outer right gap"
            case .gapOuterTop: "Outer top gap"
            case .gapOuterBottom: "Outer bottom gap"
        }
    }

    var page: SettingsSidebarItem {
        switch self {
            case .startWorkspacesOnMain, .startAtLogin, .autoReloadConfig: .general
            case .appearance, .chromeStyle, .menuBarIndicator, .glideEnabled, .glideDuration, .bordersEnabled, .borderOrder, .dimInactive: .appearance
            case .sidebarEnabled, .sidebarDisplayMode, .sidebarPosition, .showClock, .showSeconds, .showDate, .showWeekday: .sidebar
            case .automaticallyTileNewWindows, .autoAddNewWindowsToTabGroup, .automaticallyUnhideApps, .defaultLayout, .defaultOrientation, .fullscreenWidth, .workspaceSwipes, .focusFollowsMouse, .followAppActivation, .tabEnabled, .shakeToToggleTiling: .windows
            case .sidebarMenuBarBackground, .sidebarFocusFilter, .sidebarWidth, .sidebarCollapsedWidth, .sidebarHeightMode: .sidebar
            case .followAppActivationExcluded, .tabHeight, .doubleSidedWindows, .scrollingColumnWidth, .scrollingWidthPresets, .scrollingEdgePreview, .scrollingCenter, .scrollingMinimap, .masterSize, .masterSide: .windows
            case .menuBarIconAppearance, .inactiveBorderColor, .accentColor, .gapInnerHorizontal, .gapInnerVertical, .gapOuterLeft, .gapOuterRight, .gapOuterTop, .gapOuterBottom: .appearance
        }
    }
}

func settingsControlSearchResults(_ query: String) -> [SettingsControl] {
    let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !terms.isEmpty else { return [] }
    return SettingsControl.allCases.filter { result in
        let text = "\(result.title) \(result.id) \(result.page.label)"
        return terms.allSatisfy { text.localizedStandardContains($0) }
    }
}


/// Build the reference inventory once for all destinations in this query.
@MainActor
func settingsPageSearchResults(_ query: String, pages: [SettingsSidebarItem]) -> [SettingsSidebarItem] {
    let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !terms.isEmpty else { return pages }
    let references = Dictionary(grouping: configurationReferenceSections) { $0.pane ?? .configuration }
    return pages.filter { page in
        let referenceText = (references[page] ?? []).map {
            "\($0.title) \($0.description) \($0.defaults ?? "") \($0.example ?? "")"
        }
        let text = ([page.label] + referenceText + page.searchAliases).joined(separator: " ")
        return terms.allSatisfy { text.localizedStandardContains($0) }
    }
}
