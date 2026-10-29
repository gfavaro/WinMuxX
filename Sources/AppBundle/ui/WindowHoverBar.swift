import AppKit
import Common

/// Rest the pointer on the middle of a tiled window's top edge and a small bar offers
/// Main (in Master), Focus and Float for that window, so they need no shortcut. Pointer
/// moves only compare cached layout frames; which window is really on top is checked
/// once the pointer has rested. Each button runs the ordinary command for that window.
@MainActor
final class WindowHoverBar {
    static let shared = WindowHoverBar()
    static let zoneHeight: CGFloat = 8
    static let dwell: Duration = .milliseconds(350)
    private var pending: (windowId: UInt32, task: Task<Void, Never>)?
    private var shown: UInt32?
    private lazy var panel = HoverBarPanel()

    /// The band along the middle third of a window's top edge that summons the bar.
    static func triggerZone(for frame: Rect) -> Rect {
        let width = max(frame.width / 3, min(frame.width, 120))
        return Rect(topLeftX: frame.minX + (frame.width - width) / 2, topLeftY: frame.minY, width: width, height: zoneHeight)
    }

    /// The bar's place: centred on the window's top edge, just inside it.
    static func barFrame(for frame: Rect, size: CGSize) -> Rect {
        Rect(topLeftX: frame.minX + (frame.width - size.width) / 2, topLeftY: frame.minY + 4, width: size.width, height: size.height)
    }

    /// Where the window is: a focused (fullscreen) window has no tile, only the screen it
    /// fills, and a floating one only where WindowServer has it (no cached frame follows it).
    static func frame(of window: Window, liveFrame: (UInt32) -> CGRect? = windowServerFrame) -> Rect? {
        if window.parent is Workspace {
            return liveFrame(window.windowId).map { Rect(topLeftX: $0.minX, topLeftY: $0.minY, width: $0.width, height: $0.height) }
        }
        return window.isFullscreen ? window.lastAppliedLayoutVirtualRect : window.lastAppliedLayoutPhysicalRect
    }

    /// The actions offered for a window, as titles and commands.
    static func actions(for window: Window) -> [(title: String, symbol: String, command: String)] {
        let id = window.windowId
        if window.isFullscreen { return [("Unfocus", "arrow.down.right.and.arrow.up.left", "fullscreen off --window-id \(id)")] }
        if window.parent is Workspace { return [("Tile", "rectangle.split.2x1", "layout tiling --window-id \(id)")] }
        var actions: [(String, String, String)] = []
        if window.nodeWorkspace?.arrangement == .master { actions.append(("Main", "rectangle.lefthalf.inset.filled", "swap-with-master --window-id \(id)")) }
        actions.append(("Focus", "arrow.up.left.and.arrow.down.right", "fullscreen --window-id \(id)"))
        actions.append(("Float", "macwindow.on.rectangle", "layout floating tiling --window-id \(id)"))
        return actions
    }

    /// The managed window whose top-edge zone holds the point, from cached frames.
    /// Floating windows and a focused one cover the tiles beneath them, so they come first.
    static func candidate(at point: CGPoint) -> Window? {
        for workspace in Workspace.all where workspace.isVisible {
            let windows = workspace.allLeafWindowsRecursive
            let floating = workspace.floatingWindows.filter { $0.participatesInWorkspaceFocus && !$0.isHiddenInCorner }
            for window in floating + windows.filter(\.isFullscreen) + windows.filter({ !$0.isFullscreen }) {
                guard window.parent is TilingContainer || window.parent is Workspace, !window.isConcealedByScrolling,
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
        guard config.hoverBar.enabled, TrayMenuModel.shared.isEnabled, !isLeftMouseButtonDown, !isMouseManipulationActive,
              !WorkspacePresentationController.shared.isActive else { return hide() }
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
            self.show(for: window)
        })
    }

    private var panelRect: CGRect {
        let frame = panel.frame
        return CGRect(x: frame.minX, y: mainMonitor.height - frame.maxY, width: frame.width, height: frame.height)
    }

    private func show(for window: Window) {
        guard let frame = Self.frame(of: window) else { return }
        let id = window.windowId
        let size = panel.configure(Self.actions(for: window)) { [weak self] command in
            self?.hide()
            // Act as a click on the window would: focus (and raise) it first, so a window
            // floated from the bar is not left behind the tiles it came from.
            guard let token: RunSessionGuard = .isServerEnabled, case .cmd(let parsed) = parseCommand(command),
                  case .cmd(let raise) = parseCommand(["focus", "--window-id", String(id)]) else { return }
            Task { @MainActor in
                _ = try? await runLightSession(.menuBarButton, token, shouldSchedulePostRefresh: true) {
                    let result = try await [raise, parsed].runCmdSeq(.defaultEnv, .emptyStdin)
                    showShortcutFailure("Hover bar", result)
                }
            }
        }
        let bar = Self.barFrame(for: frame, size: size)
        panel.setFrame(CGRect(x: bar.minX, y: mainMonitor.height - bar.maxY, width: bar.width, height: bar.height), display: true)
        panel.orderFrontRegardless()
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

@MainActor
private final class HoverBarPanel: NSPanelHud {
    private let stack = NSStackView()
    private var run: ((String) -> Void)?

    override init() {
        super.init()
        level = .floating
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor), stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor), stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        contentView = effect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Lays out one button per action and returns the bar's size.
    func configure(_ actions: [(title: String, symbol: String, command: String)], run: @escaping (String) -> Void) -> CGSize {
        self.run = run
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for action in actions {
            let button = HoverBarButton(title: action.title, target: self, action: #selector(pressed(_:)))
            button.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.bezelStyle = .recessed
            button.controlSize = .small
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.identifier = NSUserInterfaceItemIdentifier(action.command)
            stack.addArrangedSubview(button)
        }
        stack.layoutSubtreeIfNeeded()
        return stack.fittingSize
    }

    @objc private func pressed(_ sender: NSButton) {
        guard let command = sender.identifier?.rawValue else { return }
        run?(command)
    }
}

private final class HoverBarButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
