import AppKit
import Common
import Foundation
import HotKey
import MASShortcut

@MainActor
func buildShortcutSections() -> [ShortcutSettingsModel.Section] {
    return [
        .init(
            id: "managed-focus",
            category: .managed,
            title: "Focus",
            summary: "Directional focus movement while WinMux is managing windows.",
            actions: [
                shortcutAction(id: "focus-left", title: "Focus Left", command: "focus left"),
                shortcutAction(id: "focus-down", title: "Focus Down", command: "focus down"),
                shortcutAction(id: "focus-up", title: "Focus Up", command: "focus up"),
                shortcutAction(id: "focus-right", title: "Focus Right", command: "focus right"),
                shortcutAction(id: "focus-history", title: "Back and Forth", command: "focus-back-and-forth"),
            ],
        ),
        .init(
            id: "managed-move",
            category: .managed,
            title: "Move",
            summary: "Reposition the focused tiled window inside the tree.",
            actions: [
                shortcutAction(id: "move-left", title: "Move Left", command: "move left"),
                shortcutAction(id: "move-down", title: "Move Down", command: "move down"),
                shortcutAction(id: "move-up", title: "Move Up", command: "move up"),
                shortcutAction(id: "move-right", title: "Move Right", command: "move right"),
            ],
        ),
        .init(
            id: "managed-splits",
            category: .managed,
            title: "Splits",
            summary: "Create a shared split container with the nearest window in the chosen direction.",
            actions: [
                shortcutAction(id: "split-left", title: "Split Left", command: "join-with left"),
                shortcutAction(id: "split-down", title: "Split Down", command: "join-with down"),
                shortcutAction(id: "split-up", title: "Split Up", command: "join-with up"),
                shortcutAction(id: "split-right", title: "Split Right", command: "join-with right"),
                shortcutAction(id: "split-horizontal", title: "New Horizontal Container", command: "split horizontal"),
                shortcutAction(id: "split-vertical", title: "New Vertical Container", command: "split vertical"),
                shortcutAction(id: "split-opposite", title: "New Opposite Container", command: "split opposite"),
            ],
        ),
        .init(
            id: "managed-layout",
            category: .managed,
            title: "Layout",
            summary: "Common layout toggles for managed windows.",
            actions: [
                shortcutAction(
                    id: "toggle-floating",
                    title: "Toggle Floating",
                    subtitle: "Switch the focused managed window between floating and tiling.",
                    command: "layout floating tiling"
                ),
                shortcutAction(
                    id: "fullscreen",
                    title: "Toggle Fullscreen",
                    command: "fullscreen"
                ),
                shortcutAction(id: "layout-dwindle", title: "Dwindle", command: "layout dwindle"),
                shortcutAction(id: "layout-horizontal", title: "Horizontal Tiles", command: "layout h_tiles"),
                shortcutAction(id: "layout-vertical", title: "Vertical Tiles", command: "layout v_tiles"),
                shortcutAction(id: "layout-tabs", title: "Tab Group", command: "layout tab-group"),
                shortcutAction(id: "layout-orientation", title: "Toggle Orientation", command: "layout horizontal vertical"),
                shortcutAction(id: "balance", title: "Balance Sizes", command: "balance-sizes"),
                shortcutAction(id: "flatten", title: "Flatten Workspace Tree", command: "flatten-workspace-tree"),
            ],
        ),
        .init(id: "managed-stack", category: .managed, title: "Grouping", summary: nil,
              actions: ["left", "down", "up", "right"].map {
                  shortcutAction(id: "stack-\($0)", title: "Stack \($0.capitalized)", command: "stack-with \($0)")
              } + [
                  shortcutAction(id: "tab-next", title: "Next Tab", command: "focus tab-next"),
                  shortcutAction(id: "tab-prev", title: "Previous Tab", command: "focus tab-prev"),
              ]),
        .init(id: "managed-swap", category: .managed, title: "Swap", summary: nil,
              actions: ["left", "down", "up", "right"].map {
                  shortcutAction(id: "swap-\($0)", title: "Swap \($0.capitalized)", command: "swap \($0)")
              }),
        .init(id: "managed-resize", category: .managed, title: "Resize", summary: nil,
              actions: [
                  shortcutAction(id: "width-grow", title: "Increase Width", command: "resize width +50"),
                  shortcutAction(id: "width-shrink", title: "Decrease Width", command: "resize width -50"),
                  shortcutAction(id: "height-grow", title: "Increase Height", command: "resize height +50"),
                  shortcutAction(id: "height-shrink", title: "Decrease Height", command: "resize height -50"),
              ]),
        .init(id: "managed-window", category: .managed, title: "Window", summary: nil,
              actions: [
                  shortcutAction(id: "native-fullscreen", title: "Toggle macOS Fullscreen", command: "macos-native-fullscreen"),
                  shortcutAction(id: "native-minimize", title: "Minimize", command: "macos-native-minimize"),
                  shortcutAction(id: "close-window", title: "Close Window", command: "close"),
                  shortcutAction(id: "close-others", title: "Close Other Windows…", command: "close-all-windows-but-current"),
              ]),
        .init(id: "utilities", category: .common, title: "Utilities", summary: nil,
              actions: [
                  shortcutAction(id: "sidebar", title: "Open Sidebar", command: "open-sidebar"),
                  shortcutAction(id: "palette", title: "Window Switcher", command: "palette"),
                  shortcutAction(id: "volume-up", title: "Increase Volume", command: "volume up"),
                  shortcutAction(id: "volume-down", title: "Decrease Volume", command: "volume down"),
                  shortcutAction(id: "volume-mute", title: "Toggle Mute", command: "volume mute-toggle"),
              ]),
        .init(
            id: "workspaces",
            category: .common,
            title: "Workspaces",
            summary: "Use one modifier pattern for workspace numbers, then override specific workspaces only when needed.",
            actions: [],
        ),
    ]
}

func shortcutAction(
    id: String,
    title: String,
    subtitle: String? = nil,
    command: String,
) -> ShortcutSettingsModel.Action {
    let canonicalCommand = canonicalConfigCommandScript(command) ?? command
    return .init(
        id: id,
        title: title,
        subtitle: subtitle,
        commandScript: command,
        canonicalCommand: canonicalCommand,
    )
}

let defaultWorkspaceSwitchModifiers: NSEvent.ModifierFlags = [.option]
let defaultWorkspaceMoveModifiers: NSEvent.ModifierFlags = [.option, .shift]

struct WorkspaceShortcutState: Equatable {
    let switchModifiers: NSEvent.ModifierFlags
    let moveModifiers: NSEvent.ModifierFlags
    let switchOverrides: [String: String]
    let moveOverrides: [String: String]
}

func inferWorkspaceShortcutState(
    from entries: [String: String],
    workspaceNumbers: [String],
    defaultSwitchModifiers: NSEvent.ModifierFlags = defaultWorkspaceSwitchModifiers,
    defaultMoveModifiers: NSEvent.ModifierFlags = defaultWorkspaceMoveModifiers,
) -> WorkspaceShortcutState {
    let switchCommands = Dictionary(uniqueKeysWithValues: workspaceNumbers.map { ($0, workspaceCommand($0, kind: .switchTo)) })
    let moveCommands = Dictionary(uniqueKeysWithValues: workspaceNumbers.map { ($0, workspaceCommand($0, kind: .moveTo)) })

    var actualSwitchNotations: [String: String] = [:]
    var actualMoveNotations: [String: String] = [:]
    var switchModifierFrequencies: [NSEvent.ModifierFlags.RawValue: Int] = [:]
    var moveModifierFrequencies: [NSEvent.ModifierFlags.RawValue: Int] = [:]

    for (notation, command) in entries {
        if let workspaceName = switchCommands.first(where: { $0.value == command })?.key {
            actualSwitchNotations[workspaceName] = notation
            if let modifiers = matchingWorkspacePatternModifiers(notation: notation, workspaceName: workspaceName) {
                switchModifierFrequencies[modifiers.rawValue, default: 0] += 1
            }
        }
        if let workspaceName = moveCommands.first(where: { $0.value == command })?.key {
            actualMoveNotations[workspaceName] = notation
            if let modifiers = matchingWorkspacePatternModifiers(notation: notation, workspaceName: workspaceName) {
                moveModifierFrequencies[modifiers.rawValue, default: 0] += 1
            }
        }
    }

    let switchModifiers = NSEvent.ModifierFlags(
        rawValue: switchModifierFrequencies.max(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        })?.key ?? defaultSwitchModifiers.rawValue
    )
    let moveModifiers = NSEvent.ModifierFlags(
        rawValue: moveModifierFrequencies.max(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        })?.key ?? defaultMoveModifiers.rawValue
    )

    let switchOverrides = workspaceNumbers.reduce(into: [String: String]()) { result, workspaceName in
        guard let actualNotation = actualSwitchNotations[workspaceName],
              actualNotation != workspacePatternNotation(modifiers: switchModifiers, workspaceName: workspaceName)
        else { return }
        result[workspaceName] = actualNotation
    }
    let moveOverrides = workspaceNumbers.reduce(into: [String: String]()) { result, workspaceName in
        guard let actualNotation = actualMoveNotations[workspaceName],
              actualNotation != workspacePatternNotation(modifiers: moveModifiers, workspaceName: workspaceName)
        else { return }
        result[workspaceName] = actualNotation
    }

    return WorkspaceShortcutState(
        switchModifiers: switchModifiers,
        moveModifiers: moveModifiers,
        switchOverrides: switchOverrides,
        moveOverrides: moveOverrides,
    )
}

@MainActor
func shortcutSettingsWorkspaceNumbers() -> [String] {
    let configuredNumbers = Set(Array(config.minimumWorkspaceCount == nil ? config.persistentWorkspaces : []).filter { workspaceKey(for: $0) != nil })
        .union(TrayMenuModel.shared.workspaces.map(\.name).filter { workspaceKey(for: $0) != nil })
    let defaults = (1 ... 9).map(String.init)
    let merged = configuredNumbers.union(defaults)
    return merged.sorted { lhs, rhs in
        guard let lhsInt = Int(lhs), let rhsInt = Int(rhs) else {
            return lhs < rhs
        }
        return lhsInt < rhsInt
    }
}

func workspaceCommand(_ workspaceName: String, kind: ShortcutSettingsModel.WorkspaceShortcutKind) -> String {
    switch kind {
        case .switchTo:
            "workspace \(quoteCommandArgument(workspaceName))"
        case .moveTo:
            "move-node-to-workspace \(quoteCommandArgument(workspaceName))"
    }
}

func parseWorkspaceCommandTarget(
    _ command: String,
    kind: ShortcutSettingsModel.WorkspaceShortcutKind
) -> String? {
    let prefix: String = switch kind {
        case .switchTo: "workspace "
        case .moveTo: "move-node-to-workspace "
    }
    guard command.hasPrefix(prefix) else { return nil }
    return String(command.dropFirst(prefix.count))
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
}

private func matchingWorkspacePatternModifiers(notation: String, workspaceName: String) -> NSEvent.ModifierFlags? {
    guard let key = workspaceKey(for: workspaceName),
          let (modifiers, actualKey) = try? parseBinding(notation, .emptyRoot, keyNotationToKeyCode).get(),
          actualKey == key
    else {
        return nil
    }
    return modifiers
}

func workspacePatternNotation(modifiers: NSEvent.ModifierFlags, workspaceName: String) -> String? {
    guard let key = workspaceKey(for: workspaceName) else { return nil }
    return renderBindingNotation(modifiers: modifiers, key: key)
}

func workspaceKey(for workspaceName: String) -> Key? {
    switch workspaceName {
        case "0": .zero
        case "1": .one
        case "2": .two
        case "3": .three
        case "4": .four
        case "5": .five
        case "6": .six
        case "7": .seven
        case "8": .eight
        case "9": .nine
        default: nil
    }
}

private func quoteCommandArgument(_ raw: String) -> String {
    if raw.range(of: #"^[A-Za-z0-9._/-]+$"#, options: .regularExpression) != nil {
        return raw
    }
    let escaped = raw
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

func notation(from shortcut: MASShortcut) -> String? {
    guard let key = Key(carbonKeyCode: UInt32(shortcut.keyCode)) else { return nil }
    let modifiers = normalizedRecorderModifiers(from: shortcut.modifierFlags)
    return renderBindingNotation(modifiers: modifiers, key: key)
}

func masShortcut(from notation: String) -> MASShortcut? {
    guard let (modifiers, key) = try? parseBinding(notation, .emptyRoot, keyNotationToKeyCode).get() else {
        return nil
    }
    return MASShortcut(keyCode: Int(key.carbonKeyCode), modifierFlags: modifiers)
}

private func normalizedRecorderModifiers(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    var result: NSEvent.ModifierFlags = []
    if flags.contains(.option) { result.insert(.option) }
    if flags.contains(.control) { result.insert(.control) }
    if flags.contains(.command) { result.insert(.command) }
    if flags.contains(.shift) { result.insert(.shift) }
    return result
}

func renderBindingNotation(modifiers: NSEvent.ModifierFlags, key: Key) -> String {
    modifiers.isEmpty ? key.toString() : "\(modifiers.toString())-\(key.toString())"
}

func displayBindingNotation(_ notation: String) -> String {
    notation.split(separator: "-").map { component in
        switch component {
            case "alt": "⌥"
            case "ctrl": "⌃"
            case "cmd": "⌘"
            case "shift": "⇧"
            case "left": "←"
            case "right": "→"
            case "up": "↑"
            case "down": "↓"
            case "enter": "↩"
            case "esc": "⎋"
            case "space": "Space"
            case "tab": "⇥"
            case "backspace": "⌫"
            case "semicolon": ";"
            case "comma": ","
            case "period": "."
            case "slash": "/"
            case "minus": "-"
            case "equal": "="
            default:
                String(component).uppercased()
        }
    }.joined(separator: "")
}

private extension Result {
    func get() throws -> Success {
        switch self {
            case .success(let value): value
            case .failure(let error): throw error
        }
    }
}

func shortcutSettingsError(_ message: String) -> NSError {
    NSError(domain: winMuxAppId, code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
