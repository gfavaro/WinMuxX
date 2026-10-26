import Common
import TOMLKit

private struct WorkspaceBackendConfig: ConvenienceCopyable {
    var type: WorkspaceBackendKind = .virtual
}

struct NativeSpacesConfig: ConvenienceCopyable, Equatable {
    var tilingEnabled = false
    var restoreLayouts = true
}

func parseNativeSpaces(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace,
                       _ errors: inout [TomlParseError]) -> NativeSpacesConfig {
    parseTable(raw, NativeSpacesConfig(), [
        "tiling-enabled": Parser(\.tilingEnabled, parseBool),
        "restore-layouts": Parser(\.restoreLayouts, parseBool),
    ], trace, &errors)
}

func parseWorkspaceBackend(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace,
                           _ errors: inout [TomlParseError]) -> WorkspaceBackendKind {
    parseTable(raw, WorkspaceBackendConfig(), [
        "type": Parser(\.type) { raw, trace in
            parseString(raw, trace).flatMap {
                WorkspaceBackendKind(rawValue: $0).orFailure(.semantic(trace, "Expected virtual or native (experimental)"))
            }
        },
    ], trace, &errors).type
}
