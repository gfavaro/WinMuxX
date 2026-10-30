import AppKit

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
    NativeFrameRecovery.shared.leavesAlone(window.windowId, tile: tile) || VirtualFrameRecovery.shared.leavesAlone(window.windowId, tile: tile)
}

/// Whether a window sits on its tile. Apps that cannot shrink to it stay larger, and
/// terminals size in whole rows and columns, so only a moved origin or a window clearly
/// smaller than its tile counts as off it.
func windowRestsOnTile(_ frame: CGRect, tile: Rect) -> Bool {
    abs(frame.minX - tile.topLeftX) <= 4 && abs(frame.minY - tile.topLeftY) <= 4 &&
        frame.width >= tile.width - 24 && frame.height >= tile.height - 24
}

/// Puts a tiled window back on its tile when its app moved or resized it on its own after
/// native tiling placed it. Without this the window stayed where the app put it until the
/// next layout change. Checks once the window has been still for a moment, so a stream of
/// move events costs one check.
@MainActor
final class NativeFrameRecovery {
    static let shared = NativeFrameRecovery()
    private var budgets: [UInt32: FrameRecoveryBudget] = [:]
    private var pending: [UInt32: Task<Void, Never>] = [:]
    private let settleDelay: Duration = .milliseconds(150)

    /// `retile` renews every window's budget.
    func reset() { budgets.removeAll() }

    func leavesAlone(_ id: UInt32, tile: Rect) -> Bool { budgets[id]?.isExhausted(on: tile) == true }

    func windowChanged(_ window: Window) {
        let id = window.windowId
        pending[id]?.cancel()
        pending[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            pending[id] = nil
            check(id)
        }
    }

    private func check(_ id: UInt32) {
        let backend = runtime.workspaceBackend
        guard let window = Window.get(byId: id), window.parent is TilingContainer,
              let workspace = window.nodeWorkspace, workspace.isVisible,
              let tile = window.lastAppliedLayoutPhysicalRect else { budgets[id] = nil; return }
        // Our own writes and pans, the user's drags and a layout in progress are not the app's doing.
        guard backend.native.tilingEnabled, backend.native.tiling.ready, TrayMenuModel.shared.isEnabled,
              NSEvent.pressedMouseButtons == 0, !NativeScrollingPan.shared.isPanning,
              !WindowMotion.shared.isAnimating(id), let frame = windowServerFrame(id) else { return }
        guard budgets[id, default: FrameRecoveryBudget()].shouldReapply(tile: tile, resting: windowRestsOnTile(frame, tile: tile)) else { return }
        backend.native.observation?.requestRead(event: "nativeAppMovedWindow")
    }
}

/// Where WindowServer has the window, top-left origin, without asking its app.
func windowServerFrame(_ id: UInt32) -> CGRect? {
    guard let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(id)) as? [[String: Any]],
          let bounds = rows.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: bounds)
}
