public struct NoPeekCmdArgs: CmdArgs {
    public enum Action: String, Sendable { case on, off, toggle }
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .noPeek,
        allowInConfig: true,
        help: """
        USAGE: winmuxx no-peek [on|off|toggle]

        Darken and blur everything except the focused window, so people beside you or on
        a call can't read your other windows. Without an argument it toggles.
        """,
        flags: [:], posArgs: [ArgParser(\.action, parseNoPeekAction)],
    )
    public var action: Action? = nil
}

private func parseNoPeekAction(_ input: PosArgParserInput) -> ParsedCliArgs<NoPeekCmdArgs.Action?> {
    guard let raw = input.nonFlagArgs().first else { return .succ(nil, advanceBy: 0) }
    guard let action = NoPeekCmdArgs.Action(rawValue: raw) else { return .fail("Expected on, off or toggle", advanceBy: 1) }
    return .succ(action, advanceBy: 1)
}
