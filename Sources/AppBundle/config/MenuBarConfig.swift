import Foundation
import Common

struct MenuBarConfig: ConvenienceCopyable, Equatable, Sendable {
    var indicator: MenuBarIndicator = .icon
    var iconAppearance: MenuBarIconAppearance = .color
}

enum MenuBarIconAppearance: String, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case color
    case monochrome

    var id: String { rawValue }

    var title: String {
        switch self {
            case .color: "Color"
            case .monochrome: "Monochrome"
        }
    }
}

enum MenuBarIndicator: String, CaseIterable, Identifiable, Sendable {
    case icon, workspace
    /// The workspace of every display, left to right, with the focused display's in bold.
    case allDisplays = "all-displays"
    var id: String { rawValue }
    var title: String {
        switch self {
            case .icon: "Icon"
            case .workspace: "Workspace"
            case .allDisplays: "All displays"
        }
    }
}

/// One display's entry in the menu bar when it lists every display.
struct MenuBarDisplayIndicator: Equatable {
    let text: String
    let isFocused: Bool
}

func menuBarWorkspaceIndicator(label: String?, number: Int) -> String {
    let label = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return label.first.map { String($0).uppercased() } ?? String(number)
}
