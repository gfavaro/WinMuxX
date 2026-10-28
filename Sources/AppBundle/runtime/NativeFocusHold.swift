import AppKit

/// A sidebar click that changes another display's desktop keeps focus where the user is.
/// macOS activates a window on the switched display; while the hold lasts that activation
/// is not adopted, so focus hooks (such as move-mouse) do not fire, and the held window is
/// brought back. A click elsewhere or the hold's expiry ends it.
@MainActor
final class NativeFocusHold {
    private struct Hold {
        let windowId: UInt32?
        let homeDisplay: String
        var until: ContinuousClock.Instant
        var restored = false
    }
    private var hold: Hold?
    var now: () -> ContinuousClock.Instant = { .now }

    /// Starts a hold for a switch in flight; `settle` bounds it once the switch lands.
    func begin(window: Window?, homeDisplay: String, timeout: Duration = .seconds(3)) {
        hold = Hold(windowId: window?.windowId, homeDisplay: homeDisplay, until: now() + timeout)
    }

    /// The switch landed; macOS activations trailing it still arrive for a moment.
    func settle(after delay: Duration = .milliseconds(500)) {
        hold?.until = now() + delay
    }

    func end() { hold = nil }

    var isActive: Bool {
        guard let hold else { return false }
        if now() < hold.until { return true }
        self.hold = nil
        return false
    }

    /// True when `window` took focus on another display during the hold: the caller skips
    /// adopting it. The held window is brought back once.
    func rejects(_ window: Window?, display: (Window) -> String?) -> Bool {
        guard isActive, let window, window.windowId != hold?.windowId,
              let home = hold?.homeDisplay, display(window) != home else { return false }
        if hold?.restored == false, let id = hold?.windowId, let held = Window.get(byId: id) {
            hold?.restored = true
            _ = held.focusWindow()
            held.nativeFocus()
        }
        return true
    }
}

@MainActor
func nativeFocusHoldRejects(_ window: Window?) -> Bool {
    runtime.workspaceBackend.nativeFocusHold.rejects(window) { $0.nodeWorkspace?.workspaceMonitor.displayUUID }
}
