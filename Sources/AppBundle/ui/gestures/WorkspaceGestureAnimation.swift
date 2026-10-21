import AppKit
import QuartzCore

/// The common spring for horizontal navigation and overview presentation.
enum WorkspaceGestureAnimation {
    static func settlingAnimation(keyPath: String, from: CGFloat, to: CGFloat, speed: CGFloat, duration: Double) -> CASpringAnimation {
        let animation: CASpringAnimation
        if #available(macOS 14, *) {
            animation = CASpringAnimation(perceptualDuration: duration, bounce: 0)
            animation.keyPath = keyPath
        } else {
            // Apple's published duration-to-spring conversion (WWDC23, Animate with springs).
            animation = CASpringAnimation(keyPath: keyPath)
            animation.mass = 1
            animation.stiffness = pow(2 * .pi / duration, 2)
            animation.damping = 2 * sqrt(animation.stiffness)
        }
        let distance = to - from
        // Core Animation expects animation distances per second, positive towards the target.
        let criticalSpeed = sqrt(animation.stiffness / animation.mass)
        animation.initialVelocity = abs(distance) > 0.000001 ? max(-criticalSpeed, min(criticalSpeed, speed / distance)) : 0
        animation.fromValue = from
        animation.toValue = to
        animation.duration = animation.settlingDuration
        return animation
    }

    static func duration(milliseconds: Int, enabled: Bool, reduceMotion: Bool) -> Double? {
        guard enabled, !reduceMotion, milliseconds > 0 else { return nil }
        return Double(milliseconds) / 1000
    }
}
