public struct RetileCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .retile,
        allowInConfig: true,
        help: "USAGE: winmuxx retile\nPut every tiled window on the showing workspaces back on its tile, and report how many had moved.",
        flags: [:], posArgs: [],
    )
}
