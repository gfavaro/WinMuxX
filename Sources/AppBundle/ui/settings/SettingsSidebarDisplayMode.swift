enum SettingsSidebarDisplayMode: Hashable {
    case compact, autoHide, expanded

    init(_ config: WorkspaceSidebarConfig) {
        self = config.alwaysExpanded ? .expanded : config.autoHide ? .autoHide : .compact
    }

    var edits: [SettingsConfigEdit] {
        [SettingsConfigEdit(section: "workspace-sidebar", key: "always-expanded", renderedValue: self == .expanded ? "true" : "false"),
         SettingsConfigEdit(section: "workspace-sidebar", key: "auto-hide", renderedValue: self == .autoHide ? "true" : "false")]
    }
}
