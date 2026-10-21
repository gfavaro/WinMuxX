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
    var id: String { rawValue }
    var title: String { self == .icon ? "Icon" : "Workspace" }
}

func menuBarWorkspaceIndicator(label: String?, number: Int) -> String {
    let label = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return label.first.map { String($0).uppercased() } ?? String(number)
}
