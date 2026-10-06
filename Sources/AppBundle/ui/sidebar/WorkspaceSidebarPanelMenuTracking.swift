import AppKit
import Common
import CoreGraphics
import SwiftUI

extension WorkspaceSidebarPanel {
    func installMenuTrackingObservers() {
        let center = NotificationCenter.default
        menuTrackingObservers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.beginMenuTrackingIfNeeded() }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.endMenuTrackingIfNeeded() }
            },
        ]
    }

    func beginMenuTrackingIfNeeded() {
        guard isVisible,
              viewModel.workspaceSidebarVisibleWidth > 0,
              isMouseInsideVisibleRegion()
        else { return }
        menuTrackingDepth += 1
        menuTrackingGraceUntil = .distantFuture
        pendingCollapse?.cancel()
        pendingCollapse = nil
        pendingCollapseFinalize?.cancel()
        pendingCollapseFinalize = nil
        expandSidebar(to: CGFloat(config.workspaceSidebar.width))
    }

    func endMenuTrackingIfNeeded() {
        guard menuTrackingDepth > 0 else { return }
        menuTrackingDepth -= 1
        guard menuTrackingDepth == 0 else { return }
        menuTrackingGraceUntil = Date().addingTimeInterval(menuTrackingEndGrace)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.updateHoverStateFromMousePosition()
        }
        // The 0.08s recheck lands inside the grace period, whose expansion lock swallows a
        // hover exit. With a stationary cursor no pointer event re-evaluates after the grace
        // expires, so schedule one recheck just past it.
        DispatchQueue.main.asyncAfter(deadline: .now() + menuTrackingEndGrace + 0.05) { [weak self] in
            self?.updateHoverStateFromMousePosition()
        }
    }

    func isMenuTrackingOrInGracePeriod(now: Date = .now) -> Bool {
        menuTrackingDepth > 0 || now < menuTrackingGraceUntil
    }
}
