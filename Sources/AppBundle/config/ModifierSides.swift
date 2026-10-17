import AppKit
import Common
import TOMLKit

struct ModifierSides: ConvenienceCopyable, Equatable, Sendable {
    enum Side: String, Sendable { case both, left, right }
    var alt: Side = .both
    var cmd: Side = .both
    var ctrl: Side = .both
    var shift: Side = .both

    private var rules: [(NSEvent.ModifierFlags, Side, TapModifierKey, TapModifierKey)] {
        [(.option, alt, .leftAlt, .rightAlt), (.command, cmd, .leftCmd, .rightCmd),
         (.control, ctrl, .leftCtrl, .rightCtrl), (.shift, shift, .leftShift, .rightShift)]
    }

    func restricts(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        rules.contains { modifiers.contains($0.0) && $0.1 != .both }
    }

    func matches(_ modifiers: NSEvent.ModifierFlags, flags: NSEvent.ModifierFlags) -> Bool {
        let relevant: NSEvent.ModifierFlags = [.option, .command, .control, .shift]
        guard flags.intersection(relevant) == modifiers.intersection(relevant) else { return false }
        return rules.allSatisfy { flag, side, left, right in
            guard modifiers.contains(flag), side != .both else { return true }
            let required = side == .left ? left : right
            let excluded = side == .left ? right : left
            return flags.contains(required.deviceSpecificModifierFlag) && !flags.contains(excluded.deviceSpecificModifierFlag)
        }
    }
}

func parseModifierSides(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace, _ errors: inout [TomlParseError]) -> ModifierSides {
    @Sendable func side(_ raw: TOMLValueConvertible, _ trace: TomlBacktrace) -> ParsedToml<ModifierSides.Side> {
        parseString(raw, trace).flatMap {
            ModifierSides.Side(rawValue: $0).orFailure(.semantic(trace, "Expected both, left or right"))
        }
    }
    let parsers: [String: any ParserProtocol<ModifierSides>] = [
        "alt": Parser(\.alt, side), "cmd": Parser(\.cmd, side),
        "ctrl": Parser(\.ctrl, side), "shift": Parser(\.shift, side),
    ]
    return parseTable(raw, ModifierSides(), parsers, trace, &errors)
}
