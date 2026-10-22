import Common
import HotKey
import TOMLKit

struct Mode: ConvenienceCopyable, Equatable, Sendable {
    var timeoutMs: Int = 0
    var showIndicator = false
    var exitOnUnboundKey = false
    var indicatorColor: String?
    var bindings: [String: HotkeyBinding]
    var tapBindings: [String: TapBinding]
    var sequenceBindings: [String: SequenceBinding]

    init(
        bindings: [String: HotkeyBinding],
        tapBindings: [String: TapBinding],
        sequenceBindings: [String: SequenceBinding] = [:],
    ) {
        self.bindings = bindings
        self.tapBindings = tapBindings
        self.sequenceBindings = sequenceBindings
    }

    static let zero = Mode(bindings: [:], tapBindings: [:], sequenceBindings: [:])
}

func parseModes(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError], _ mapping: [String: Key]) -> [String: Mode] {
    guard let rawTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return [:]
    }
    var result: [String: Mode] = [:]
    for (key, value) in rawTable {
        result[key] = parseMode(value, backtrace + .key(key), &errors, mapping)
    }
    return result
}

func parseMode(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError], _ mapping: [String: Key]) -> Mode {
    guard let rawTable: TOMLTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return .zero
    }

    var result: Mode = .zero
    for (key, value) in rawTable {
        let backtrace = backtrace + .key(key)
        switch key {
            case "timeout-ms":
                if let v = parseInt(value, backtrace).getOrNil(appendErrorTo: &errors) {
                    if (0...60000).contains(v) { result.timeoutMs = v }
                    else { errors.append(.semantic(backtrace, "Must be between 0 and 60000")) }
                }
            case "show-indicator":
                if let v = parseBool(value, backtrace).getOrNil(appendErrorTo: &errors) { result.showIndicator = v }
            case "exit-on-unbound-key":
                if let v = parseBool(value, backtrace).getOrNil(appendErrorTo: &errors) { result.exitOnUnboundKey = v }
            case "indicator-color":
                if let v = parseString(value, backtrace).getOrNil(appendErrorTo: &errors) {
                    if let hex = normalizedWorkspaceSidebarColorHex(v) { result.indicatorColor = hex }
                    else { errors.append(.semantic(backtrace, "Use a six-digit hex color, such as #5E9EFF")) }
                }
            case "binding":
                let (chordBindings, seqBindings) = parseBindings(value, backtrace, &errors, mapping)
                result.bindings = chordBindings
                result.sequenceBindings = seqBindings
            case "binding-tap":
                result.tapBindings = parseTapBindings(value, backtrace, &errors)
            default:
                errors += [unknownKeyError(backtrace)]
        }
    }
    return result
}
