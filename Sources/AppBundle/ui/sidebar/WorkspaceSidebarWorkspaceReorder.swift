import Foundation

/// Where a dragged workspace header would land: just above or below `targetWorkspaceName`.
struct WorkspaceSidebarReorderPreview: Equatable {
    let workspaceName: String
    let targetWorkspaceName: String
    let placeAfter: Bool
}

/// The landing spot for `workspaceName` dragged to `pointer`, or nil when the pointer isn't
/// over another workspace of the same project. A spot that leaves the order unchanged is nil too.
@MainActor
func workspaceSidebarReorderPreview(_ workspaceName: String, pointer: CGPoint) -> WorkspaceSidebarReorderPreview? {
    guard case .workspace(let targetName)? = workspaceSidebarDropTarget(at: pointer)?.kind,
          targetName != workspaceName,
          let source = Workspace.existing(byName: workspaceName),
          let target = Workspace.existing(byName: targetName),
          target.projectId == source.projectId,
          !source.isConfiguredPersistent, !target.isConfiguredPersistent,
          let rect = workspaceSidebarDropTarget(at: pointer)?.rect
    else { return nil }
    let placeAfter = pointer.y >= rect.center.y
    let shown = orderedWorkspaces(in: source.projectId)
    guard let sourceIndex = shown.firstIndex(of: source), let targetIndex = shown.firstIndex(of: target) else { return nil }
    let landingIndex = placeAfter ? targetIndex + 1 : targetIndex
    if landingIndex == sourceIndex || landingIndex == sourceIndex + 1 { return nil }
    return WorkspaceSidebarReorderPreview(workspaceName: workspaceName, targetWorkspaceName: targetName, placeAfter: placeAfter)
}

@MainActor
func updateSidebarWorkspaceReorder(_ workspaceName: String, pointer: CGPoint) {
    let preview = workspaceSidebarReorderPreview(workspaceName, pointer: pointer)
    if TrayMenuModel.shared.workspaceSidebarReorderPreview != preview {
        TrayMenuModel.shared.workspaceSidebarReorderPreview = preview
    }
}

@MainActor
func finishSidebarWorkspaceReorder(_ workspaceName: String, pointer: CGPoint) {
    let preview = workspaceSidebarReorderPreview(workspaceName, pointer: pointer)
    TrayMenuModel.shared.workspaceSidebarReorderPreview = nil
    guard let preview, let source = Workspace.existing(byName: preview.workspaceName),
          let target = Workspace.existing(byName: preview.targetWorkspaceName)
    else { return }
    let shown = orderedWorkspaces(in: source.projectId)
    guard let targetIndex = shown.firstIndex(of: target) else { return }
    let before = preview.placeAfter ? shown.dropFirst(targetIndex + 1).first : target
    if moveWorkspaceInOrder(source, before: before) {
        scheduleRefreshSession(.menuBarButton)
    }
}
