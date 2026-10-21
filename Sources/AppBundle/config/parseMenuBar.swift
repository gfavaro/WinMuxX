import TOMLKit

func parseMenuBar(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace,
                  _ errors: inout [TomlParseError]) -> MenuBarConfig {
    parseTable(raw, MenuBarConfig(), [
        "indicator": Parser(\.indicator) { raw, trace in
            parseString(raw, trace).flatMap {
                MenuBarIndicator(rawValue: $0).orFailure(.semantic(trace, "Expected icon or workspace"))
            }
        },
        "icon-appearance": Parser(\.iconAppearance) { raw, trace in
            parseString(raw, trace).flatMap {
                MenuBarIconAppearance(rawValue: $0).orFailure(.semantic(trace, "Expected color or monochrome"))
            }
        },
    ], backtrace, &errors)
}
