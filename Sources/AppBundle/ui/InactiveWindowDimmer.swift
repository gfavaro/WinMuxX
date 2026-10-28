import AppKit
import Common

/// Darkens everything but the focused window: lightly with `[dimming] inactive-windows`,
/// or fully and blurred while No peek is on, so others can't read your other windows.
/// One click-through panel per screen sits directly below the focused window. It
/// follows the border refresh, which already tracks focus, Mission Control, native
/// fullscreen and presentation.
@MainActor
final class InactiveWindowDimmer {
    static let shared = InactiveWindowDimmer()
    private(set) var noPeek = false
    private var panels: [ObjectIdentifier: DimmingPanel] = [:]

    func setNoPeek(_ enabled: Bool) {
        noPeek = enabled
        refresh(chromeAllowed: true)
    }

    /// The darkness to apply, nil when nothing is dimmed.
    static func style(noPeek: Bool, inactive: Double) -> DimmingStyle? {
        if noPeek { return .noPeek }
        return inactive > 0 ? .dim(min(inactive, 0.8)) : nil
    }

    func refresh(chromeAllowed: Bool) {
        guard !isUnitTest else { return }
        guard chromeAllowed, TrayMenuModel.shared.isEnabled,
              let style = Self.style(noPeek: noPeek, inactive: config.dimming.inactiveWindows),
              let focused = focus.windowOrNil, !focused.isFullscreen,
              !WorkspacePresentationController.shared.suppressesChrome(for: focused) else { return hide() }
        let screens = NSScreen.screens
        let live = Set(screens.map(ObjectIdentifier.init))
        for (id, panel) in panels where !live.contains(id) { panel.close(); panels[id] = nil }
        for screen in screens {
            let panel = panels[ObjectIdentifier(screen)] ?? DimmingPanel()
            panels[ObjectIdentifier(screen)] = panel
            panel.apply(style)
            panel.setFrame(screen.frame, display: false)
            panel.order(.below, relativeTo: Int(focused.windowId))
        }
    }

    func hide() {
        panels.values.forEach { $0.orderOut(nil) }
    }
}

enum DimmingStyle: Equatable {
    case dim(Double)
    case noPeek
}

@MainActor
private final class DimmingPanel: NSPanelHud {
    private let blur = NSVisualEffectView()
    private let shade = NSView()
    private var style: DimmingStyle?

    override init() {
        super.init()
        level = .normal
        hasShadow = false
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        // Every Space, hidden by Mission Control like the border panels.
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let root = NSView()
        blur.blendingMode = .behindWindow
        blur.material = .fullScreenUI
        blur.state = .active
        shade.wantsLayer = true
        for view in [blur, shade] {
            view.autoresizingMask = [.width, .height]
            root.addSubview(view)
        }
        contentView = root
    }

    func apply(_ next: DimmingStyle) {
        guard style != next else { return }
        style = next
        switch next {
            case .dim(let alpha):
                blur.isHidden = true
                shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(alpha).cgColor
            case .noPeek:
                blur.isHidden = false
                shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        }
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
