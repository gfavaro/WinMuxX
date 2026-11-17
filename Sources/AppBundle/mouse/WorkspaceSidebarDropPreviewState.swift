@MainActor
func setWorkspaceSidebarDropPreviewIfChanged(_ preview: WorkspaceSidebarDropPreviewViewModel?) {
    TrayMenuModel.shared.workspaceSidebarDropPreview = preview
}
