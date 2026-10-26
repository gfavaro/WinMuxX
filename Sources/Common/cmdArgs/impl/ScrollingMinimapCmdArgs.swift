public struct ScrollingMinimapCmdArgs: CmdArgs {
    public enum Action: String, Sendable { case toggle }
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingMinimap,
        allowInConfig: true,
        help: "USAGE: winmuxx scrolling-minimap [toggle]\nToggle the clickable map of the focused scrolling workspace.",
        flags: [:], posArgs: [ArgParser(\.action, parseAction)],
    )
    public var action: Action? = nil
}

private func parseAction(_ input: PosArgParserInput) -> ParsedCliArgs<ScrollingMinimapCmdArgs.Action?> {
    guard let raw = input.nonFlagArgs().first else { return .succ(nil, advanceBy: 0) }
    guard let action = ScrollingMinimapCmdArgs.Action(rawValue: raw) else {
        return .fail("Expected toggle", advanceBy: 1)
    }
    return .succ(action, advanceBy: 1)
}
