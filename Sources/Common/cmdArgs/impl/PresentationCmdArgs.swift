public struct PresentationCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public enum Action: String, CaseIterable, Sendable { case on, off, toggle }
    public var action: Action = .toggle
    public static let parser: CmdParser<Self> = .init(
        kind: .presentation,
        allowInConfig: true,
        help: "USAGE: presentation [on|off|toggle] [--window-id <id>]\n\nPresent one managed window over a dark backdrop until the session is cancelled. No default key binding is assigned.",
        flags: ["--window-id": optionalWindowIdFlag()],
        posArgs: [ArgParser(\.action, { .init(parseEnum($0.arg, Action.self), advanceBy: 1) })],
    )
}
