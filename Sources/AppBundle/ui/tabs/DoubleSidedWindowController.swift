import AppKit
import QuartzCore

/// Animates cards of the two windows because another app's window cannot host our Core
/// Animation layers.
@MainActor
final class DoubleSidedWindowController {
    static let shared = DoubleSidedWindowController()
    private var animationPanel: NSPanel?
    private let backdropPadding: CGFloat = 64

    var isAnimating: Bool { animationPanel != nil }

    func flip(_ window: Window) {
        guard !isAnimating, TrayMenuModel.shared.isEnabled,
              let group = window.nearestWindowTabGroup,
              group.usesDoubleSidedWindows,
              group.tabActiveWindow === window,
              let other = group.children.compactMap({ $0 as? Window }).first(where: { $0 !== window }),
              let rect = window.lastAppliedLayoutPhysicalRect
        else { return }
        let canAnimate = config.animations.enabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard canAnimate else {
            focusWindowFromTabStrip(other.windowId, fallbackWorkspace: focus.workspace.name)
            return
        }
        if let images = placeholderWindowFlipImages(front: window.windowId, back: other.windowId, rect: rect,
                                                    padding: backdropPadding, monitor: window.nodeMonitor ?? mainMonitor) {
            animate(front: images.front, back: images.back, background: images.background, rect: rect)
        }
        focusWindowFromTabStrip(other.windowId, fallbackWorkspace: focus.workspace.name)
    }

    private func animate(front: CGImage, back: CGImage, background: CGImage, rect: Rect) {
        let frame = CGRect(x: rect.topLeftX, y: mainMonitor.height - rect.topLeftY - rect.height,
                           width: rect.width, height: rect.height)
            .insetBy(dx: -backdropPadding, dy: -backdropPadding)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        let root = CALayer()
        // Cover the real windows and their shadows throughout the rotation.
        root.contents = background
        root.contentsGravity = .resize
        view.layer = root
        panel.contentView = view
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / max(rect.width * 2, 1000)
        root.sublayerTransform = perspective
        let duration = 0.48
        for (image, start, end) in [(front, 0.0, Double.pi), (back, -Double.pi, 0.0)] {
            let face = CALayer()
            face.frame = view.bounds.insetBy(dx: backdropPadding, dy: backdropPadding)
            face.contents = image
            face.contentsGravity = .resize
            face.isDoubleSided = false
            face.allowsEdgeAntialiasing = true
            root.addSublayer(face)
            face.transform = CATransform3DMakeRotation(CGFloat(end), 0, 1, 0)
            let rotation = CABasicAnimation(keyPath: "transform.rotation.y")
            rotation.fromValue = start
            rotation.toValue = end
            rotation.duration = duration
            rotation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            face.add(rotation, forKey: "flip")
        }
        animationPanel = panel
        CATransaction.commit()
        panel.orderFrontRegardless()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            panel.orderOut(nil)
            panel.contentView?.layer?.removeAllAnimations()
            panel.contentView = nil
            panel.close()
            if animationPanel === panel { animationPanel = nil }
        }
    }
}
