import AppKit
import Common

/// Rest the pointer on a tab group's pill rail and its full strip opens over the top of the
/// window; it closes shortly after the pointer leaves the strip. Pointer moves only compare
/// the published strip frames.
@MainActor
final class WindowTabRailHover {
    static let shared = WindowTabRailHover()
    static let dwell: Duration = .milliseconds(200)
    static let linger: Duration = .milliseconds(300)
    /// Reaching a little past the rail, so the gap above it and its bottom edge count.
    static let slack: CGFloat = 3
    private var pending: (id: ObjectIdentifier, task: Task<Void, Never>)?
    private var closing: Task<Void, Never>?

    /// The rail along the group's top edge, in top-left coordinates.
    static func railZone(groupFrame: CGRect, railHeight: CGFloat) -> CGRect {
        let top = mainMonitor.height - groupFrame.maxY
        return CGRect(x: groupFrame.minX, y: top - slack, width: groupFrame.width, height: railHeight + 2 * slack)
    }

    /// The open strip, which keeps itself open while the pointer is on it.
    static func stripZone(stripFrame: CGRect) -> CGRect {
        CGRect(x: stripFrame.minX, y: mainMonitor.height - stripFrame.maxY, width: stripFrame.width, height: stripFrame.height)
            .insetBy(dx: -slack, dy: -slack)
    }

    func pointerMoved(_ point: CGPoint) {
        let controller = WindowTabStripPanelController.shared
        let strips = TrayMenuModel.shared.windowTabStrips
        if let open = controller.hoverExpandedId {
            if let strip = strips.first(where: { $0.id == open }), Self.stripZone(stripFrame: strip.frame).contains(point) {
                cancelClosing()
                return
            }
            if !isLeftMouseButtonDown, !isWindowTabStripDragInProgress() { scheduleClose() }
        }
        guard config.windowTabs.enabled, TrayMenuModel.shared.isEnabled, !isLeftMouseButtonDown, !isMouseManipulationActive,
              let strip = strips.first(where: { Self.railZone(groupFrame: $0.groupFrame, railHeight: $0.railHeight).contains(point) })
        else { return cancelPending() }
        if strip.id == controller.hoverExpandedId || pending?.id == strip.id { return }
        cancelPending()
        let id = strip.id
        pending = (id, Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.dwell)
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            self.cancelClosing()
            controller.setHoverExpanded(id)
        })
    }

    private func scheduleClose() {
        guard closing == nil else { return }
        closing = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.linger)
            guard let self, !Task.isCancelled else { return }
            self.closing = nil
            WindowTabStripPanelController.shared.setHoverExpanded(nil)
        }
    }

    private func cancelClosing() {
        closing?.cancel()
        closing = nil
    }

    private func cancelPending() {
        pending?.task.cancel()
        pending = nil
    }
}
