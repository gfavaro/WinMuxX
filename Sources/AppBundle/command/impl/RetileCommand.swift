import AppKit
import Common

/// Counts the tiled windows on showing workspaces that are off their tiles, then lets
/// the layout pass that follows every command put them back (in native mode, the read
/// native tiling requests once a command completes). Each mode's put-back budget is
/// renewed, so windows it had given up on are tried again.
struct RetileCommand: Command {
    let args: RetileCmdArgs
    let shouldResetClosedWindowsCache = false
    /// Where WindowServer has a window; tests replace it.
    @MainActor static var frame: (UInt32) -> CGRect? = windowServerFrame

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let candidates = retileCandidates(frame: Self.frame)
        // A command's layout pass skips windows whose tile did not change; these are off it.
        for window in candidates { window.lastAppliedLayoutPhysicalRect = nil }
        let moved = candidates.count
        NativeFrameRecovery.shared.reset()
        VirtualFrameRecovery.shared.reset()
        let message = moved == 0 ? "Nothing had moved" : "Put \(moved) \(moved == 1 ? "window" : "windows") back"
        NoticePanel.shared.show(title: "Retile", body: message, seconds: 1.5)
        return io.out(message)
    }
}

/// Tiled windows on showing workspaces that do not rest on their tiles.
@MainActor
func retileCandidates(frame: (UInt32) -> CGRect?) -> [Window] {
    Workspace.all.filter(\.isVisible).flatMap(\.allLeafWindowsRecursive).filter { window in
        guard window.parent is TilingContainer, !window.isFullscreen, !window.isConcealedByScrolling,
              let tile = window.lastAppliedLayoutPhysicalRect, let actual = frame(window.windowId) else { return false }
        return !windowRestsOnTile(actual, tile: tile)
    }
}
