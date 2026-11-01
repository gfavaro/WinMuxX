import AppKit
import os

/// Whether VoiceOver or Switch Control is running. Both rely on the app's Enhanced User Interface,
/// which frame writes otherwise switch off and back on around every write, so WinMux leaves it
/// alone while either runs, as Dinky does. Kept current by KVO; read from apps' AX threads.
enum AssistiveTechnology {
    private static let active = OSAllocatedUnfairLock(initialState: false)
    @MainActor private static var observations: [NSKeyValueObservation] = []

    static var isActive: Bool { active.withLock { $0 } }

    @MainActor
    static func startObserving() {
        guard observations.isEmpty else { return }
        let workspace = NSWorkspace.shared
        observations = [
            workspace.observe(\.isVoiceOverEnabled, options: [.initial]) { _, _ in refresh() },
            workspace.observe(\.isSwitchControlEnabled, options: [.initial]) { _, _ in refresh() },
        ]
    }

    private static func refresh() {
        let workspace = NSWorkspace.shared
        let running = workspace.isVoiceOverEnabled || workspace.isSwitchControlEnabled
        active.withLock { $0 = running }
    }
}
