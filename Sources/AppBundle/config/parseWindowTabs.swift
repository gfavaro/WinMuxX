import TOMLKit

private let windowTabsParser: [String: any ParserProtocol<WindowTabsConfig>] = [
    "double-sided-windows": Parser(\.doubleSidedWindows, parseBool),
    "enabled": Parser(\.enabled, parseBool),
    "height": Parser(\.height, parseWindowTabsHeight),
    "style": Parser(\.style) { raw, backtrace in
        parseString(raw, backtrace).flatMap {
            WindowTabStyle(rawValue: $0).orFailure(.semantic(backtrace, "Expected pills or tabs"))
        }
    },
]

func parseWindowTabs(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> WindowTabsConfig {
    parseTable(raw, WindowTabsConfig(), windowTabsParser, backtrace, &errors)
}

private func parseWindowTabsHeight(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Int> {
    parseInt(raw, backtrace)
        .filter(.semantic(backtrace, "Must be greater than 20")) { $0 > 20 }
}
