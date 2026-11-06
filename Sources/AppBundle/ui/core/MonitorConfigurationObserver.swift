import AppKit

@MainActor
final class MonitorConfigurationObserver {
    static let shared = MonitorConfigurationObserver()

    private var observer: NSObjectProtocol?
    private var screenChangeGeneration: UInt64 = 0
    /// Replaces the settle delay, so tests can release each deadline in turn.
    var settleDelayOverrideForTests: (@MainActor () async -> Void)?

    private init() {}

    func prepareForStartup() {
        runtime.displays.changes.seed(displayTopologyIdentities(monitors))
        refreshMonitorPolicy(refreshReason: "MonitorConfigurationObserver.prepareForStartup")
    }

    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
        ) { _ in
            Task { @MainActor in
                MonitorConfigurationObserver.shared.handleScreenParametersChanged()
            }
        }
    }

    func handleScreenParametersChanged() {
        runtime.displays.displayHookPending = false
        WorkspaceOverviewController.shared.invalidate()
        WindowMotion.shared.screensChanged()
        // A vanished display's workspace must not stay "visible" on it: selection would then
        // target it and be refused. Retiring creates no fallback workspace.
        retireDisconnectedViewports()
        // AppKit can emit this notification while the display topology is still changing.
        // Refresh panels immediately, but wait for the settled pass before reconciling
        // workspace-to-monitor assignments. This avoids creating fallback workspaces for a
        // transient one-display topology during plug/unplug and arrangement changes.
        refreshMonitorPolicy(
            refreshReason: NSApplication.didChangeScreenParametersNotification.rawValue,
            refreshSession: false,
        )
        scheduleSettledRefresh()
    }

    private func refreshMonitorPolicy(refreshReason: String, refreshSession: Bool = true) {
        WorkspaceSidebarPanel.refreshAll()
        WindowTabStripPanelController.shared.refresh()
        if refreshSession, TrayMenuModel.shared.isEnabled {
            scheduleRefreshSession(.globalObserver(refreshReason))
        }
    }

    private func scheduleSettledRefresh() {
        screenChangeGeneration += 1
        let generation = screenChangeGeneration
        Task { @MainActor in
            if let delay = self.settleDelayOverrideForTests {
                await delay()
            } else {
                try? await Task.sleep(nanoseconds: 750_000_000)
            }
            guard generation == screenChangeGeneration else { return }
            WindowMotion.shared.screensSettled()
            if TrayMenuModel.shared.isEnabled {
                runtime.displays.displayHookPending = true
            } else {
                runtime.displays.changes.seed(displayTopologyIdentities(monitors))
            }
            refreshMonitorPolicy(refreshReason: "\(NSApplication.didChangeScreenParametersNotification.rawValue).settled")
        }
    }
}
