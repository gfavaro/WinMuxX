import Common
import TOMLKit

struct ScrollingConfig: ConvenienceCopyable, Equatable {
    var columnWidth = 0.49
    var widthPresets = [0.25, 0.3333, 0.5, 0.6667, 0.75, 1.0]
    var gestureEnabled = true
    var gestureSensitivity = 1.0
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
        "gesture-enabled": Parser(\.gestureEnabled, parseBool),
        "gesture-sensitivity": Parser(\.gestureSensitivity) { raw, trace in
            parseDouble(raw, trace).filter(.semantic(trace, "Must be finite and greater than zero")) { $0.isFinite && $0 > 0 }
        },
        "minimap-enabled": Parser(\.minimapEnabled, parseBool),
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
