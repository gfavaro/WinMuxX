/// A place on a scrolling strip: 1 to 8 count from the left, 9 is the last column,
/// as browser tabs do.
public enum ScrollingColumnPosition: Equatable, Sendable {
    case index(Int), first, last
}

public struct ScrollingFocusCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .scrollingFocus,
        allowInConfig: true,
        help: "USAGE: winmuxx scrolling-focus (1-9|first|last)\nFocus a column of the scrolling strip; 9 is the last column.",
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
        help: "USAGE: winmuxx scrolling-move (1-9|first|last)\nMove the focused column to that place on the scrolling strip; 9 is the last.",
        flags: [:], posArgs: [newMandatoryPosArgParser(\.position, parseScrollingColumnPosition, placeholder: "(1-9|first|last)")],
    )
    public var position: Lateinit<ScrollingColumnPosition> = .uninitialized
}

public struct ScrollingPinCmdArgs: CmdArgs {
    public enum Side: String, CaseIterable, Sendable { case left, right }
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

private func parsePinSide(input: PosArgParserInput) -> ParsedCliArgs<ScrollingPinCmdArgs.Side> {
    guard let raw = input.nonFlagArgs().first else { return .fail("Expected left or right", advanceBy: 0) }
    guard let side = ScrollingPinCmdArgs.Side(rawValue: raw) else {
        return .fail("Can't parse '\(raw)'\nPossible values: \(ScrollingPinCmdArgs.Side.unionLiteral)", advanceBy: 1)
    }
    return .succ(side, advanceBy: 1)
}
