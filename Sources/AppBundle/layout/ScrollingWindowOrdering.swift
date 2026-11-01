import AppKit
import Common

struct ScrollingStackItem: Equatable {
    let id: UInt32
    let frame: CGRect
}

/// Raise only the front prefix needed to put overlapping windows in the desired
/// order. Nonoverlapping tiles never need native ordering. Inputs are back to
/// front; Core Graphics reports current order front to back.
func scrollingWindowRaises(desired: [ScrollingStackItem], currentFrontToBack: [UInt32]) -> [UInt32] {
    let front = Array(desired.reversed())
    let positions = Dictionary(currentFrontToBack.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    let count = (0...front.count).first { prefix in
        for i in prefix..<front.count {
            for j in (i + 1)..<front.count where front[i].frame.intersects(front[j].frame) {
                guard let above = positions[front[i].id], let below = positions[front[j].id], above < below else { return false }
            }
        }
        return true
    } ?? front.count
    return front.prefix(count).reversed().map(\.id)
}

@MainActor
final class ScrollingWindowOrdering {
    static let shared = ScrollingWindowOrdering()
    private struct Signature: Equatable {
        let workspace: ObjectIdentifier
        let epoch: UInt64
        let groups: [ObjectIdentifier]
        let visibility: [ScrollingColumnVisibility?]
        let windows: [UInt32]
        let focus: UInt32?
    }
    private var signature: Signature?
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        signature = nil
    }

    func update(workspace: Workspace, frames: [WorkspaceGroupFrame]) {
        guard !isUnitTest, !serverArgs.isReadOnly, TrayMenuModel.shared.isEnabled,
              !WindowRecoveryController.shared.isTerminating,
              workspace.isVisible, workspace.arrangement == .scrolling else { return }
        let items = frames.sorted { $0.stackingIndex < $1.stackingIndex }.flatMap { group in
            group.node.allLeafWindowsRecursive.filter { !$0.isHiddenInCorner }.compactMap { window -> ScrollingStackItem? in
                guard let rect = window.lastAppliedLayoutPhysicalRect else { return nil }
                return .init(id: window.windowId, frame: CGRect(origin: rect.topLeftCorner, size: rect.size))
            }
        }
        let next = Signature(workspace: ObjectIdentifier(workspace), epoch: workspace.scrollingSessionEpoch,
            groups: frames.map { ObjectIdentifier($0.node) }, visibility: frames.map(\.visibility),
            windows: items.map(\.id), focus: focus.windowOrNil?.windowId)
        guard signature != next else { return }
        cancel()
        signature = next
        let expectedGeneration = generation
        let expectedFocus = captureRequestedFocus()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let current = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []).compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
        var raises = scrollingWindowRaises(desired: items, currentFrontToBack: current)
        // AXRaise may change an app's key window even without activation. Restore
        // its actual focused window last if any sibling in that app is raised.
        if let focused = focus.windowOrNil, focused.app.pid == frontmostPID,
           raises.contains(where: { Window.get(byId: $0)?.app.pid == frontmostPID }),
           items.contains(where: { $0.id == focused.windowId }) {
            raises.removeAll { $0 == focused.windowId }
            raises.append(focused.windowId)
        }
        task = Task { @MainActor [weak self, weak workspace] in
            for id in raises {
                guard let self, let workspace, !Task.isCancelled, self.generation == expectedGeneration,
                      workspace.scrollingSessionEpoch == next.epoch, workspace.arrangement == .scrolling,
                      workspace.isVisible, captureRequestedFocus() == expectedFocus,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID,
                      let window = Window.get(byId: id) as? MacWindow, window.nodeWorkspace === workspace else { return }
                do { try await window.macApp.raiseWithoutActivating(id) } catch { return }
            }
            if let self, self.generation == expectedGeneration { self.task = nil }
        }
    }
}
