import AppKit

/// Where each native window was before native tiling first moved it, so quitting or
/// `enable off` can put it back. In memory only: it never touches the virtual recovery
/// journal, and after a crash the next launch's layout restore takes over. After
/// Dinky's Recovery.
@MainActor
final class NativeOriginalFrames {
    static let shared = NativeOriginalFrames()
    private struct Entry {
        let pid: pid_t
        let frame: CGRect
        let workspaceName: String?
    }
    private var entries: [UInt32: Entry] = [:]
    private let answerTimeout: Duration = .seconds(2)

    func recordBeforeWrite(_ window: MacWindow) {
        guard runtime.workspaceBackend.kind == .native, entries[window.windowId] == nil,
              TrayMenuModel.shared.isEnabled, let frame = windowServerFrame(window.windowId) else { return }
        entries[window.windowId] = Entry(pid: window.macApp.pid, frame: frame, workspaceName: window.nodeWorkspace?.name)
    }

    /// Puts back tiled windows still on the desktop they started on while it shows. A
    /// window on a hidden desktop keeps its entry for a later restore: reaching it would
    /// take a desktop switch. Returns how many went back and how many were left.
    @discardableResult
    func restore() async -> (restored: Int, left: Int) {
        guard config.nativeSpaces.restoreFramesOnQuit else { return (0, entries.count) }
        let candidates = entries.compactMap { id, entry -> (id: UInt32, frame: CGRect)? in
            guard let window = MacWindow.allWindowsMap[id] else { entries[id] = nil; return nil }
            guard window.macApp.pid == entry.pid, window.parent is TilingContainer,
                  let workspace = window.nodeWorkspace, workspace.name == entry.workspaceName, workspace.isVisible else { return nil }
            return (id, entry.frame)
        }
        // All at once, each app on its own thread, so one slow app cannot hold up the rest.
        let writes = candidates.map { candidate in
            Task { @MainActor () -> UInt32? in
                guard let window = MacWindow.allWindowsMap[candidate.id] else { return nil }
                do {
                    try await window.setAxFrameBlocking(candidate.frame.origin, candidate.frame.size, positionFirst: true)
                    return candidate.id
                } catch { return nil }
            }
        }
        let timeout = answerTimeout
        let deadline = Task { try? await Task.sleep(for: timeout); writes.forEach { $0.cancel() } }
        var restored: [UInt32] = []
        for write in writes { if let id = await write.value { restored.append(id) } }
        deadline.cancel()
        for id in restored { entries[id] = nil }
        return (restored.count, entries.count)
    }
}
