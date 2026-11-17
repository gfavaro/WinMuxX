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

/// The Scrolling arrangement's strip, as StripMuxX has it.
struct ScrollingConfig: ConvenienceCopyable, Equatable {
    /// A new column's width, as a share of the display.
    var columnWidth = 0.5
    /// How much of an offscreen column remains visible at the display edge.
    var edgePreview = 14
    /// The widths `scrolling-width next` and `previous` step through.
    var widthPresets = [0.3333, 0.5, 0.6667, 1.0]
    var centerFocusedColumn = ScrollingCenterMode.never
    /// The map of the strip shown while it is panned, and by `scrolling-minimap`.
    var minimapEnabled = true
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
        "edge-preview": Parser(\.edgePreview) { raw, trace in
            parseInt(raw, trace).filter(.semantic(trace, "Must be between 0 and 40 points")) { (0...40).contains($0) }
        },
        "minimap-enabled": Parser(\.minimapEnabled, parseBool),
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
