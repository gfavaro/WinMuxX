import SwiftUI

struct ExperimentalUISettings {
    var doubleSidedWindows: Bool {
        get { UserDefaults.standard.bool(forKey: "doubleSidedWindows") }
        set { UserDefaults.standard.set(newValue, forKey: "doubleSidedWindows") }
    }

    var indicator: MenuBarIndicator {
        get { MenuBarIndicator(rawValue: UserDefaults.standard.string(forKey: "menuBarIndicator") ?? "") ?? .icon }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "menuBarIndicator") }
    }

    var iconAppearance: MenuBarIconAppearance {
        get {
            guard let value = UserDefaults.standard.string(forKey: "iconAppearance") else {
                return .color
            }
            return MenuBarIconAppearance(rawValue: value) ?? .color
        }
        set {
            UserDefaults.standard.setValue(newValue.rawValue, forKey: "iconAppearance")
            UserDefaults.standard.synchronize()
        }
    }
}

enum MenuBarIconAppearance: String, CaseIterable, Identifiable, Equatable, Hashable {
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

enum MenuBarIndicator: String, CaseIterable, Identifiable {
    case icon, workspace
    var id: String { rawValue }
    var title: String { self == .icon ? "Icon" : "Workspace" }
}

func menuBarWorkspaceIndicator(label: String?, number: Int) -> String {
    let label = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return label.first.map { String($0).uppercased() } ?? String(number)
}
