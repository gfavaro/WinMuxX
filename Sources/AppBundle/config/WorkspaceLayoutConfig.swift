import AppKit
import Common
import TOMLKit

struct WorkspaceLayoutSettings: ConvenienceCopyable, Equatable {
    var layout: WorkspaceLayoutName?
    var orientation: DefaultContainerOrientation?
    var fullscreenWidth: Double?
    var singleWindowAlignment: SingleWindowAlignment?

    func overlaying(_ base: Self) -> Self {
        Self(layout: layout ?? base.layout, orientation: orientation ?? base.orientation,
             fullscreenWidth: fullscreenWidth ?? base.fullscreenWidth,
             singleWindowAlignment: singleWindowAlignment ?? base.singleWindowAlignment)
    }
}

struct WorkspaceLayoutConfig: ConvenienceCopyable {
    var defaults = WorkspaceLayoutSettings()
    var displays: [WorkspaceDisplayLayout] = []

    func settings(on monitor: Monitor) -> WorkspaceLayoutSettings {
        let matching = displays.first { rule in
            switch rule.selector {
                case .pattern(_, let regex): monitor.name.contains(regex.val)
                default: rule.selector.resolveMonitor(sortedMonitors: sortedMonitors)?.rect.topLeftCorner == monitor.rect.topLeftCorner
            }
        }
        return matching?.settings.overlaying(defaults) ?? defaults
    }
}

struct WorkspaceDisplayLayout {
    let selector: MonitorDescription
    let settings: WorkspaceLayoutSettings
}

private let workspaceLayoutParsers: [String: any ParserProtocol<WorkspaceLayoutSettings>] = [
    "layout": Parser(\.layout, parseOptionalWorkspaceLayout),
    "orientation": Parser(\.orientation, parseOptionalWorkspaceOrientation),
    "fullscreen-width": Parser(\.fullscreenWidth, parseFullscreenWidth),
    "single-window-alignment": Parser(\.singleWindowAlignment, parseOptionalSingleWindowAlignment),
]

private let workspaceParsers: [String: any ParserProtocol<WorkspaceLayoutConfig>] = [
    "layout": Parser(\.defaults.layout, parseOptionalWorkspaceLayout),
    "orientation": Parser(\.defaults.orientation, parseOptionalWorkspaceOrientation),
    "fullscreen-width": Parser(\.defaults.fullscreenWidth, parseFullscreenWidth),
    "single-window-alignment": Parser(\.defaults.singleWindowAlignment, parseOptionalSingleWindowAlignment),
    "display": Parser(\.displays, parseWorkspaceDisplayLayouts),
]

private func parseOptionalWorkspaceLayout(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace) -> ParsedToml<WorkspaceLayoutName?> {
    parseString(raw, trace).flatMap {
        WorkspaceLayoutName(rawValue: $0).map { Optional($0) }
            .orFailure(.semantic(trace, "Expected dwindle, master or scrolling"))
    }
}

private func parseOptionalWorkspaceOrientation(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace) -> ParsedToml<DefaultContainerOrientation?> {
    parseString(raw, trace).flatMap {
        DefaultContainerOrientation(rawValue: $0).map { Optional($0) }
            .orFailure(.semantic(trace, "Expected horizontal, vertical or auto"))
    }
}

private func parseWorkspaceDisplayLayouts(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace,
                                          _ errors: inout [TomlParseError]) -> [WorkspaceDisplayLayout] {
    guard let table = raw.table else {
        errors.append(expectedActualTypeError(expected: .table, actual: raw.type, trace))
        return []
    }
    return table.compactMap { pattern, settings in
        let path = trace + .key(pattern)
        guard let selector = parseMonitorDescription(pattern).toParsedToml(path).getOrNil(appendErrorTo: &errors) else { return nil }
        return WorkspaceDisplayLayout(selector: selector,
            settings: parseTable(settings, WorkspaceLayoutSettings(), workspaceLayoutParsers, path, &errors))
    }
}

func parseWorkspaceLayouts(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace,
                           _ errors: inout [TomlParseError]) -> [String: WorkspaceLayoutConfig] {
    guard let table = raw.table else {
        errors.append(expectedActualTypeError(expected: .table, actual: raw.type, trace))
        return [:]
    }
    var result: [String: WorkspaceLayoutConfig] = [:]
    for (name, value) in table {
        let path = trace + .key(name)
        if name.isEmpty { errors.append(.semantic(path, "Workspace name must not be empty")); continue }
        var parsed = parseTable(value, WorkspaceLayoutConfig(), workspaceParsers, path, &errors)
        var displays = parsed.displays
        // Explicit identities win; longer name patterns are more specific. Break ties
        // lexically so TOML iteration order never decides which override applies.
        displays.sort {
            func priority(_ selector: MonitorDescription) -> Int {
                if case .pattern(let pattern, _) = selector { return pattern.count }
                return Int.max
            }
            let a = priority($0.selector), b = priority($1.selector)
            return a == b ? $0.selector.selector < $1.selector.selector : a > b
        }
        parsed.displays = displays
        result[name] = parsed
    }
    return result
}

extension Workspace {
    /// Apply defaults only when resolved settings change. Manual layout commands
    /// survive ordinary refreshes; visiting another workspace never relocates this one.
    @MainActor
    func applyConfiguredLayout() {
        let resolved = config.workspaceLayouts[name]?.settings(on: workspaceMonitor)
        // Width/alignment policies must not reset a manually selected layout.
        let settings = resolved.flatMap { value -> WorkspaceLayoutSettings? in
            guard value.layout != nil || value.orientation != nil else { return nil }
            return WorkspaceLayoutSettings(layout: value.layout,
                                           orientation: value.orientation ?? config.defaultRootContainerOrientation)
        }
        guard settings != lastConfiguredLayout else { return }
        let previous = lastConfiguredLayout
        lastConfiguredLayout = settings
        guard settings != nil || previous != nil else { return }
        if previous?.layout != nil, settings?.layout == nil { transitionArrangement(to: .dwindle) }
        let root = rootTilingContainer
        let orientation = settings?.orientation ?? config.defaultRootContainerOrientation
        if let layout = settings?.layout { transitionArrangement(to: layout) }
        if arrangement == .dwindle {
            root.dwindleOrientation = switch orientation {
                case .horizontal: .h
                case .vertical: .v
                case .auto: nil
            }
            let axis: Orientation = switch orientation {
                case .horizontal: .h
                case .vertical: .v
                case .auto: workspaceMonitor.visibleRectPaddedByOuterGaps.width >= workspaceMonitor.visibleRectPaddedByOuterGaps.height ? .h : .v
            }
            root.changeOrientation(axis)
        }
        for window in allLeafWindowsRecursive { window.lastAppliedLayoutPhysicalRect = nil }
        WorkspaceGestureCoordinator.shared.overviewPresentationChanged()
    }
}
