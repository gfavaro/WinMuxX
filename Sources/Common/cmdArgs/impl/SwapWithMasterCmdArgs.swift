public struct SwapWithMasterCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .swapWithMaster,
        allowInConfig: true,
        help: """
        USAGE: winmuxx swap-with-master [--window-id <window-id>]

        Swap the target pane with the master pane. When the master is focused,
        swap it with the first pane in the stack. Requires master layout.
        """,
        flags: ["--window-id": optionalWindowIdFlag()],
        posArgs: [],
    )
}
