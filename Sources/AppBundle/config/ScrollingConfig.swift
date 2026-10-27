import AppKit
import Common
import TOMLKit

/// How the strip scrolls when focus moves to a column.
enum ScrollingCenterMode: String, CaseIterable {
    /// Scroll only as far as needed to show the column.
    case never
    /// Centre the column when it would otherwise be partly off screen.
    case onOverflow = "on-overflow"
    /// Always centre the focused column.
    case always
}

struct ScrollingConfig: ConvenienceCopyable, Equatable {
    var columnWidth = 0.49
    var widthPresets = [0.25, 0.3333, 0.5, 0.6667, 0.75, 1.0]
    var gestureEnabled = true
    var gestureSensitivity = 1.0
    var minimapEnabled = true
    var centerFocusedColumn = ScrollingCenterMode.never
    /// Holding exactly these keeps the minimap up; empty turns it off.
    var minimapHoldModifiers: NSEvent.ModifierFlags = []
}

func parseScrolling(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace, _ errors: inout [TomlParseError]) -> ScrollingConfig {
    parseTable(raw, ScrollingConfig(), [
        "column-width": Parser(\.columnWidth) { raw, trace in
            parseDouble(raw, trace).filter(.semantic(trace, "Must be between 0.1 and 1.0")) { (0.1...1).contains($0) }
        },
        "width-presets": Parser(\.widthPresets) { raw, trace in
            parseArrayOfDoubles(raw, trace).filter(.semantic(trace, "Expected ascending widths between 0.1 and 1.0")) {
                !$0.isEmpty && $0.allSatisfy { $0.isFinite && (0.1...1).contains($0) } && zip($0, $0.dropFirst()).allSatisfy(<)
            }
        },
        "gesture-enabled": Parser(\.gestureEnabled, parseBool),
        "gesture-sensitivity": Parser(\.gestureSensitivity) { raw, trace in
            parseDouble(raw, trace).filter(.semantic(trace, "Must be finite and greater than zero")) { $0.isFinite && $0 > 0 }
        },
        "minimap-enabled": Parser(\.minimapEnabled, parseBool),
        "minimap-hold-modifiers": Parser(\.minimapHoldModifiers) { raw, trace in
            parseTomlArray(raw, trace).flatMap { values in
                values.enumerated().mapAllOrFailure { index, value in
                    parseString(value, trace + .index(index)).flatMap { name -> ParsedToml<NSEvent.ModifierFlags> in
                        let flag: NSEvent.ModifierFlags? = switch name {
                            case "ctrl": .control
                            case "alt": .option
                            case "cmd": .command
                            case "shift": .shift
                            default: nil
                        }
                        return flag.orFailure(.semantic(trace + .index(index), "Expected ctrl, alt, cmd or shift"))
                    }
                }.map { NSEvent.ModifierFlags($0) }
            }
        },
        "center-focused-column": Parser(\.centerFocusedColumn) { raw, trace in
            parseString(raw, trace).flatMap {
                ScrollingCenterMode(rawValue: $0).orFailure(.semantic(trace, "Expected never, on-overflow or always"))
            }
        },
    ], trace, &errors)
}

private func parseArrayOfDoubles(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace) -> ParsedToml<[Double]> {
    parseTomlArray(raw, trace).flatMap { values in
        values.enumerated().mapAllOrFailure { index, value in parseDouble(value, trace + .index(index)) }
    }
}

private func parseDouble(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace) -> ParsedToml<Double> {
    (raw.double ?? raw.int.map(Double.init)).orFailure(expectedActualTypeError(expected: .double, actual: raw.type, trace))
}
