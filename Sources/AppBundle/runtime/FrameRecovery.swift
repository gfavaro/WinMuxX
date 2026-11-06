import AppKit

/// An app's own move or resize of a tiled window is put back once the window has been
/// still for a moment, within the window's `FrameRecoveryBudget`. Deciding only once the window is still is what lets a
/// fight be counted: putting it back at once kept the events coming forever.
@MainActor
final class FrameRecovery {
    static let shared = FrameRecovery()
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
        guard window.parent is TilingContainer, !window.isFullscreen, !window.isHiddenInCorner,
              window.nodeWorkspace?.isVisible == true else { return nil }
        return window.lastAppliedLayoutPhysicalRect
    }
}

/// How often a window that will not stay on its tile is put back: at most `limit` times
/// within `window` on the same tile, so an app that keeps moving its window is left alone
/// instead of fought forever, however quickly or slowly it moves it back, while one that
/// moves it now and then is always put back. A new tile starts over; ineligible moves
/// (drags, our own writes and animations) are never counted. After Dinky's FrameRecovery,
/// which refilled on rest: an app slower than the settle delay then never ran out.
struct FrameRecoveryBudget {
    private var tile: Rect?
    private var attempts: [ContinuousClock.Instant] = []
    static let limit = 3
    static let window: Duration = .seconds(10)

    mutating func shouldReapply(tile: Rect, resting: Bool, now: ContinuousClock.Instant = .now) -> Bool {
        if self.tile != tile {
            self.tile = tile
            attempts = []
        }
        attempts.removeAll { now - $0 >= Self.window }
        guard !resting, attempts.count < Self.limit else { return false }
        attempts.append(now)
        return true
    }

    /// Whether this tile's tries are used up, so layout leaves the window where its app put it.
    func isExhausted(on tile: Rect, now: ContinuousClock.Instant = .now) -> Bool {
        self.tile == tile && attempts.count(where: { now - $0 < Self.window }) >= Self.limit
    }
}

/// A window whose app keeps moving it off this tile stays where its app put it: without
/// this, any other refresh's layout pass put it back and the fight went on.
@MainActor
func frameRecoveryLeavesAlone(_ window: Window, tile: Rect) -> Bool {
    FrameRecovery.shared.leavesAlone(window.windowId, tile: tile)
}

/// Whether a window sits on its tile. Apps that cannot shrink to it stay larger, and
/// terminals size in whole rows and columns, so only a moved origin or a window clearly
/// smaller than its tile counts as off it.
func windowRestsOnTile(_ frame: CGRect, tile: Rect) -> Bool {
    abs(frame.minX - tile.topLeftX) <= 4 && abs(frame.minY - tile.topLeftY) <= 4 &&
        frame.width >= tile.width - 24 && frame.height >= tile.height - 24
}

/// Where WindowServer has the window, top-left origin, without asking its app.
func windowServerFrame(_ id: UInt32) -> CGRect? {
    guard let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(id)) as? [[String: Any]],
          let bounds = rows.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: bounds)
}
