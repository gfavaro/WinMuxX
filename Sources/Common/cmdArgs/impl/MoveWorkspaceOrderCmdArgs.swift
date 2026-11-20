public struct MoveWorkspaceOrderCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .moveWorkspaceOrder,
        allowInConfig: true,
        help: move_workspace_order_help_generated,
        flags: [
            "--workspace": optionalWorkspaceFlag(),
        ],
        posArgs: [newMandatoryPosArgParser(\.direction, parseDirection, placeholder: Direction.unionLiteral)],
    )
    public var direction: Lateinit<Direction> = .uninitialized

    public enum Direction: String, CaseIterable, Sendable {
        case up, down
    }
}

private func parseDirection(i: PosArgParserInput) -> ParsedCliArgs<MoveWorkspaceOrderCmdArgs.Direction> {
    .init(parseEnum(i.arg, MoveWorkspaceOrderCmdArgs.Direction.self), advanceBy: 1)
}
