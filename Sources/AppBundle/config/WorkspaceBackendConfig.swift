import Common
import TOMLKit

private struct WorkspaceBackendConfig: ConvenienceCopyable {
    var type: WorkspaceBackendKind = .virtual
}

func parseWorkspaceBackend(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace,
                           _ errors: inout [TomlParseError]) -> WorkspaceBackendKind {
    parseTable(raw, WorkspaceBackendConfig(), [
        "type": Parser(\.type) { raw, trace in
            parseString(raw, trace).flatMap {
                WorkspaceBackendKind(rawValue: $0).orFailure(.semantic(trace, "Expected virtual or native (experimental read-only observation)"))
            }
        },
    ], trace, &errors).type
}
