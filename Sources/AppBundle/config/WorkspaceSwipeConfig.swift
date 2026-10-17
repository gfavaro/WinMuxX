import TOMLKit
import Common

struct WorkspaceSwipeConfig: Equatable, ConvenienceCopyable {
    var enabled = false
    var reverseDirection = false
    var animationDurationMs = 220
}

private let workspaceSwipeParser: [String: any ParserProtocol<WorkspaceSwipeConfig>] = [
    "animation-duration-ms": Parser(\.animationDurationMs) { raw, trace in
        parseInt(raw, trace).filter(.semantic(trace, "Must be between 0 and 1000 milliseconds")) { (0...1000).contains($0) }
    },
    "enabled": Parser(\.enabled, parseBool),
    "reverse-direction": Parser(\.reverseDirection, parseBool),
]

func parseWorkspaceSwipe(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> WorkspaceSwipeConfig {
    parseTable(raw, WorkspaceSwipeConfig(), workspaceSwipeParser, backtrace, &errors)
}
