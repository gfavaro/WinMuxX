@MainActor
func setWorkspaceSidebarDropPreviewIfChanged(_ preview: WorkspaceSidebarDropPreviewViewModel?) {
    guard TrayMenuModel.shared.workspaceSidebarDropPreview != preview else { return }
    TrayMenuModel.shared.workspaceSidebarDropPreview = preview
    WorkspaceSidebarPanel.syncVisiblePanelModelsFromShared()
}
