import AppKit
import MASShortcut

/// A shortcut macOS itself handles (System Settings → Keyboard → Keyboard Shortcuts).
struct SystemShortcut: Equatable {
    let id: Int
    let name: String
    let keyCode: Int
    let modifiers: NSEvent.ModifierFlags
}

/// Read-only view of macOS's own shortcuts, so Settings can name the owner of a clash.
/// Other apps' global shortcuts cannot be listed, so they are never reported.
enum SystemShortcuts {
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// macOS's defaults. Its preferences file omits a shortcut until the user changes it.
    static let defaults: [SystemShortcut] = [
        .init(id: 64, name: "Show Spotlight search", keyCode: 49, modifiers: .command),
        .init(id: 65, name: "Show Finder search window", keyCode: 49, modifiers: [.command, .option]),
        .init(id: 60, name: "Select the previous input source", keyCode: 49, modifiers: .control),
        .init(id: 61, name: "Select next source in Input menu", keyCode: 49, modifiers: [.control, .option]),
        .init(id: 28, name: "Save picture of screen as a file", keyCode: 20, modifiers: [.command, .shift]),
        .init(id: 29, name: "Copy picture of screen to the clipboard", keyCode: 20, modifiers: [.command, .shift, .control]),
        .init(id: 30, name: "Save picture of selected area as a file", keyCode: 21, modifiers: [.command, .shift]),
        .init(id: 31, name: "Copy picture of selected area to the clipboard", keyCode: 21, modifiers: [.command, .shift, .control]),
        .init(id: 184, name: "Screenshot and recording options", keyCode: 23, modifiers: [.command, .shift]),
        .init(id: 32, name: "Mission Control", keyCode: 126, modifiers: .control),
        .init(id: 33, name: "Application windows", keyCode: 125, modifiers: .control),
        .init(id: 79, name: "Move left a space", keyCode: 123, modifiers: .control),
        .init(id: 81, name: "Move right a space", keyCode: 124, modifiers: .control),
        .init(id: 36, name: "Show Desktop", keyCode: 103, modifiers: []),
        .init(id: 27, name: "Move focus to next window", keyCode: 50, modifiers: .command),
        .init(id: 98, name: "Show Help menu", keyCode: 44, modifiers: [.command, .shift]),
        .init(id: 52, name: "Turn Dock hiding on/off", keyCode: 2, modifiers: [.command, .option]),
        .init(id: 59, name: "Turn VoiceOver on or off", keyCode: 96, modifiers: .command),
        .init(id: 162, name: "Show Accessibility controls", keyCode: 96, modifiers: [.command, .option]),
        .init(id: 12, name: "Turn keyboard access on or off", keyCode: 122, modifiers: .control),
        .init(id: 7, name: "Move focus to the menu bar", keyCode: 120, modifiers: .control),
        .init(id: 8, name: "Move focus to the Dock", keyCode: 99, modifiers: .control),
        .init(id: 9, name: "Move focus to active or next window", keyCode: 118, modifiers: .control),
        .init(id: 10, name: "Move focus to the window toolbar", keyCode: 96, modifiers: .control),
        .init(id: 11, name: "Move focus to the floating window", keyCode: 97, modifiers: .control),
        .init(id: 13, name: "Change the way Tab moves focus", keyCode: 98, modifiers: .control),
        .init(id: 57, name: "Move focus to status menus", keyCode: 100, modifiers: .control),
    ]

    /// Names for shortcuts that are off by default but may be turned on.
    static let names: [Int: String] = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0.name) })
        .merging([
            80: "Move left a space", 82: "Move right a space", 15: "Turn zoom on or off", 17: "Zoom in", 19: "Zoom out",
            160: "Show Launchpad", 163: "Show Notification Center", 175: "Turn Do Not Disturb on/off", 222: "Turn Stage Manager on/off",
        ]) { current, _ in current }
        .merging((118...133).map { ($0, "Switch to Desktop \($0 - 117)") }) { current, _ in current }

    /// The enabled shortcuts, from the defaults overridden by `AppleSymbolicHotKeys`.
    static func enabled(overrides table: [String: Any]?) -> [SystemShortcut] {
        var result: [Int: SystemShortcut] = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
        for (key, raw) in table ?? [:] {
            guard let id = Int(key), let entry = raw as? [String: Any] else { continue }
            let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? false
            guard enabled, let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [NSNumber], parameters.count >= 3,
                  parameters[1].intValue != 65535 else {
                result[id] = nil
                continue
            }
            result[id] = SystemShortcut(id: id, name: names[id] ?? "a macOS shortcut",
                keyCode: parameters[1].intValue, modifiers: modifiers(fromMask: parameters[2].intValue))
        }
        return result.values.sorted { $0.id < $1.id }
    }

    static func current() -> [SystemShortcut] {
        enabled(overrides: CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString) as? [String: Any])
    }

    static func modifiers(fromMask mask: Int) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(mask)).intersection(relevantModifiers)
    }

    static func owner(keyCode: Int, modifiers: NSEvent.ModifierFlags, in shortcuts: [SystemShortcut]) -> SystemShortcut? {
        let wanted = modifiers.intersection(relevantModifiers)
        return shortcuts.first { $0.keyCode == keyCode && $0.modifiers == wanted }
    }
}

struct ShortcutKey: Hashable {
    let keyCode: Int
    let modifiers: UInt

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(SystemShortcuts.relevantModifiers).rawValue
    }
}

/// Other modifiers for the same key that neither macOS nor WinMuxX uses, best first.
func freeShortcutAlternatives(keyCode: Int, taken: Set<ShortcutKey>, system: [SystemShortcut], limit: Int = 2) -> [NSEvent.ModifierFlags] {
    let candidates: [NSEvent.ModifierFlags] = [
        .option, [.control, .option], [.option, .shift], [.command, .option], [.control, .shift],
        [.control, .command], [.control, .option, .shift], [.command, .option, .shift], [.control, .option, .command],
    ]
    return Array(candidates.filter { modifiers in
        !taken.contains(ShortcutKey(keyCode: keyCode, modifiers: modifiers))
            && SystemShortcuts.owner(keyCode: keyCode, modifiers: modifiers, in: system) == nil
    }.prefix(limit))
}

/// One message per WinMuxX action whose shortcut clashes with macOS or another WinMuxX
/// shortcut, naming the owner and suggesting free modifiers for the same key.
func shortcutConflictMessages(assignments: [String: String], titles: [String: String],
                              customNotations: [String], system: [SystemShortcut]) -> [String: String] {
    func key(_ notation: String) -> ShortcutKey? {
        masShortcut(from: notation).map { ShortcutKey(keyCode: $0.keyCode, modifiers: $0.modifierFlags) }
    }
    let actionKeys = assignments.compactMapValues(key)
    let taken = Set(actionKeys.values).union(customNotations.compactMap(key))
    var messages: [String: String] = [:]
    for (actionId, shortcut) in actionKeys {
        let modifiers = NSEvent.ModifierFlags(rawValue: shortcut.modifiers)
        var reasons: [String] = []
        if let owner = SystemShortcuts.owner(keyCode: shortcut.keyCode, modifiers: modifiers, in: system) {
            reasons.append("macOS uses this for \(owner.name)")
        }
        let sharing = actionKeys.filter { $0.key != actionId && $0.value == shortcut }.compactMap { titles[$0.key] }.sorted()
        if !sharing.isEmpty { reasons.append("Also assigned to \(sharing.joined(separator: ", "))") }
        guard !reasons.isEmpty else { continue }
        let alternatives = freeShortcutAlternatives(keyCode: shortcut.keyCode, taken: taken, system: system)
            .map { shortcutGlyphs(keyCode: shortcut.keyCode, modifiers: $0) }
        let suggestion = alternatives.isEmpty ? "" : ". Try \(alternatives.joined(separator: " or "))"
        messages[actionId] = reasons.joined(separator: ". ") + suggestion + "."
    }
    return messages
}

func shortcutGlyphs(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> String {
    let shortcut = MASShortcut(keyCode: keyCode, modifierFlags: modifiers)
    return shortcut.modifierFlagsString + (shortcut.keyCodeString ?? "")
}
