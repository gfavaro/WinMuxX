import TOMLKit
import Common

struct WorkspaceOverviewConfig: Equatable, ConvenienceCopyable {
    var threeFingerUp = false
}
func parseWorkspaceOverview(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> WorkspaceOverviewConfig {
    parseTable(raw, WorkspaceOverviewConfig(), ["three-finger-up": Parser(\.threeFingerUp, parseBool)], backtrace, &errors)
}
