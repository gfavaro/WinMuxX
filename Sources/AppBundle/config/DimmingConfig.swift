import Common
import TOMLKit

/// `[dimming]`: how dark windows other than the focused one get. 0 leaves them alone.
struct DimmingConfig: ConvenienceCopyable, Equatable {
    var inactiveWindows = 0.0
}

private let dimmingParsers: [String: any ParserProtocol<DimmingConfig>] = [
    "inactive-windows": Parser(\.inactiveWindows) { raw, trace in
        (raw.double ?? raw.int.map(Double.init)).orFailure(.semantic(trace, "Must be a number from 0 to 0.8"))
            .filter(.semantic(trace, "Must be a number from 0 to 0.8")) { $0.isFinite && $0 >= 0 && $0 <= 0.8 }
    },
]

func parseDimming(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace, _ errors: inout [TomlParseError]) -> DimmingConfig {
    parseTable(raw, DimmingConfig(), dimmingParsers, trace, &errors)
}
