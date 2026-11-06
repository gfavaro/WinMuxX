import TOMLKit
import Common

struct WorkspaceSwipeConfig: Equatable, ConvenienceCopyable {
    var enabled = false
}

private let workspaceSwipeParser: [String: any ParserProtocol<WorkspaceSwipeConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
]

func parseWorkspaceSwipe(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> WorkspaceSwipeConfig {
    parseTable(raw, WorkspaceSwipeConfig(), workspaceSwipeParser, backtrace, &errors)
}
