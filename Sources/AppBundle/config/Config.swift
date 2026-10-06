import AppKit
import Common
import HotKey
import OrderedCollections

func getDefaultConfigUrlFromProject() -> URL {
    var url = URL(filePath: #filePath)
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: ".git").path) {
        url.deleteLastPathComponent()
    }
    let projectRoot: URL = url
    return projectRoot.appending(component: "resources/default-config.toml")
}

var defaultConfigUrl: URL {
    if isUnitTest {
        return getDefaultConfigUrlFromProject()
    } else {
        return Bundle.main.url(forResource: "default-config", withExtension: "toml")
            // Useful for debug builds that are not app bundles
            ?? getDefaultConfigUrlFromProject()
    }
}
@MainActor let defaultConfig: Config = {
    let parsedConfig = parseConfig(Result { try String(contentsOf: defaultConfigUrl, encoding: .utf8) }.getOrDie())
    if !parsedConfig.errors.isEmpty {
        die("Can't parse default config: \(parsedConfig.errors)")
    }
    return parsedConfig.config
}()
@MainActor var config: Config = defaultConfig // todo move to Ctx?
@MainActor var configUrl: URL = defaultConfigUrl

struct Config: ConvenienceCopyable {
    var configVersion: Int = 1
    var afterLoginCommand: [any Command] = []
    var afterStartupCommand: [any Command] = []
    var _indentForNestedContainersWithTheSameOrientation: Void = ()
    var enableNormalizationFlattenContainers: Bool = true
    var _nonEmptyWorkspacesRootContainersLayoutOnStartup: Void = ()
    var defaultRootContainerLayout: Layout = .dwindle
    var defaultRootContainerOrientation: DefaultContainerOrientation = .auto
    var startAtLogin: Bool = false
    var autoReloadConfig: Bool = false
    var automaticallyUnhideMacosHiddenApps: Bool = false
    var automaticallyTileNewWindows: Bool = true
    var enableShakeToToggleTiling: Bool = true
    var focusFollowsMouse: Bool = false
    var focusFollowsMouseDwell: Int = 250
    var shortcutsPreset: ShortcutsPreset = .none
    var tabGroupPadding: Int = 30
    var enableNormalizationOppositeOrientationForNestedContainers: Bool = true
    var persistentWorkspaces: OrderedSet<String> = []
    var execOnWorkspaceChange: [String] = [] // todo deprecate
    var keyMapping = KeyMapping()
    var execConfig: ExecConfig = ExecConfig()

    var onFocusChanged: [any Command] = []
    // var onFocusedWorkspaceChanged: [any Command] = []
    var onFocusedMonitorChanged: [any Command] = []

    var autoAddNewWindowsToTabGroup: Bool = false
    var gaps: Gaps = .zero
    var workspaceSidebar = WorkspaceSidebarConfig()
    var windowTabs = WindowTabsConfig()
    var windowBorders = WindowBordersConfig()
    var animations = AnimationsConfig()
    var workspaceToMonitorForceAssignment: [String: [MonitorDescription]] = [:]
    var modes: [String: Mode] = [:]
    var onWindowDetected: [WindowDetectedCallback] = []
    var onModeChanged: [any Command] = []
}

enum DefaultContainerOrientation: String {
    case horizontal, vertical, auto
}

enum ShortcutsPreset: String, Equatable, Sendable {
    case none
    case rectangle
}

enum WorkspaceSidebarPosition: String, CaseIterable, Sendable { case left, right }
enum WorkspaceSidebarHeightMode: String, CaseIterable, Sendable { case standard, centered, full }

struct WorkspaceSidebarConfig: ConvenienceCopyable, Equatable, Sendable {
    var enabled: Bool = false
    var enableFocus: Bool = false
    var autoHide: Bool = false
    var alwaysExpanded: Bool = false
    var collapsedWidth: Int = 44
    var width: Int = 240
    var monitor: [MonitorDescription] = []
    var showStatusPills: Bool = true
    var showClock: Bool = true
    var showSeconds: Bool = true
    var showDate: Bool = true
    var showWeekday: Bool = true
    var appearance: WorkspaceSidebarAppearance = .system
    var background: WorkspaceSidebarBackground = .sidebar
    var menuBarBackground = false
    var frostedTint: WorkspaceSidebarFrostedTint = .automatic
    // Legacy appearance remains parseable; the style is the single runtime choice.
    var effectiveAppearance: WorkspaceSidebarAppearance { chromeStyle == .solid ? .custom : .system }
    var chromeStyle: ChromeStyle = .liquidGlass
    var solidChromeColor: ChromeSolidColor = .midnight
    var solidChromeCustomColor: String = "#191B20"
    var position: WorkspaceSidebarPosition = .left
    var heightMode: WorkspaceSidebarHeightMode? = nil
    var menuBarReserveHeight: Int = 28
    var projectDeletionAction: WorkspaceProjectDeletionAction = .closeWindows
    var workspaceLabels: [String: String] = [:]
    var projectLabels: [String: String] = [:]
    var projectColors: [String: String] = [:]
}

enum WorkspaceSidebarAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case custom

    var id: String { rawValue }
}

enum WorkspaceSidebarBackground: String, CaseIterable, Identifiable, Sendable {
    case sidebar
    case menuBar = "menu-bar"
    case transparent

    var id: String { rawValue }
}

enum WorkspaceSidebarFrostedTint: String, CaseIterable, Identifiable, Sendable {
    case automatic, white, black, cyan, pink, indigo, purple, ice, aurora

    var id: String { rawValue }
    var title: String {
        switch self {
            case .automatic: "Automatic"
            case .white: "White"
            case .black: "Black"
            case .cyan: "Cyan"
            case .pink: "Pink"
            case .indigo: "Indigo"
            case .purple: "Purple"
            case .ice: "Ice — cyan / pink"
            case .aurora: "Aurora — indigo / purple"
        }
    }
}

enum ChromeStyle: String, CaseIterable, Identifiable, Sendable {
    case liquidGlass = "liquid-glass"
    case solid

    var id: String { rawValue }
}

enum ChromeSolidColor: String, CaseIterable, Identifiable, Sendable {
    case purple, pink, red, orange, yellow
    case black
    case onyx
    case charcoal
    case midnight
    case graphite
    case slate
    case steel
    case silver
    case fog
    case blue
    case indigo
    case lavender
    case ocean
    case teal
    case mint
    case green
    case sage
    case gold
    case cocoa
    case rose
    case mauve
    case plum
    case violet
    case apricot
    case custom

    // sRGB samples from the supplied System Settings accent-color reference.
    static let settingsPresets: [ChromeSolidColor] = [.custom, .blue, .purple, .pink, .red, .orange, .yellow, .green, .graphite]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .black: "Black"
        case .onyx: "Onyx"
        case .charcoal: "Charcoal"
        case .midnight: "Midnight"
        case .graphite: "Graphite"
        case .slate: "Slate"
        case .steel: "Steel"
        case .silver: "Silver"
        case .fog: "Fog"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .lavender: "Lavender"
        case .ocean: "Ocean"
        case .teal: "Teal"
        case .mint: "Mint"
        case .green: "Green"
        case .sage: "Sage"
        case .gold: "Gold"
        case .cocoa: "Cocoa"
        case .rose: "Rose"
        case .mauve: "Mauve"
        case .plum: "Plum"
        case .violet: "Violet"
        case .apricot: "Apricot"
        case .custom: "Custom"
        }
    }

    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .purple: (157.0 / 255, 90.0 / 255, 163.0 / 255)
        case .pink: (235.0 / 255, 118.0 / 255, 172.0 / 255)
        case .red: (217.0 / 255, 94.0 / 255, 86.0 / 255)
        case .orange: (238.0 / 255, 154.0 / 255, 74.0 / 255)
        case .yellow: (249.0 / 255, 209.0 / 255, 96.0 / 255)
        case .black: (0.015, 0.016, 0.020)
        case .onyx: (0.045, 0.048, 0.055)
        case .charcoal: (0.10, 0.105, 0.12)
        case .midnight: (0.07, 0.09, 0.15)
        case .graphite: (168.0 / 255, 169.0 / 255, 169.0 / 255)
        case .slate: (0.19, 0.25, 0.33)
        case .steel: (0.32, 0.34, 0.38)
        case .silver: (0.48, 0.50, 0.54)
        case .fog: (0.67, 0.68, 0.71)
        case .blue: (66.0 / 255, 143.0 / 255, 249.0 / 255)
        case .indigo: (0.18, 0.20, 0.46)
        case .lavender: (0.22, 0.17, 0.34)
        case .ocean: (0.07, 0.23, 0.34)
        case .teal: (0.04, 0.34, 0.33)
        case .mint: (0.08, 0.28, 0.23)
        case .green: (137.0 / 255, 194.0 / 255, 105.0 / 255)
        case .sage: (0.26, 0.33, 0.25)
        case .gold: (0.38, 0.31, 0.02)
        case .cocoa: (0.30, 0.21, 0.17)
        case .rose: (0.34, 0.14, 0.24)
        case .mauve: (0.30, 0.20, 0.28)
        case .plum: (0.33, 0.15, 0.35)
        case .violet: (0.25, 0.18, 0.45)
        case .apricot: (0.35, 0.21, 0.11)
        case .custom: (0.10, 0.11, 0.13)
        }
    }
}

enum WorkspaceProjectDeletionAction: String, CaseIterable, Identifiable, Sendable {
    case closeWindows = "close-windows"
    case moveWindowsToFallback = "move-windows-to-fallback"

    var id: String { rawValue }
}

struct WindowTabsConfig: ConvenienceCopyable, Equatable, Sendable {
    var enabled: Bool = true
    var height: Int = 36
}

extension WorkspaceSidebarConfig {
    @MainActor
    func resolvedMonitor(sortedMonitors: [Monitor]) -> Monitor? {
        monitor.lazy
            .compactMap { $0.resolveMonitor(sortedMonitors: sortedMonitors) }
            .first
    }

    @MainActor
    func resolvedMonitors(sortedMonitors: [Monitor]) -> [Monitor] {
        guard !monitor.isEmpty else { return sortedMonitors }
        if monitor == [.main] {
            return sortedMonitors
        }
        var seenTopLeftCorners = Set<CGPoint>()
        return monitor
            .compactMap { $0.resolveMonitor(sortedMonitors: sortedMonitors) }
            .filter { seenTopLeftCorners.insert($0.rect.topLeftCorner).inserted }
    }
}
