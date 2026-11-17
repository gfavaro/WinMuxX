import AppKit
import Common

/// Three-finger left/right in a Scrolling workspace pans its strip, adapted from StripMuxX.
/// The strip follows the fingers; on release focus goes to the column nearest the middle.
/// Anywhere else the swipe stays with macOS.
@MainActor
final class DockScrollingSwipeReceiver: DockSwipeReceiver {
    private weak var workspace: Workspace?
    private var sign: CGFloat = 1
    private var progress = 0.0
    private var direction: CGFloat = 0
    private var startingColumn: ObjectIdentifier?

    /// The Scrolling workspace under the pointer, when there is a strip to pan.
    private func target() -> Workspace? {
        guard workspaceSwipeGestureEnabled, isWinMuxRuntimeReady, TrayMenuModel.shared.isEnabled,
              !WindowBorderController.shared.isMissionControlActive,
              !isMouseManipulationActive, !isLeftMouseButtonDown,
              let monitor = sortedMonitors.first(where: { $0.rect.contains(mouseLocation) }),
              !shouldSuppressChromeForFullscreenContent(on: monitor) else { return nil }
        let workspace = monitor.activeWorkspace
        guard workspace.arrangement == .scrolling, workspace.scrollingColumns.count > 1 else { return nil }
        return workspace
    }

    func dockSwipeMayStart() -> DockSwipeStart {
        target() == nil ? .unavailable : .started
    }

    /// Positive progress is the fingers moving left, which brings the columns on the right in.
    func dockSwipeBegan(positive: Bool, progress: Double, timestamp: Double) -> DockSwipeStart {
        guard let workspace = target() else { return .unavailable }
        self.workspace = workspace
        sign = positive ? 1 : -1
        self.progress = 0
        direction = 0
        let metrics = workspace.scrollingMetrics
        startingColumn = nearestScrollingColumn(in: metrics, offset: workspace.scrollingOffset, direction: 0)
            .map { ObjectIdentifier($0.node) }
        workspace.scrollingGestureSessionID = UUID()
        workspace.scrollingGestureMotionActive = true
        dockSwipeChanged(progress, timestamp: timestamp)
        return .started
    }

    func dockSwipeChanged(_ progress: Double, timestamp: Double) {
        guard let workspace, workspace.isVisible, workspace.arrangement == .scrolling else { return }
        let next = max(0, min(1, progress))
        let delta = CGFloat(next - self.progress) * sign
        self.progress = next
        guard abs(delta) > 0.00001 else { return }
        let metrics = workspace.scrollingMetrics
        let offset = metrics.clampedOffset(workspace.scrollingOffset + delta * metrics.areaWidth)
        guard abs(offset - workspace.scrollingOffset) > 0.0001 else { return }
        direction = offset > workspace.scrollingOffset ? 1 : -1
        workspace.scrollingOffset = offset
        // The strip moves without focus, so the layout must not scroll it back to the focus.
        workspace.lastScrollingFocusWindowId = focus.windowOrNil?.windowId
        WorkspaceScrollingMinimap.shared.show(workspace, duringGesture: true)
        scheduleRefreshSession(.globalObserver("scrollingSwipe"))
    }

    func dockSwipeEnded(commit: Bool, progress: Double, velocity: Double, timestamp: Double) {
        defer { workspace = nil; startingColumn = nil }
        // The settle after the fingers lift glides as any layout does.
        workspace?.scrollingGestureMotionActive = false
        workspace?.scrollingGestureSessionID = nil
        WorkspaceScrollingMinimap.shared.endGesture()
        guard commit, let workspace, workspace.isVisible, workspace.arrangement == .scrolling else {
            scheduleRefreshSession(.globalObserver("scrollingSwipeCancelled"))
            return
        }
        let metrics = workspace.scrollingMetrics
        guard let column = settledDockSwipeColumn(in: metrics, offset: workspace.scrollingOffset, direction: direction,
                                                  startingColumnID: startingColumn, advanceIfStuck: true),
              let window = column.node.mostRecentWindowRecursive else { return }
        // Focusing the column scrolls the strip to show it whole.
        workspace.lastScrollingFocusWindowId = nil
        _ = window.focusWindow()
        scheduleRefreshSession(.globalObserver("scrollingSwipeEnded"))
    }
}
