import Foundation
import Common

struct ConfigurationReferenceSection: Identifiable {
    let id: String
    let title: String
    let description: String
    var defaults: String? = nil
    var example: String? = nil
    var pane: SettingsSidebarItem? = nil
}

@MainActor
var configurationReferenceSections: [ConfigurationReferenceSection] {
    let defaults = defaultConfig
    return [
        .init(id: "general", title: "General", description: "start-at-login launches WinMuxX at login. auto-reload-config watches the configuration file for changes.", defaults: "start-at-login = \(defaults.startAtLogin), auto-reload-config = \(defaults.autoReloadConfig)", pane: .general),
        .init(id: "workspaces", title: "Workspaces", description: "persistent-workspaces lists stable slots in sidebar order; they remain available when empty. Numeric entries keep their numbers, named entries keep their names, and custom sidebar labels override either. minimum-workspace-count adds automatic slots as needed, using unreserved numbers. Active displays and projects still retain their required workspaces. shortcuts-preset selects the built-in shortcut preset.", defaults: "persistent-workspaces = [], minimum-workspace-count = \(defaults.effectiveMinimumWorkspaceCount), shortcuts-preset = '\(defaults.shortcutsPreset.rawValue)'", example: "persistent-workspaces = ['1', '3', 'Code']\nminimum-workspace-count = 5", pane: .workspaces),
        .init(id: "windows", title: "Windows", description: "Controls new-window tiling, tab groups, pointer focus, shake gestures, default layout, normalization and single-window size/alignment. single-window-aspect-ratio also accepts per-display rules.", defaults: "default-root-container-layout = '\(defaults.defaultRootContainerLayout.rawValue)', default-root-container-orientation = '\(defaults.defaultRootContainerOrientation.rawValue)', focus-follows-mouse = \(defaults.focusFollowsMouse), focus-follows-mouse-dwell = \(defaults.focusFollowsMouseDwell) ms", pane: .windows),
        .init(id: "sidebar", title: "Sidebar", description: "[workspace-sidebar] controls visibility, width, position, height, display filtering and the clock. The monitor option is advanced; an empty list shows the sidebar on every display.", defaults: "enabled = \(defaults.workspaceSidebar.enabled), width = \(defaults.workspaceSidebar.width), collapsed-width = \(defaults.workspaceSidebar.collapsedWidth)", pane: .sidebar),
        .init(id: "appearance", title: "Appearance", description: "[borders] controls width, colors, stacking and excluded apps. [animations] controls window motion. [gaps] controls spacing. workspace-sidebar.chrome-style selects the shared glass or solid appearance.", defaults: "borders.width = \(defaults.windowBorders.width), animations.enabled = \(defaults.animations.enabled), animations.duration-ms = \(defaults.animations.durationMs)", pane: .appearance),
        .init(id: "sidebar-advanced", title: "Advanced sidebar options", description: "workspace-sidebar.monitor restricts which displays show a sidebar; an empty list means all displays. menu-bar-reserve-height protects the menu bar reveal area in points. Legacy appearance, background and frosted-tint are described below.", defaults: "monitor = [], menu-bar-reserve-height = \(defaults.workspaceSidebar.menuBarReserveHeight)", example: """
        [workspace-sidebar]
        monitor = []
        menu-bar-reserve-height = \(defaults.workspaceSidebar.menuBarReserveHeight)
        """),
        .init(id: "workspace-swipe", title: "[workspace-swipe]", description: "Experimental raw-touch recognition: exactly three fingers, horizontal only. enabled opts in; reverse-direction swaps left/right. Finger-tracked previews navigate existing workspaces on the pointer display and stop at boundaries. Release past halfway to commit, otherwise cancel. animation-duration-ms controls settling (220 ms by default; zero disables visuals). Native macOS gestures should use another finger count.", defaults: "enabled = false, reverse-direction = false", example: "[workspace-swipe]\nenabled = false\nreverse-direction = false", pane: .windows),
        .init(id: "modifier-sides", title: "Modifier sides", description: "[modifiers] accepts alt, cmd, ctrl and shift with both, left or right. Applies to shortcut chords; modifier taps retain their explicit sides. The unused side passes through for normal typing.", defaults: "All modifiers use both sides.", example: "[modifiers]\nalt = 'left'"),
        .init(id: "padding", title: "tab-group-padding", description: "Root-level spacing for tab-group containers, in points. This is separate from window-tabs.height, which sets the tab strip height.", defaults: "\(defaults.tabGroupPadding)", example: "tab-group-padding = \(defaults.tabGroupPadding)"),
        .init(id: "rules", title: "[[on-window-detected]]", description: "Match exact app-id, app-id-regex, workspace, app-name-regex-substring, window-title-regex-substring or during-winmux-startup. Regex matches are case-insensitive; every supplied condition must match. Rules run in file order; check-further-callbacks = true continues after a match. Restored windows keep their saved placement instead of replaying these rules.", defaults: "No rules; check-further-callbacks = false.", example: """
        [[on-window-detected]]
        if.app-id = 'com.apple.finder'
        check-further-callbacks = false
        run = 'layout floating'
        """),
        .init(id: "assignments", title: "[workspace-to-monitor-force-assignment]", description: "Assign internal workspace names to displays. Display selectors include uuid:<UUID>, hardware:<vendor>:<model>:<serial>, main, secondary, display numbers and name patterns. Saved assignments constrain placement; ordinary navigation keeps workspace ownership. Configure them in Displays.", defaults: "No forced assignments.", example: """
        [workspace-to-monitor-force-assignment]
        '1' = 'main'
        '2' = 'secondary'
        """),
        .init(id: "workspace-layouts", title: "Per-display workspace layouts", description: "[workspace.<internal-name>] sets layout and orientation defaults. Nested display.<selector> tables override them on matching displays. Omitted keys inherit workspace/global defaults. Explicit selectors win over name regexes; longer regexes win, then lexical order. Manual commands survive refreshes until resolved settings change. These settings never relocate workspaces.", example: """
        [workspace.1]
        layout = 'dwindle'
        [workspace.1.display.'Built-in']
        layout = 'accordion'
        orientation = 'vertical'
        """),
        .init(id: "gaps", title: "Per-display gaps", description: "Each [gaps] value accepts a constant or an ordered list of display overrides followed by a fallback. Values are measured in points. Replace the existing key inside [gaps].", defaults: "See Appearance for the default inner and outer spacing.", example: """
        [gaps]
        inner.horizontal = [{ monitor.main = 4 }, 8]
        outer.left = [{ monitor.secondary = 12 }, 8]
        """, pane: .appearance),
        .init(id: "keyboard", title: "[key-mapping] and shortcut modes", description: "Keyboard presets: qwerty, dvorak or colemak. [key-mapping.key-notation-to-key-code] adds custom key names. [mode.<name>.binding] defines command shortcuts and sequences; hyper means alt-ctrl-cmd-shift and meh means alt-ctrl-shift; [mode.<name>.binding-tap] defines tap-only shortcuts.", defaults: "qwerty; no custom key mappings.", example: """
        [key-mapping]
        preset = 'qwerty'

        [key-mapping.key-notation-to-key-code]
        mykey = 'a'

        [mode.main.binding]
        alt-mykey = 'focus left'
        """, pane: .shortcuts),
        .init(id: "next-window", title: "Layout for the next detected window", description: "A command, not a persistent setting. Schedule floating or tiling once; another request replaces it. Existing windows, popups, restored windows and native minimized/fullscreen/hidden windows do not consume it. The explicit layout overrides automatic layout rules and is forgotten when WinMuxX quits.", defaults: "No pending request.", example: """
        [mode.main.binding]
        alt-shift-n = 'layout floating --for-next-detected-window'
        """, pane: .shortcuts),
        .init(id: "automation", title: "Automation callbacks", description: "after-startup-command runs after startup. on-focus-changed, on-focused-monitor-changed and on-mode-changed run after the corresponding focus or mode changes. on-display-changed runs after a settled display topology change; shell commands receive WINMUX_DISPLAYS and WINMUX_PREV_DISPLAYS. They accept a WinMuxX command or an array of commands. exec-on-workspace-change instead accepts an executable followed by its arguments.", defaults: "on-focused-monitor-changed = \(tomlStringArray(defaults.onFocusedMonitorChanged.map { $0.args.description }.joined(separator: "\n"))); other callbacks are empty.", example: """
        on-display-changed = []
        on-focus-changed = []
        on-focused-monitor-changed = ['move-mouse monitor-lazy-center']
        on-mode-changed = []
        after-startup-command = []
        exec-on-workspace-change = []
        """, pane: .automation),
        .init(id: "exec", title: "[exec] and [exec.env-vars]", description: "Commands inherit the app’s environment. When [exec] is omitted, PATH receives /opt/homebrew/bin:/opt/homebrew/sbin before the inherited PATH. Defining [exec] replaces that implicit configuration; add PATH explicitly to retain the prefix. Variables support ${NAME} interpolation. exec-and-forget prepends this app’s bundled CLI directory to PATH so hooks can call winmuxx after a Finder launch.", defaults: "inherit-env-vars = true; Homebrew PATH prefix when [exec] is absent.", example: """
        [exec]
        inherit-env-vars = true

        [exec.env-vars]
        PATH = '/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}'
        """),
        .init(id: "labels", title: "Sidebar labels and colors", description: "Use internal workspace names as workspace-label keys and project IDs as project keys. Labels change the visible name, not the identity or assignments. Colors accept #RRGGBB values.", defaults: "No workspace labels. The default project label and color come from the default configuration.", example: """
        [workspace-sidebar.workspace-labels]
        '1' = 'Terminal'

        [workspace-sidebar.project-labels]
        default = 'Default'

        [workspace-sidebar.project-colors]
        default = '#C4B5FD'
        """),
        .init(id: "legacy", title: "Legacy options", description: "after-login-command is deprecated and only accepts an empty array; use start-at-login and after-startup-command. Sidebar appearance, background and frosted-tint remain accepted legacy keys; chrome-style determines the effective appearance. use-liquid-glass is an alias used only when chrome-style is absent. non-empty-workspaces-root-containers-layout-on-startup and indent-for-nested-containers-with-the-same-orientation are deprecated; remove them.", defaults: "Use the current Settings controls for new configurations.")
    ]
}
