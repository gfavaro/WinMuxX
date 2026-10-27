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
    /// For `doctor`: what the last restore did.
    private(set) var lastRestore = "none yet"
    var count: Int { entries.count }
    private let answerTimeout: Duration = .seconds(2)

    func recordBeforeWrite(_ window: MacWindow) {
        guard runtime.workspaceBackend.kind == .native, entries[window.windowId] == nil,
              TrayMenuModel.shared.isEnabled, let frame = windowServerFrame(window.windowId) else { return }
        entries[window.windowId] = Entry(pid: window.macApp.pid, frame: frame, workspaceName: window.nodeWorkspace?.name)
    }

    /// Stops tiling with `stopTiling`, then puts back tiled windows still on the desktop
    /// they started on while it shows. Each write runs under a lease taken while tiling
    /// still granted it, which keeps checking that the window is where it was. A window on
    /// a hidden desktop keeps its entry for a later restore: reaching it would take a
    /// desktop switch.
    func restore(stoppingTiling stopTiling: () -> Void) async {
        guard config.nativeSpaces.restoreFramesOnQuit else {
            stopTiling()
            lastRestore = "off (restore-frames-on-quit = false)"
            return
        }
        let candidates = entries.compactMap { id, entry -> (id: UInt32, frame: CGRect)? in
            guard let window = MacWindow.allWindowsMap[id] else { entries[id] = nil; return nil }
            guard window.macApp.pid == entry.pid, window.parent is TilingContainer, // Floating ones were placed by the user.
                  let workspace = window.nodeWorkspace, workspace.name == entry.workspaceName, workspace.isVisible else { return nil }
            return (id, entry.frame)
        }
        // Any AX event revokes grants until the next read; wait briefly for one.
        func granted(_ id: UInt32) -> Bool { MacWindow.allWindowsMap[id]?.macApp.hasNativeWriteGrant(id) == true }
        if !candidates.allSatisfy({ granted($0.id) }) {
            runtime.workspaceBackend.observation?.requestRead(event: "nativeRestoreFrames")
            let deadline = ContinuousClock.now + .milliseconds(1500)
            while ContinuousClock.now < deadline, !candidates.allSatisfy({ granted($0.id) }) {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        let leased = candidates.compactMap { candidate -> (id: UInt32, frame: CGRect, validate: @Sendable (AXUIElement) throws -> Void)? in
            guard granted(candidate.id), let validate = MacWindow.allWindowsMap[candidate.id]?.macApp.nativeLeaseValidation(candidate.id) else { return nil }
            return (candidate.id, candidate.frame, validate)
        }
        stopTiling()
        // All at once, each app on its own thread, so one slow app cannot hold up the rest.
        let writes = leased.map { item in
            Task { @MainActor () -> UInt32? in
                guard let app = MacWindow.allWindowsMap[item.id]?.macApp else { return nil }
                do {
                    try await app.setAxFrameBlocking(item.id, item.frame.origin, item.frame.size, positionFirst: true, validation: item.validate)
                    return item.id
                } catch {
                    NSLog("WinMuxX native restore of window %u: %@", item.id, String(describing: error))
                    return nil
                }
            }
        }
        let timeout = answerTimeout
        let deadline = Task { try? await Task.sleep(for: timeout); writes.forEach { $0.cancel() } }
        var restored: [UInt32] = []
        for write in writes { if let id = await write.value { restored.append(id) } }
        deadline.cancel()
        for id in restored { entries[id] = nil }
        lastRestore = "\(restored.count) of \(candidates.count) on showing desktops put back (\(leased.count) granted), \(entries.count) kept"
    }
}
