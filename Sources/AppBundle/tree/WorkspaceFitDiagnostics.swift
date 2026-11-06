import AppKit
import Common

enum WorkspaceFitIssueKind: String, Equatable {
    case tiledGroup
}

struct WorkspaceFitIssue: Identifiable, Equatable {
    let workspaceId: WorkspaceId
    let kind: WorkspaceFitIssueKind
    let minimumSize: CGSize
    let availableSize: CGSize
    var id: String { "\(workspaceId.rawValue):\(kind.rawValue)" }
}

@MainActor
func workspaceFitIssues(in workspaces: [Workspace]) -> [WorkspaceFitIssue] {
    workspaces.compactMap { workspace -> WorkspaceFitIssue? in
        let available = workspaceTilingRect(workspace).size
        let root = workspace.rootTilingContainer
        let area = workspaceTilingRect(workspace)
        let minimum = CGSize(width: root.minimumLayoutExtent(along: .h, rect: area),
                             height: root.minimumLayoutExtent(along: .v, rect: area))
        guard layoutMinimumExceedsArea(minimum, available: available) else { return nil }
        return WorkspaceFitIssue(workspaceId: workspace.id, kind: .tiledGroup,
            minimumSize: minimum, availableSize: available)
    }
}

func layoutMinimumExceedsArea(_ minimum: CGSize, available: CGSize) -> Bool {
    minimum.width > available.width || minimum.height > available.height
}
