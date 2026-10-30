import AppKit

/// Virtual mode's counterpart of `NativeFrameRecovery`. An app's own move or resize of a
/// tiled window is put back once the window has been still for a moment, within the
/// window's `FrameRecoveryBudget`. Deciding only once the window is still is what lets a
/// fight be counted: putting it back at once kept the events coming forever.
@MainActor
final class VirtualFrameRecovery {
    static let shared = VirtualFrameRecovery()
    private var budgets: [UInt32: FrameRecoveryBudget] = [:]
    private var pending: [UInt32: Task<Void, Never>] = [:]
    private let settleDelay: Duration = .milliseconds(150)
    var frame: (UInt32) -> CGRect? = windowServerFrame

    /// `retile` renews every window's budget.
    func reset() { budgets.removeAll() }

    func leavesAlone(_ id: UInt32, tile: Rect) -> Bool { budgets[id]?.isExhausted(on: tile) == true }

    /// A geometry change the user did not make. Windows without a tile refresh at once, as
    /// before; a tiled one is checked once it is still.
    func windowChanged(_ window: Window, putBack: @escaping @MainActor () -> Void) {
        guard Self.tile(of: window) != nil else { return putBack() }
        let id = window.windowId
        pending[id]?.cancel()
        pending[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            pending[id] = nil
            settled(id, putBack: putBack)
        }
    }

    func settled(_ id: UInt32, putBack: () -> Void) {
        guard let window = Window.get(byId: id), let tile = Self.tile(of: window) else {
            budgets[id] = nil
            return putBack()
        }
        // An animation ends on the tile by itself.
        guard !WindowMotion.shared.isAnimating(id) else { return }
        guard let frame = frame(id) else { return putBack() }
        if budgets[id, default: FrameRecoveryBudget()].shouldReapply(tile: tile, resting: windowRestsOnTile(frame, tile: tile)) { putBack() }
    }

    private static func tile(of window: Window) -> Rect? {
        guard window.parent is TilingContainer, !window.isFullscreen, !window.isConcealedByScrolling, !window.isHiddenInCorner,
              window.nodeWorkspace?.isVisible == true, window.nodeWorkspace?.scrollingGestureMotionActive != true else { return nil }
        return window.lastAppliedLayoutPhysicalRect
    }
}
