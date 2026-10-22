public struct StateCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .state, allowInConfig: false,
        help: "USAGE: state [-h|--help] [--json]\nRead a versioned snapshot of managed state without refreshing native windows.",
        flags: ["--json": trueBoolFlag(\.json)], posArgs: [])
    public var json = false
}
