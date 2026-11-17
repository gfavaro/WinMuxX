import AppKit
import Common

/// A thin accent line in the gap beside a pinned scrolling column, so a pin is
/// visible where it acts. One line per laid-out workspace; workspaces that are no
/// longer showing lose theirs at the next layout.
@MainActor
final class ScrollingPinIndicator {
    static let shared = ScrollingPinIndicator()
    static let thickness: CGFloat = 3
    private var lines: [ObjectIdentifier: ScrollingPinLinePanel] = [:]

    /// The line's rect in top-left global coordinates, nil when nothing is pinned.
    static func lineRect(pinned: Rect, side: ScrollingPinCmdArgs.Side, gap: CGFloat) -> Rect {
        let inset = min(pinned.height * 0.15, 80)
        let x = side == .left ? pinned.maxX + max(gap, thickness) / 2 - thickness / 2
            : pinned.minX - max(gap, thickness) / 2 - thickness / 2
        return Rect(topLeftX: x, topLeftY: pinned.minY + inset, width: thickness, height: max(pinned.height - inset * 2, 1))
    }

    func update(_ workspace: Workspace, rect: Rect, gaps: ResolvedGaps) {
        guard !isUnitTest else { return }
        guard TrayMenuModel.shared.isEnabled else { return hideAll() }
        let id = ObjectIdentifier(workspace)
        for (other, panel) in lines where other != id && !Workspace.all.contains(where: { ObjectIdentifier($0) == other && $0.isVisible }) {
            panel.close()
            lines[other] = nil
        }
        guard workspace.isVisible, let split = workspace.scrollingPinSplit(in: rect, gaps: gaps) else { hide(workspace); return }
        let line = Self.lineRect(pinned: split.pinned, side: workspace.scrollingPinSide, gap: CGFloat(gaps.inner.horizontal))
        let panel = lines[id] ?? ScrollingPinLinePanel()
        lines[id] = panel
        panel.setFrame(CGRect(x: line.minX, y: mainMonitor.height - line.maxY, width: line.width, height: line.height), display: true)
        panel.orderFrontRegardless()
    }

    func hide(_ workspace: Workspace) {
        lines.removeValue(forKey: ObjectIdentifier(workspace))?.close()
    }

    func hideAll() {
        lines.values.forEach { $0.close() }
        lines.removeAll()
    }
}

@MainActor
private final class ScrollingPinLinePanel: NSPanelHud {
    override init() {
        super.init()
        hasShadow = false
        ignoresMouseEvents = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = .clear
        isOpaque = false
        // Hidden by Mission Control like the border panels.
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        contentView = ScrollingPinLineView()
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ScrollingPinLineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.width / 2, yRadius: bounds.width / 2).fill()
    }
}
