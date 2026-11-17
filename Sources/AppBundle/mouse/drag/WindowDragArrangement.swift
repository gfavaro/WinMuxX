import AppKit

/// The three drag stages a workspace arrangement can own: where a drop on its windows lands,
/// what is shown while it hovers, and how the drop is applied. The workspace under the pointer,
/// or the one a drop lands in, picks the implementation; Dwindle, Master and Scrolling all drop
/// through the tree and share the tree's implementation.
@MainActor
protocol WindowDragArrangement: AnyObject {
    /// Where a drop on this arrangement's surface lands, or nil when the pointer is not over a
    /// place this arrangement accepts. Only asked when the workspace under the pointer is this
    /// arrangement's.
    func surfaceDestination(
        sourceWindow: Window,
        mouseLocation: CGPoint,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
    ) -> WindowDragIntentDestination?

    /// Where a drop on `targetWindow`, one of this arrangement's windows, lands.
    func windowDestination(
        sourceWindow: Window,
        targetWindow: Window,
        mouseLocation: CGPoint,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
    ) -> WindowDragIntentDestination?

    /// Where a resolved drop zone on this arrangement's window lands, before the drop's overlay
    /// is laid over it.
    func dropIntentDestination(
        resolution: WindowDropIntentResolution,
        sourceWindow: Window,
        targetWindow: Window,
        mouseLocation: CGPoint,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
    ) -> WindowDragIntentDestination?

    /// Shows the hover preview a drop on this arrangement's bar would make. False when this
    /// arrangement shows no bar preview, and the shared tab reentry preview runs.
    func updateBarDropPreview(sourceWindowId: UInt32, destination: WindowDragIntentDestination) -> Bool

    /// Applies a drop. Nil when the drop is not this arrangement's, and the tree's apply should
    /// run; true or false once the drop has been applied or refused.
    func applyDrop(kind: WindowDragIntentKind, sourceWindow: Window, subject: WindowDragSubject) -> Bool?
}

/// The workspace under the pointer, or the one a drop lands in, picks the drag implementation.
@MainActor
func windowDragArrangement(for workspace: Workspace?) -> WindowDragArrangement {
    if workspace?.arrangement == .tabbed { return TabbedWindowDragArrangement.shared }
    return TreeWindowDragArrangement.shared
}

/// The arrangement a drop `kind` applies to: the workspace of the window the kind names.
@MainActor
func windowDragArrangement(for kind: WindowDragIntentKind) -> WindowDragArrangement {
    let targetWindowId: UInt32? = switch kind {
        case .tabStack(let id), .insertTab(let id, _), .stackSplit(let id, _), .swap(let id),
             .reorderTab(let id, _), .detachTab(let id):
            id
        case .moveToWorkspace, .moveToWorkspaceZone, .createWorkspace, .sidebarHover, .unavailable:
            nil
    }
    return windowDragArrangement(for: targetWindowId.flatMap { Window.get(byId: $0)?.nodeWorkspace })
}
