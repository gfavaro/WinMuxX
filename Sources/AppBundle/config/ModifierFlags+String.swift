import AppKit

let modifiersMap: [String: NSEvent.ModifierFlags] = [
    "shift": .shift,
    "alt": .option,
    "ctrl": .control,
    "cmd": .command,
    "hyper": [.option, .control, .command, .shift],
    "meh": [.option, .control, .shift],
]

extension NSEvent.ModifierFlags {
    func toString() -> String {
        var result: [String] = []
        if contains(.option) { result.append("alt") }
        if contains(.control) { result.append("ctrl") }
        if contains(.command) { result.append("cmd") }
        if contains(.shift) { result.append("shift") }
        return result.joined(separator: "-")
    }
}
