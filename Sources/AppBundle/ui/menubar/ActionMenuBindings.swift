import AppKit
import Common
import HotKey

/// A snapshot of the effective bindings, independent of menu rendering.
struct ActionMenuBinding {
    let notation: String
    let commands: [any Command]
    let keyEquivalent: String?
    let modifiers: NSEvent.ModifierFlags
}

struct ActionMenuBindings {
    private(set) var entries: [ActionMenuBinding]
    private var shown: Set<Int> = []

    @MainActor
    init(mode: Mode?) {
        entries = (mode?.bindings.values.map {
            ActionMenuBinding(notation: $0.descriptionWithKeyNotation, commands: $0.commands,
                              keyEquivalent: menuKeyEquivalent($0.keyCode), modifiers: $0.modifiers)
        } ?? []) + (mode?.tapBindings.values.map {
            ActionMenuBinding(notation: "Tap " + $0.descriptionWithKeyNotation, commands: $0.commands,
                              keyEquivalent: nil, modifiers: [])
        } ?? []) + (mode?.sequenceBindings.values.map {
            ActionMenuBinding(notation: "Sequence " + $0.descriptionWithKeyNotation, commands: $0.commands,
                              keyEquivalent: nil, modifiers: [])
        } ?? [])
        entries.sort { $0.notation < $1.notation }
    }

    mutating func bindings(for command: any Command) -> [ActionMenuBinding] {
        let matches = entries.indices.filter {
            entries[$0].commands.count == 1 && entries[$0].commands[0].equals(command)
        }
        shown.formUnion(matches)
        return matches.map { entries[$0] }
    }

    var unshown: [ActionMenuBinding] { entries.indices.filter { !shown.contains($0) }.map { entries[$0] } }
}

/// A binding as macOS menus print shortcuts: ⌃⌥⇧⌘, then the key.
func shortcutHintText(_ binding: ActionMenuBinding) -> String {
    guard let key = binding.keyEquivalent, let scalar = key.unicodeScalars.first else { return binding.notation }
    let modifiers: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
    let prefix = modifiers.filter { binding.modifiers.contains($0.0) }.map(\.1).joined()
    let names: [Int: String] = [
        0x20: "Space", 0x0D: "↩", 0x09: "⇥", 0x1B: "⎋", 0x08: "⌫",
        NSLeftArrowFunctionKey: "←", NSRightArrowFunctionKey: "→", NSUpArrowFunctionKey: "↑", NSDownArrowFunctionKey: "↓",
        NSDeleteFunctionKey: "⌦", NSHomeFunctionKey: "↖", NSEndFunctionKey: "↘", NSPageUpFunctionKey: "⇞", NSPageDownFunctionKey: "⇟",
    ]
    let code = Int(scalar.value)
    if let name = names[code] { return prefix + name }
    if (NSF1FunctionKey...NSF35FunctionKey).contains(code) { return prefix + "F\(code - NSF1FunctionKey + 1)" }
    return prefix + key.uppercased()
}

func menuKeyEquivalent(_ key: Key) -> String? {
    let name = key.toString()
    let special: [String: String] = [
        "space": " ", "return": "\r", "enter": "\r", "tab": "\t", "escape": "\u{1b}", "esc": "\u{1b}",
        "delete": "\u{8}", "backspace": "\u{8}", "forwardDelete": String(UnicodeScalar(NSDeleteFunctionKey)!),
        "left": String(UnicodeScalar(NSLeftArrowFunctionKey)!), "right": String(UnicodeScalar(NSRightArrowFunctionKey)!),
        "up": String(UnicodeScalar(NSUpArrowFunctionKey)!), "down": String(UnicodeScalar(NSDownArrowFunctionKey)!),
        "minus": "-", "equal": "=", "leftSquareBracket": "[", "rightSquareBracket": "]", "backslash": "\\",
        "semicolon": ";", "quote": "'", "comma": ",", "period": ".", "slash": "/", "backtick": "`",
        "home": String(UnicodeScalar(NSHomeFunctionKey)!), "end": String(UnicodeScalar(NSEndFunctionKey)!),
        "pageUp": String(UnicodeScalar(NSPageUpFunctionKey)!), "pageDown": String(UnicodeScalar(NSPageDownFunctionKey)!),
        "sectionSign": "§",
    ]
    if let equivalent = special[name] { return equivalent }
    if name.hasPrefix("f"), let number = Int(name.dropFirst()), (1...20).contains(number) {
        return String(UnicodeScalar(NSF1FunctionKey + number - 1)!)
    }
    return name.count == 1 ? name.lowercased() : nil
}
