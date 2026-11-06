import SwiftUI

struct SettingsSearchDestination: Equatable {
    let id: String
    let request = UUID()
}

/// Emitted by the requested field during SwiftUI's layout preference pass.
struct SettingsSearchReadyKey: PreferenceKey {
    static let defaultValue: SettingsSearchDestination? = nil
    static func reduce(value: inout SettingsSearchDestination?, nextValue: () -> SettingsSearchDestination?) {
        if let next = nextValue() { value = next }
    }
}

private struct SettingsSearchTargetKey: EnvironmentKey {
    static let defaultValue: SettingsSearchDestination? = nil
}
extension EnvironmentValues {
    var settingsSearchTarget: SettingsSearchDestination? {
        get { self[SettingsSearchTargetKey.self] }
        set { self[SettingsSearchTargetKey.self] = newValue }
    }
}

struct SettingsControlSearchResult: Identifiable {
    let id: String
    let title: String
    let page: SettingsSidebarItem
}

func settingsControlSearchResults(_ query: String) -> [SettingsControlSearchResult] {
    let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !terms.isEmpty else { return [] }
    return settingsControlSearchIndex.filter { result in
        let text = "\(result.title) \(result.id) \(result.page.label)"
        return terms.allSatisfy { text.localizedStandardContains($0) }
    }
}

// Searchable controls that are always present on their destination page.
private let settingsControlSearchIndex: [SettingsControlSearchResult] = [
    .init(id: "start-workspaces-on-main-monitor", title: "Start workspaces on main display", page: .general),
    .init(id: "start-at-login", title: "Start at login", page: .general),
    .init(id: "auto-reload-config", title: "Reload config when it changes", page: .general),
    .init(id: "appearance", title: "Theme", page: .appearance),
    .init(id: "workspace-sidebar.chrome-style", title: "Shared appearance", page: .appearance),
    .init(id: "menu-bar.indicator", title: "Menu bar indicator", page: .appearance),
    .init(id: "animations.enabled", title: "Glide windows", page: .appearance),
    .init(id: "animations.duration-ms", title: "Glide duration", page: .appearance),
    .init(id: "borders.enabled", title: "Show window borders", page: .appearance),
    .init(id: "borders.order", title: "Border placement", page: .appearance),
    .init(id: "dimming.inactive-windows", title: "Dim inactive windows", page: .appearance),
    .init(id: "workspace-sidebar.enabled", title: "Show sidebar", page: .sidebar),
    .init(id: "workspace-sidebar.display-mode", title: "Sidebar display", page: .sidebar),
    .init(id: "workspace-sidebar.position", title: "Sidebar position", page: .sidebar),
    .init(id: "workspace-sidebar.show-clock", title: "Show clock", page: .sidebar),
    .init(id: "workspace-sidebar.show-seconds", title: "Show seconds", page: .sidebar),
    .init(id: "workspace-sidebar.show-date", title: "Show date", page: .sidebar),
    .init(id: "workspace-sidebar.show-weekday", title: "Show weekday", page: .sidebar),
    .init(id: "automatically-tile-new-windows", title: "Tile new windows automatically", page: .windows),
    .init(id: "auto-add-new-windows-to-tab-group", title: "Add new windows to the current tab group", page: .windows),
    .init(id: "automatically-unhide-macos-hidden-apps", title: "Unhide macOS-hidden apps", page: .windows),
    .init(id: "default-root-container-layout", title: "Root layout", page: .windows),
    .init(id: "default-root-container-orientation", title: "Root orientation", page: .windows),
    .init(id: "fullscreen-width", title: "Width", page: .windows),
    .init(id: "workspace-swipe.enabled", title: "Enable workspace swipes", page: .windows),
    .init(id: "workspace-overview.three-finger-up", title: "Three-finger swipe up", page: .windows),
    .init(id: "focus-follows-mouse", title: "Focus windows under the pointer", page: .windows),
    .init(id: "follow-app-activation.enabled", title: "Follow app activation", page: .windows),
    .init(id: "window-tabs.enabled", title: "Show tab strips", page: .windows),
    .init(id: "enable-shake-to-toggle-tiling", title: "Shake to toggle tiling", page: .windows),
]
