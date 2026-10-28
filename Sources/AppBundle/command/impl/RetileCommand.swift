import AppKit
import Common

/// Counts the tiled windows on showing workspaces that are off their tiles, then lets
/// the layout pass that follows every command put them back. Native mode also gets
/// its put-back budget renewed, so windows it had given up on are tried again.
struct RetileCommand: Command {
    let args: RetileCmdArgs
    let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let moved = retileCandidates(frame: windowServerFrame).count
        NativeFrameRecovery.shared.reset()
        let message = moved == 0 ? "Nothing had moved" : "Put \(moved) \(moved == 1 ? "window" : "windows") back"
        if runtime.workspaceBackend.kind == .native { runtime.workspaceBackend.native.observation?.requestRead(event: "retile") }
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
