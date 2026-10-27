public struct UndoLayoutCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .undoLayout,
        allowInConfig: true,
        help: "USAGE: winmuxx undo-layout\nPut back the focused workspace's layout as it was before its last layout command.",
        flags: [:], posArgs: [],
    )
}
