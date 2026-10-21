import Foundation
import Common

/// An explicit, read-only scan of a settled model. Never invoke between detach/rebind.
/// History and FrozenFocus are intentionally excluded: missing historical windows fall
/// back through LiveFocus and are not dangling ownership. Detached closing windows
/// are excluded unless the caller supplies them as expected live windows.
struct ModelInvariantViolation: Equatable {
    enum Kind: String { case registry, nameIndex, project, viewport, duplicateActiveWorkspace, duplicateNode, duplicateWindowID, parent, missingWindow }
    let kind: Kind
    let identity: String
}

@MainActor
extension WinMuxRuntime {
    func modelInvariantViolations(expectedWindows: [Window]? = nil) -> [ModelInvariantViolation] {
        withValue {
            var result: [ModelInvariantViolation] = []
            func report(_ kind: ModelInvariantViolation.Kind, _ identity: String) {
                result.append(.init(kind: kind, identity: identity))
            }
            let state = workspaces
            for (id, workspace) in state.workspaceById {
                if id != workspace.id { report(.registry, id.rawValue) }
                if state.workspaceIdByName[workspace.name] != id { report(.nameIndex, id.rawValue) }
                if state.projectsById[workspace.projectId] == nil { report(.project, id.rawValue) }
            }
            for (name, id) in state.workspaceIdByName where state.workspaceById[id]?.name != name {
                report(.nameIndex, id.rawValue)
            }
            for (projectID, project) in state.projectsById {
                var seen = Set<WorkspaceId>()
                for id in project.workspaceOrder {
                    if !seen.insert(id).inserted || state.workspaceById[id]?.projectId != projectID {
                        report(.project, id.rawValue)
                    }
                }
                for workspace in state.workspaceById.values where workspace.projectId == projectID && !seen.contains(workspace.id) {
                    report(.project, workspace.id.rawValue)
                }
            }
            var active = Set<WorkspaceId>()
            for (id, viewport) in state.monitorViewportsById {
                if id != viewport.id { report(.viewport, String(describing: id)) }
                if let workspace = viewport.activeWorkspaceId {
                    if state.workspaceById[workspace] == nil { report(.viewport, workspace.rawValue) }
                    if !active.insert(workspace).inserted { report(.duplicateActiveWorkspace, workspace.rawValue) }
                }
            }
            var nodes = Set<ObjectIdentifier>(), windows = Set<ObjectIdentifier>(), ids = Set<UInt32>()
            func walk(_ node: TreeNode) {
                guard nodes.insert(ObjectIdentifier(node)).inserted else {
                    report(.duplicateNode, String(describing: ObjectIdentifier(node))); return
                }
                if let window = node as? Window {
                    windows.insert(ObjectIdentifier(window))
                    if !ids.insert(window.windowId).inserted { report(.duplicateWindowID, String(window.windowId)) }
                }
                for child in node.children {
                    if child.parent !== node { report(.parent, String(describing: ObjectIdentifier(child))) }
                    walk(child)
                }
            }
            for workspace in state.workspaceById.values { walk(workspace) }
            walk(macosMinimizedWindowsContainer)
            walk(macosPopupWindowsContainer)
            let expectedWindows = expectedWindows ?? (isUnitTest ? nil : Array(MacWindow.allWindowsMap.values).filter(\.isBound))
            if let expectedWindows {
                for window in expectedWindows where !windows.contains(ObjectIdentifier(window)) {
                    report(.missingWindow, String(window.windowId))
                }
            }
            return result.sorted { ($0.kind.rawValue, $0.identity) < ($1.kind.rawValue, $1.identity) }
        }
    }
}
