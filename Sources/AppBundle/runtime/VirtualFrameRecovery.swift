import AppKit

/// Virtual mode's counterpart of `NativeFrameRecovery`. An app's own move or resize of a
/// tiled window triggers the refresh that puts it back; an app that keeps moving it is
/// left alone after `FrameRecoveryBudget.limit` tries, until its tile changes, it comes
/// to rest there or `retile` runs. Each burst of events is one try, counted once the
/// window has been still for a moment.
@MainActor
final class VirtualFrameRecovery {
    static let shared = VirtualFrameRecovery()
    private var budgets: [UInt32: FrameRecoveryBudget] = [:]
    private var pending: [UInt32: Task<Void, Never>] = [:]
    private let settleDelay: Duration = .milliseconds(150)
    var frame: (UInt32) -> CGRect? = windowServerFrame

    /// `retile` renews every window's budget.
    func reset() { budgets.removeAll() }

    /// Called for a geometry change the user did not make; false when the app has used up
    /// this tile's tries, so the caller skips the refresh.
    func shouldPutBack(_ window: Window) -> Bool {
        guard let tile = Self.tile(of: window) else { return true }
        let id = window.windowId
        pending[id]?.cancel()
        pending[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            pending[id] = nil
            settled(id)
        }
        return budgets[id]?.isExhausted(on: tile) != true
    }

    func settled(_ id: UInt32) {
        guard let window = Window.get(byId: id), let tile = Self.tile(of: window) else { budgets[id] = nil; return }
        guard !WindowMotion.shared.isAnimating(id), let frame = frame(id) else { return }
        _ = budgets[id, default: FrameRecoveryBudget()].shouldReapply(tile: tile, resting: windowRestsOnTile(frame, tile: tile))
    }

    private static func tile(of window: Window) -> Rect? {
        guard window.parent is TilingContainer, !window.isFullscreen, !window.isConcealedByScrolling, !window.isHiddenInCorner,
              window.nodeWorkspace?.isVisible == true, window.nodeWorkspace?.scrollingGestureMotionActive != true else { return nil }
        return window.lastAppliedLayoutPhysicalRect
    }
}
