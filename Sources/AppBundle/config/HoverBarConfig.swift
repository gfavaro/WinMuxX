import Common
import TOMLKit

/// `[hover-bar]`: quick actions that appear when the pointer rests on a tiled window's top edge.
struct HoverBarConfig: ConvenienceCopyable, Equatable {
    var enabled = true
}

func parseHoverBar(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace, _ errors: inout [TomlParseError]) -> HoverBarConfig {
    parseTable(raw, HoverBarConfig(), ["enabled": Parser(\.enabled, parseBool)], trace, &errors)
}
