/// A place on a Scrolling strip: 1 to 8 count from the left and 9 is the last column, as
/// browser tabs do.
public enum ScrollingColumnPosition: Equatable, Sendable {
    case index(Int), first, last
}

public struct ScrollingFocusCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingFocus,
        allowInConfig: true,
        help: "USAGE: winmuxx scrolling-focus (1-9|first|last)\nFocus a column of the Scrolling strip; 9 is the last column.",
        flags: [:], posArgs: [newMandatoryPosArgParser(\.position, parseScrollingColumnPosition, placeholder: "(1-9|first|last)")],
    )
    public var position: Lateinit<ScrollingColumnPosition> = .uninitialized
}

public struct ScrollingMoveCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingMove,
        allowInConfig: true,
        help: "USAGE: winmuxx scrolling-move (1-9|first|last)\nMove the focused column to that place on the Scrolling strip; 9 is the last.",
        flags: [:], posArgs: [newMandatoryPosArgParser(\.position, parseScrollingColumnPosition, placeholder: "(1-9|first|last)")],
    )
    public var position: Lateinit<ScrollingColumnPosition> = .uninitialized
}

public struct ScrollingPinCmdArgs: CmdArgs {
    public enum Side: String, CaseIterable, Sendable, Codable { case left, right }
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingPin,
        allowInConfig: true,
        help: "USAGE: winmuxx scrolling-pin (left|right)\nPin the focused column to that screen edge at full height while the strip scrolls beside it. The same command again unpins it.",
        flags: [:], posArgs: [newMandatoryPosArgParser(\.side, parsePinSide, placeholder: Side.unionLiteral)],
    )
    public var side: Lateinit<Side> = .uninitialized
}

public struct ScrollingCenterCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingCenter,
        allowInConfig: true,
        help: "USAGE: winmuxx scrolling-center\nCenter the focused column of the Scrolling strip.",
        flags: [:], posArgs: [],
    )
}

public struct ScrollingPanCmdArgs: CmdArgs {
    public enum Direction: String, CaseIterable, Sendable { case left, right, focus }
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingPan,
        allowInConfig: true,
        help: "USAGE: winmuxx scrolling-pan (left|right|focus)\nScroll the Scrolling strip half a display without changing focus; focus brings the focused column back into view.",
        flags: [:], posArgs: [newMandatoryPosArgParser(\.direction, parsePanDirection, placeholder: Direction.unionLiteral)],
    )
    public var direction: Lateinit<Direction> = .uninitialized
}

public struct ScrollingWidthCmdArgs: CmdArgs {
    public enum Action: String, CaseIterable, Sendable { case next, previous, full }
    /// A preset step, or a share of the display between 0.1 and 1.
    public enum Target: Equatable, Sendable {
        case action(Action)
        case share(Double)
    }
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingWidth,
        allowInConfig: true,
        help: "USAGE: winmuxx scrolling-width (next|previous|full|<share>)\nSet the focused column's width on the Scrolling strip: the next or previous of scrolling.width-presets, the full usable strip width, or a share from 0.1 to 1. The sidebar and window gaps are accounted for.",
        flags: [:], posArgs: [newMandatoryPosArgParser(\.target, parseWidthTarget, placeholder: "(next|previous|full|<share>)")],
    )
    public var target: Lateinit<Target> = .uninitialized
}

private func parseScrollingColumnPosition(input: PosArgParserInput) -> ParsedCliArgs<ScrollingColumnPosition> {
    guard let raw = input.nonFlagArgs().first else { return .fail("Expected 1-9, first or last", advanceBy: 0) }
    switch raw {
        case "first": return .succ(.first, advanceBy: 1)
        case "last": return .succ(.last, advanceBy: 1)
        default:
            guard let number = Int(raw), (1...9).contains(number) else {
                return .fail("Can't parse '\(raw)'\nPossible values: 1-9, first, last", advanceBy: 1)
            }
            return .succ(number == 9 ? .last : .index(number), advanceBy: 1)
    }
}

private func parsePanDirection(input: PosArgParserInput) -> ParsedCliArgs<ScrollingPanCmdArgs.Direction> {
    guard let raw = input.nonFlagArgs().first else { return .fail("Expected left, right or focus", advanceBy: 0) }
    guard let value = ScrollingPanCmdArgs.Direction(rawValue: raw) else {
        return .fail("Can't parse '\(raw)'\nPossible values: \(ScrollingPanCmdArgs.Direction.unionLiteral)", advanceBy: 1)
    }
    return .succ(value, advanceBy: 1)
}

private func parseWidthTarget(input: PosArgParserInput) -> ParsedCliArgs<ScrollingWidthCmdArgs.Target> {
    guard let raw = input.nonFlagArgs().first else { return .fail("Expected next, previous, full or a share", advanceBy: 0) }
    if let action = ScrollingWidthCmdArgs.Action(rawValue: raw) { return .succ(.action(action), advanceBy: 1) }
    if let share = Double(raw), share.isFinite, (0.1...1).contains(share) { return .succ(.share(share), advanceBy: 1) }
    return .fail("Can't parse '\(raw)'\nPossible values: \(ScrollingWidthCmdArgs.Action.unionLiteral) or a share from 0.1 to 1", advanceBy: 1)
}

private func parsePinSide(input: PosArgParserInput) -> ParsedCliArgs<ScrollingPinCmdArgs.Side> {
    guard let raw = input.nonFlagArgs().first else { return .fail("Expected left or right", advanceBy: 0) }
    guard let side = ScrollingPinCmdArgs.Side(rawValue: raw) else {
        return .fail("Can't parse '\(raw)'\nPossible values: \(ScrollingPinCmdArgs.Side.unionLiteral)", advanceBy: 1)
    }
    return .succ(side, advanceBy: 1)
}
