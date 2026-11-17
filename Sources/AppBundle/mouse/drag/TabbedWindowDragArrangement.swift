import AppKit

/// The Tabbed arrangement's drag stages, still in their old places behind the interface. Their
/// code moves here stage by stage; until then this only forwards.
@MainActor
final class TabbedWindowDragArrangement: WindowDragArrangement {
    static let shared = TabbedWindowDragArrangement()
    private init() {}

    func surfaceDestination(
        sourceWindow: Window,
        mouseLocation: CGPoint,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
    ) -> WindowDragIntentDestination? {
        // The window shown by the tab group under the pointer, its bar included.
        let workspace = mouseLocation.monitorApproximation.activeWorkspace
        guard let target = workspace.tabbedGroups.first(where: { $0.lastFrame?.contains(mouseLocation) == true })?.displayedWindow
        else { return nil }
        return tabbedWindowSurfaceDestination(in: workspace, sourceWindow: sourceWindow, targetWindow: target,
                                              mouseLocation: mouseLocation, subject: subject, detachOrigin: detachOrigin)
    }

    func windowDestination(
        sourceWindow: Window,
        targetWindow: Window,
        mouseLocation: CGPoint,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
    ) -> WindowDragIntentDestination? {
        guard let workspace = targetWindow.nodeWorkspace else { return nil }
        return tabbedWindowSurfaceDestination(in: workspace, sourceWindow: sourceWindow, targetWindow: targetWindow,
                                              mouseLocation: mouseLocation, subject: subject, detachOrigin: detachOrigin)
    }

    func dropIntentDestination(
        resolution: WindowDropIntentResolution,
        sourceWindow: Window,
        targetWindow: Window,
        mouseLocation: CGPoint,
        subject: WindowDragSubject,
        detachOrigin: TabDetachOrigin,
    ) -> WindowDragIntentDestination? {
        // A drop on a Tabbed workspace's window lands in its tab groups, which are kept apart from
        // the tree, so the tree's own containers have no say.
        let source = targetWindow.nodeWorkspace?.tabbedGroup(containing: sourceWindow.windowId)
        return tabbedGroupDropDestination(resolution, source: source, sourceWindow: sourceWindow, targetWindow: targetWindow,
                                          subject: subject)
    }

    func updateBarDropPreview(sourceWindowId: UInt32, destination: WindowDragIntentDestination) -> Bool {
        updateTabbedBarDropPreview(sourceWindowId: sourceWindowId, destination: destination)
    }

    func applyDrop(kind: WindowDragIntentKind, sourceWindow: Window, subject: WindowDragSubject) -> Bool? {
        applyTabbedGroupDragIntent(kind, sourceWindow: sourceWindow, subject: subject)
    }
}
