import AppKit
import Common
import QuartzCore

struct WorkspaceOverviewMotion {
    let opacity: CGFloat
    let scale: CGFloat
    let translation: CGFloat

    init(progress: Double, height: CGFloat) {
        let p = CGFloat(progress.isFinite ? min(1, max(0, progress)) : 0)
        opacity = p
        scale = 1 + 0.035 * (1 - p)
        translation = max(0, height) * 0.06 * (1 - p)
    }
}

/// Panel-only motion; updates touch existing layers without publishing view state.
@MainActor
final class WorkspaceOverviewPresentation {
    private var generation = 0

    func cancel(_ panel: NSPanel) {
        generation += 1
        panel.contentView?.layer?.removeAllAnimations()
    }

    func update(_ panel: NSPanel, progress: Double) {
        cancel(panel)
        guard let view = panel.contentView else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        apply(WorkspaceOverviewMotion(progress: progress, height: view.bounds.height), to: layer)
    }

    private func apply(_ motion: WorkspaceOverviewMotion, to layer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = Float(motion.opacity)
        var transform = CATransform3DMakeScale(motion.scale, motion.scale, 1)
        transform.m42 = motion.translation
        layer.transform = transform
        CATransaction.commit()
    }

    func animate(_ panel: NSPanel, opening: Bool, completion: @escaping @MainActor () -> Void = {}) {
        guard let view = panel.contentView else { completion(); return }
        view.wantsLayer = true
        guard let layer = view.layer else { completion(); return }
        let visible = layer.presentation() ?? layer
        let fromOpacity = CGFloat(visible.opacity), fromScale = visible.transform.m11, fromY = visible.transform.m42
        cancel(panel)
        let target = WorkspaceOverviewMotion(progress: opening ? 1 : 0, height: view.bounds.height)
        guard let duration = WorkspaceGestureAnimation.duration(milliseconds: config.animations.durationMs,
            enabled: config.animations.enabled && !isUnitTest,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else {
            apply(target, to: layer); completion(); return
        }
        let token = generation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in
                guard self?.generation == token else { return }
                completion()
            }
        }
        let values: [(String, CGFloat, CGFloat, String)] = [
            ("opacity", fromOpacity, target.opacity, "workspaceOverviewOpacity"),
            ("transform.scale", fromScale, target.scale, "workspaceOverviewScale"),
            ("transform.translation.y", fromY, target.translation, "workspaceOverviewTranslation"),
        ]
        apply(target, to: layer)
        for (keyPath, from, to, key) in values {
            layer.add(WorkspaceGestureAnimation.settlingAnimation(keyPath: keyPath, from: from, to: to,
                speed: 0, duration: duration), forKey: key)
        }
        CATransaction.commit()
    }
}

extension WorkspaceOverviewPanel: WorkspaceOverviewPresenting {
    func present(key: Bool) {
        alphaValue = 1
        ignoresMouseEvents = false
        presentation.update(self, progress: 0)
        presentation.animate(self, opening: true)
        orderFrontRegardless()
        if key { makeKey() }
    }

    func dismissOverview(animated: Bool, completion: @escaping @MainActor () -> Void) {
        ignoresMouseEvents = true
        resignKey()
        if animated { presentation.animate(self, opening: false, completion: completion) }
        else { hideForReuse(); completion() }
    }

    func hideForReuse() {
        presentation.cancel(self)
        orderOut(nil)
        model.activate = nil; model.pageChanged = nil; model.dismiss = nil
    }

    func dismissOverview() {
        hideForReuse()
        contentView = nil
        model.activate = nil; model.pageChanged = nil; model.dismiss = nil
    }
}
