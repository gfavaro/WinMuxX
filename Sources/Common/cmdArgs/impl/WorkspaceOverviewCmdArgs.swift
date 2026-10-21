public struct WorkspaceOverviewCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public enum Action: String, CaseIterable, Sendable { case show, hide, toggle }
    public var action: Action = .toggle
    public static let parser: CmdParser<Self> = .init(
        kind: .workspaceOverview, allowInConfig: true,
        help: "USAGE: workspace-overview [show|hide|toggle]\n\nShow or dismiss the current project's workspace overview. Defaults to toggle.",
        flags: [:], posArgs: [ArgParser(\.action, { .init(parseEnum($0.arg, Action.self), advanceBy: 1) })])
}
