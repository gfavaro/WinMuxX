struct WorkspaceSidebarProjectColorPreset: Hashable, Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
}

let workspaceSidebarProjectColorPresets: [WorkspaceSidebarProjectColorPreset] = [
    WorkspaceSidebarProjectColorPreset(name: "Blue", hex: "#7BA3C9"),
    WorkspaceSidebarProjectColorPreset(name: "Cyan", hex: "#6FBAB4"),
    WorkspaceSidebarProjectColorPreset(name: "Green", hex: "#7DBF8E"),
    WorkspaceSidebarProjectColorPreset(name: "Yellow", hex: "#C9B97A"),
    WorkspaceSidebarProjectColorPreset(name: "Orange", hex: "#C4956E"),
    WorkspaceSidebarProjectColorPreset(name: "Red", hex: "#C48181"),
    WorkspaceSidebarProjectColorPreset(name: "Pink", hex: "#BF8AAE"),
    WorkspaceSidebarProjectColorPreset(name: "Violet", hex: "#9B8FC4"),
]
