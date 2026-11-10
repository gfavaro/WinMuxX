import AppKit
import Common

/// Rest the pointer on a tiled window's top edge and a bar offers Main (in Master), Focus
/// and Float for that window where the pointer is, so they need no shortcut. Pointer
/// moves only compare cached layout frames; which window is really on top is checked
/// once the pointer has rested. Each button runs the ordinary command for that window.
@MainActor
final class WindowHoverBar {
    static let shared = WindowHoverBar()
    /// A thin band on the window's top edge: the whole title bar summoned the bar too readily.
    static let zoneHeight: CGFloat = 8
    /// How far the band reaches above the edge, so resting on the border itself counts.
    static let zoneAboveEdge: CGFloat = 3
    static let dwell: Duration = .milliseconds(350)
    private var pending: (windowId: UInt32, task: Task<Void, Never>)?
    private var shown: UInt32?
    private lazy var panel = HoverBarPanel()

    /// The band along a window's top edge that summons the bar: all of it but the corners,
    /// which hold the window buttons and resize handles (80 pt each, a quarter on narrow windows).
    static func triggerZone(for frame: Rect) -> Rect {
        let corner = min(80, frame.width / 4)
        return Rect(topLeftX: frame.minX + corner, topLeftY: frame.minY - zoneAboveEdge, width: frame.width - 2 * corner, height: zoneHeight)
    }

    /// The bar's place: centred on the pointer along the window's top edge, just inside the
    /// window, and kept within it.
    static func barFrame(for frame: Rect, size: CGSize, pointerX: CGFloat) -> Rect {
        let inset: CGFloat = 4
        let lowest = frame.minX + inset, highest = max(lowest, frame.maxX - inset - size.width)
        let x = min(max(pointerX - size.width / 2, lowest), highest)
        return Rect(topLeftX: x, topLeftY: frame.minY + inset, width: size.width, height: size.height)
    }

    /// Where the window is: a focused (fullscreen) window has no tile, only the screen it
    /// fills, and a floating one only where WindowServer has it (no cached frame follows it).
    static func frame(of window: Window, liveFrame: (UInt32) -> CGRect? = windowServerFrame) -> Rect? {
        if window.parent is Workspace {
            return liveFrame(window.windowId).map { Rect(topLeftX: $0.minX, topLeftY: $0.minY, width: $0.width, height: $0.height) }
        }
        return window.isFullscreen ? window.lastAppliedLayoutVirtualRect : window.lastAppliedLayoutPhysicalRect
    }

    /// The actions offered for a window. `shortcut` is the plain command a binding would run,
    /// so the bar can print its configured keys.
    static func actions(for window: Window) -> [HoverBarAction] {
        let id = window.windowId
        if window.isFullscreen {
            return [HoverBarAction(title: "Unfocus", symbol: "arrow.down.right.and.arrow.up.left", command: "fullscreen off --window-id \(id)", shortcut: "fullscreen")]
        }
        if window.parent is Workspace {
            return [HoverBarAction(title: "Tile", symbol: "rectangle.split.2x1", command: "layout tiling --window-id \(id)", shortcut: "layout floating tiling")]
        }
        var actions: [HoverBarAction] = []
        if window.nodeWorkspace?.arrangement == .master {
            actions.append(HoverBarAction(title: "Main", symbol: "rectangle.lefthalf.inset.filled", command: "swap-with-master --window-id \(id)", shortcut: "swap-with-master"))
        }
        actions.append(HoverBarAction(title: "Focus", symbol: "arrow.up.left.and.arrow.down.right", command: "fullscreen --window-id \(id)", shortcut: "fullscreen"))
        actions.append(HoverBarAction(title: "Float", symbol: "macwindow.on.rectangle", command: "layout floating tiling --window-id \(id)", shortcut: "layout floating tiling"))
        return actions
    }

    /// The configured keys for an action in the current mode, as macOS menus print them.
    static func shortcutHint(for action: HoverBarAction) -> String? {
        guard case .cmd(let command) = parseCommand(action.shortcut) else { return nil }
        var bindings = ActionMenuBindings(mode: activeMode.flatMap { config.modes[$0] })
        return bindings.bindings(for: command).first.map(shortcutHintText)
    }

    /// The tabs of the group a tabbed window belongs to, from the published tab models.
    static func tabs(for window: Window) -> [HoverBarTab] {
        // A tab strip already shows the tabs; only pills leave them to the bar.
        guard let group = window.nearestWindowTabGroup, group.showsWindowTabs,
              let strip = TrayMenuModel.shared.windowTabStrips.first(where: { $0.id == ObjectIdentifier(group) })
        else { return [] }
        return strip.tabs.map { tab in
            HoverBarTab(windowId: tab.windowId, title: tab.title.isEmpty ? tab.appName : tab.title,
                appBundlePath: tab.appBundlePath, isActive: tab.isActive)
        }
    }

    /// The managed window whose top-edge zone holds the point, from cached frames.
    /// Floating windows and a focused one cover the tiles beneath them, so they come first.
    static func candidate(at point: CGPoint) -> Window? {
        for workspace in Workspace.all where workspace.isVisible {
            let windows = workspace.allLeafWindowsRecursive
            let floating = workspace.floatingWindows.filter { $0.participatesInWorkspaceFocus && !$0.isHiddenInCorner }
            for window in floating + windows.filter(\.isFullscreen) + windows.filter({ !$0.isFullscreen }) {
                guard window.parent is TilingContainer || window.parent is Workspace,
                      !window.isInactiveWindowTab, let frame = frame(of: window),
                      triggerZone(for: frame).contains(point) else { continue }
                return window
            }
        }
        return nil
    }

    func pointerMoved(_ point: CGPoint) {
        // Over the bar, a press is a click on it.
        if shown != nil, panelRect.insetBy(dx: -12, dy: -12).contains(point) { return }
        guard TrayMenuModel.shared.isEnabled, !isLeftMouseButtonDown, !isMouseManipulationActive else { return hide() }
        if shown != nil { hide() }
        guard let window = Self.candidate(at: point) else { return cancelPending() }
        if pending?.windowId == window.windowId { return }
        cancelPending()
        let id = window.windowId
        pending = (id, Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.dwell)
            guard let self, !Task.isCancelled else { return }
            let now = normalizeAppKitScreenPoint(NSEvent.mouseLocation)
            let onTop = Self.candidate(at: now)?.windowId == id ? await PointerFocusNativeHitTester.shared.windowId(at: now) == id : false
            guard !Task.isCancelled else { return }
            // A failed check must not stay pending, or resting there again would never retry.
            self.pending = nil
            guard onTop, let window = Window.get(byId: id) else { return }
            self.show(for: window, pointerX: now.x)
        })
    }

    private var panelRect: CGRect {
        let frame = panel.frame
        return CGRect(x: frame.minX, y: mainMonitor.height - frame.maxY, width: frame.width, height: frame.height)
    }

    private func show(for window: Window, pointerX: CGFloat) {
        guard let frame = Self.frame(of: window) else { return }
        let id = window.windowId
        let actions = Self.actions(for: window)
        let size = panel.configure(actions, hints: actions.map(Self.shortcutHint), tabs: Self.tabs(for: window)) { [weak self] command in
            self?.hide()
            // Act as a click on the window would: focus (and raise) it first, so a window
            // floated from the bar is not left behind the tiles it came from.
            guard let token: RunSessionGuard = .isServerEnabled, case .cmd(let parsed) = parseCommand(command),
                  case .cmd(let raise) = parseCommand(["focus", "--window-id", String(id)]) else { return }
            Task { @MainActor in
                await runUnattendedLightSession(.menuBarButton, token, shouldSchedulePostRefresh: true) {
                    let result = try await [raise, parsed].runCmdSeq(.defaultEnv, .emptyStdin)
                    showShortcutFailure("Hover bar", result)
                }
            }
        }
        let bar = Self.barFrame(for: frame, size: size, pointerX: pointerX)
        panel.setFrame(CGRect(x: bar.minX, y: mainMonitor.height - bar.maxY, width: bar.width, height: bar.height), display: true)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
        shown = window.windowId
    }

    private func cancelPending() {
        pending?.task.cancel()
        pending = nil
    }

    func hide() {
        cancelPending()
        guard shown != nil else { return }
        shown = nil
        panel.orderOut(nil)
    }
}
