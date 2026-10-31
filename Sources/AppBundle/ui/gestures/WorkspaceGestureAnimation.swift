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

/// Scalar sampling for viewport motion. It uses the stiffness, mass and
/// normalized initial velocity of the same critically damped spring used by
/// workspace swipe and overview presentation.
struct WorkspaceGestureScalarSpring {
    let from: CGFloat
    let to: CGFloat
    let initialVelocity: CGFloat
    let stiffness: CGFloat
    let mass: CGFloat

    init(from: CGFloat, to: CGFloat, animation: CASpringAnimation) {
        self.from = from
        self.to = to
        self.initialVelocity = animation.initialVelocity * (to - from)
        self.stiffness = max(animation.stiffness, 0.001)
        self.mass = max(animation.mass, 0.001)
    }

    func value(at elapsed: TimeInterval) -> CGFloat {
        let time = max(0, elapsed)
        let omega = sqrt(stiffness / mass)
        let distance = to - from
        let a = -distance
        let b = initialVelocity - omega * distance
        return to + (a + b * time) * exp(-omega * time)
    }
}
