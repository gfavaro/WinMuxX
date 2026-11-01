public struct ScrollingWidthCmdArgs: CmdArgs {
    public enum Action: String, CaseIterable, Sendable { case next, previous, full }
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingWidth,
        allowInConfig: true,
        help: "USAGE: winmuxx scrolling-width (next|previous|full)",
        flags: [:], posArgs: [newMandatoryPosArgParser(\.action, parseAction, placeholder: Action.unionLiteral)],
    )
    public var action: Lateinit<Action> = .uninitialized
}

private func parseAction(input: PosArgParserInput) -> ParsedCliArgs<ScrollingWidthCmdArgs.Action> {
    guard let raw = input.nonFlagArgs().first else { return .fail("Expected next, previous or full", advanceBy: 0) }
    guard let action = ScrollingWidthCmdArgs.Action(rawValue: raw) else {
        return .fail("Can't parse '\(raw)'\nPossible values: \(ScrollingWidthCmdArgs.Action.unionLiteral)", advanceBy: 1)
    }
    return .succ(action, advanceBy: 1)
}
