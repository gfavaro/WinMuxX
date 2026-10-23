import Common
import TOMLKit

func parseFullscreenWidth(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace) -> ParsedToml<Double?> {
    guard let value: Double = parseSimpleType(raw), value.isFinite, (0.1...1).contains(value) else {
        return .failure(.semantic(trace, "Expected a finite fullscreen-width from 0.1 to 1.0"))
    }
    return .success(value)
}

func parseOptionalSingleWindowAlignment(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace) -> ParsedToml<SingleWindowAlignment?> {
    parseString(raw, trace).flatMap {
        SingleWindowAlignment(rawValue: $0).map { Optional($0) }
            .orFailure(.semantic(trace, "Expected center, left or right"))
    }
}

private let displayWindowParsers: [String: any ParserProtocol<WorkspaceLayoutSettings>] = [
    "fullscreen-width": Parser(\.fullscreenWidth, parseFullscreenWidth),
    "single-window-alignment": Parser(\.singleWindowAlignment, parseOptionalSingleWindowAlignment),
]

func parseDisplayWindowSettings(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace,
                                _ errors: inout [TomlParseError]) -> [WorkspaceDisplayLayout] {
    guard let table = raw.table else {
        errors.append(expectedActualTypeError(expected: .table, actual: raw.type, trace))
        return []
    }
    return table.compactMap { pattern, value in
        let path = trace + .key(pattern)
        guard let selector = parseMonitorDescription(pattern).toParsedToml(path).getOrNil(appendErrorTo: &errors) else { return nil }
        return WorkspaceDisplayLayout(selector: selector,
            settings: parseTable(value, WorkspaceLayoutSettings(), displayWindowParsers, path, &errors))
    }
}

/// Named displays beat main/secondary; exact identities beat names. Width and
/// alignment share this ordering, independently of existing layout policies.
@MainActor
func matchingWindowSettings(_ rules: [WorkspaceDisplayLayout], on monitor: Monitor) -> WorkspaceLayoutSettings? {
    func priority(_ selector: MonitorDescription) -> Int {
        switch selector {
            case .uuid, .hardware, .sequenceNumber: Int.max
            case .pattern(let name, _): name.count
            case .main, .secondary: 0
        }
    }
    return rules.sorted {
        let a = priority($0.selector), b = priority($1.selector)
        return a == b ? $0.selector.selector < $1.selector.selector : a > b
    }.first { rule in
        switch rule.selector {
            case .pattern(_, let regex): monitor.name.contains(regex.val)
            default: rule.selector.resolveMonitor(sortedMonitors: sortedMonitors)?.rect.topLeftCorner == monitor.rect.topLeftCorner
        }
    }?.settings
}

extension Workspace {
    @MainActor
    var windowWidthSettings: WorkspaceLayoutSettings {
        let global = WorkspaceLayoutSettings(fullscreenWidth: config.fullscreenWidth,
                                            singleWindowAlignment: config.singleWindowAlignment)
        let display = matchingWindowSettings(config.displayWindowSettings, on: workspaceMonitor)?.overlaying(global) ?? global
        guard let workspace = config.workspaceLayouts[name] else { return display }
        let defaults = workspace.defaults.overlaying(display)
        return matchingWindowSettings(workspace.displays, on: workspaceMonitor)?.overlaying(defaults) ?? defaults
    }
}
