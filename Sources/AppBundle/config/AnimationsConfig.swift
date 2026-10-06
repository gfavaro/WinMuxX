import Common
import TOMLKit

struct AnimationsConfig: ConvenienceCopyable, Equatable {
    var enabled = true
    var durationMs = 150
}

func parseAnimations(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace, _ errors: inout [TomlParseError]) -> AnimationsConfig {
    let parsers: [String: any ParserProtocol<AnimationsConfig>] = [
        "enabled": Parser(\.enabled, parseBool),
        "duration-ms": Parser(\.durationMs) { raw, trace in
            parseInt(raw, trace).filter(.semantic(trace, "Must be between 0 and 2000 milliseconds")) { (0...2000).contains($0) }
        },
    ]
    return parseTable(raw, AnimationsConfig(), parsers, trace, &errors)
}
