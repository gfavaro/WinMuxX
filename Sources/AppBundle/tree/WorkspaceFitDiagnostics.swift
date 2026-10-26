import AppKit
import Common

enum WorkspaceFitIssueKind: String, Equatable {
    case tiledGroup
    case scrollingColumn
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
        if workspace.arrangement == .scrolling {
            let metrics = workspace.scrollingMetrics
            guard let column = metrics.columns.first(where: {
                scrollingColumnMinimumExceedsViewport($0.node.minimumLayoutExtent(along: .h, rect: workspaceTilingRect(workspace)), viewportWidth: metrics.areaWidth)
            }) else { return nil }
            return WorkspaceFitIssue(workspaceId: workspace.id, kind: .scrollingColumn,
                minimumSize: CGSize(width: column.node.minimumLayoutExtent(along: .h, rect: workspaceTilingRect(workspace)), height: 0),
                availableSize: CGSize(width: metrics.areaWidth, height: available.height))
        }
        let root = workspace.rootTilingContainer
        let area = workspaceTilingRect(workspace)
        let minimum = CGSize(width: root.minimumLayoutExtent(along: .h, rect: area),
                             height: root.minimumLayoutExtent(along: .v, rect: area))
        guard layoutMinimumExceedsArea(minimum, available: available) else { return nil }
        return WorkspaceFitIssue(workspaceId: workspace.id, kind: .tiledGroup,
            minimumSize: minimum, availableSize: available)
    }
}

struct ExplicitResizeMinimumBlock: Equatable {
    let requested: CGFloat
    let minimum: CGFloat
    let dimension: Orientation

    var isBlocked: Bool { requested + 1 < minimum }
}

func layoutMinimumExceedsArea(_ minimum: CGSize, available: CGSize) -> Bool {
    minimum.width > available.width || minimum.height > available.height
}

func scrollingColumnMinimumExceedsViewport(_ minimumWidth: CGFloat, viewportWidth: CGFloat) -> Bool {
    minimumWidth > viewportWidth
}
