public struct WorkspaceCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .workspace,
        allowInConfig: true,
        help: workspace_help_generated,
        flags: [
            "--auto-back-and-forth": optionalTrueBoolFlag(\._autoBackAndForth),
            "--wrap-around": optionalTrueBoolFlag(\._wrapAround),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
            "--monitor": singleValueSubArgParser(\.monitorDescription, "<monitor-pattern>", { parseMonitorDescription($0).getOrNil() }),
            "--name": singleValueSubArgParser(\.internalName, "<workspace-name>", { WorkspaceName.parse($0).getOrNil() }),

            "--stdin": optionalTrueBoolFlag(\.explicitStdinFlag),
            "--no-stdin": optionalFalseBoolFlag(\.explicitStdinFlag),
        ],
        posArgs: [ArgParser(\.target, parseOptionalWorkspaceTarget, argPlaceholderIfMandatory: nil)],
        conflictingOptions: [
            ["--stdin", "--no-stdin"],
        ],
    )

    public var target: Lateinit<WorkspaceTarget> = .uninitialized
    public var _autoBackAndForth: Bool?
    public var failIfNoop: Bool = false
    public var _wrapAround: Bool?
    public var explicitStdinFlag: Bool? = nil
    public var monitorDescription: MonitorDescription? = nil
    public var internalName: WorkspaceName? = nil
}

func parseWorkspaceCmdArgs(_ args: StrArrSlice) -> ParsedCmd<WorkspaceCmdArgs> {
    parseSpecificCmdArgs(WorkspaceCmdArgs(rawArgs: args), args)
        .filter("--wrapAround requires using \(NextPrev.unionLiteral) argument") { ($0._wrapAround != nil).implies($0.target.isInitialized && $0.target.val.isRelative) }
        .filterNot("--auto-back-and-forth is incompatible with \(NextPrev.unionLiteral)") { $0._autoBackAndForth != nil && $0.target.isInitialized && $0.target.val.isRelative }
        .filterNot("--fail-if-noop is incompatible with \(NextPrev.unionLiteral)") { $0.failIfNoop && $0.target.isInitialized && $0.target.val.isRelative }
        .filterNot("--fail-if-noop is incompatible with --auto-back-and-forth") { $0.autoBackAndForth && $0.failIfNoop }
        .filter("--stdin and --no-stdin require using \(NextPrev.unionLiteral) argument") { ($0.explicitStdinFlag != nil).implies($0.target.isInitialized && $0.target.val.isRelative) }
        .filter("ERROR: Argument '\(workspaceTargetPlaceholder)' is mandatory") { $0.target.isInitialized || $0.internalName != nil }
        .filter("--name cannot be used with next or prev") { $0.internalName == nil || !($0.target.isInitialized && $0.target.val.isRelative) }
        .map { parsed in
            var parsed = parsed
            if !parsed.target.isInitialized, let name = parsed.internalName {
                parsed.target = .initialized(.direct(name))
            }
            return parsed
        }
}

extension WorkspaceCmdArgs {
    public var wrapAround: Bool { _wrapAround ?? false }
    public var autoBackAndForth: Bool { _autoBackAndForth ?? false }
    public var useStdin: Bool { explicitStdinFlag ?? false }
}

public enum WorkspaceTarget: Equatable, Sendable {
    case relative(NextPrev)
    case direct(WorkspaceName)

    public var isRelative: Bool {
        switch self {
            case .relative: true
            default: false
        }
    }

    public func workspaceNameOrNil() -> WorkspaceName? {
        switch self {
            case .direct(let name): name
            case .relative: nil
        }
    }
}

let workspaceTargetPlaceholder = "(<workspace-name>|next|prev)"

func parseWorkspaceTarget(i: PosArgParserInput) -> ParsedCliArgs<WorkspaceTarget> {
    switch i.arg {
        case "next": .succ(.relative(.next), advanceBy: 1)
        case "prev": .succ(.relative(.prev), advanceBy: 1)
        default: .init(WorkspaceName.parse(i.arg).map(WorkspaceTarget.direct), advanceBy: 1)
    }
}

func parseOptionalWorkspaceTarget(i: PosArgParserInput) -> ParsedCliArgs<Lateinit<WorkspaceTarget>> {
    parseWorkspaceTarget(i: i).map { .initialized($0) }
}
