public struct WorkspaceLayoutCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .workspaceLayout,
        allowInConfig: true,
        help: """
        USAGE: winmuxx workspace-layout [--window-id <window-id>] (dwindle|master)...

        Switch the target window's workspace layout. Multiple choices cycle
        after the current mode, wrapping to the first. Requires a tiled window.
        Scrolling layout is not implemented in WinMuxX.
        """,
        flags: ["--window-id": optionalWindowIdFlag()],
        posArgs: [newMandatoryPosArgParser(\.layouts, parseWorkspaceLayoutChoices, placeholder: WorkspaceLayoutName.unionLiteral)],
    )
    public var layouts: Lateinit<[WorkspaceLayoutName]> = .uninitialized
}

public enum WorkspaceLayoutName: String, CaseIterable, Equatable, Sendable {
    case dwindle, master
}

private func parseWorkspaceLayoutChoices(input: PosArgParserInput) -> ParsedCliArgs<[WorkspaceLayoutName]> {
    var layouts: [WorkspaceLayoutName] = []
    for (index, arg) in input.nonFlagArgs().enumerated() {
        guard let layout = WorkspaceLayoutName(rawValue: arg) else {
            return .fail("Can't parse '\(arg)'\nPossible values: \(WorkspaceLayoutName.unionLiteral)", advanceBy: index + 1)
        }
        layouts.append(layout)
    }
    return .succ(layouts, advanceBy: layouts.count)
}

func parseWorkspaceLayoutCmdArgs(_ args: StrArrSlice) -> ParsedCmd<WorkspaceLayoutCmdArgs> {
    parseSpecificCmdArgs(WorkspaceLayoutCmdArgs(rawArgs: args), args)
}
