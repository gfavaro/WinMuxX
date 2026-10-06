import AppKit

@MainActor
final class MonitorConfigurationObserver {
    static let shared = MonitorConfigurationObserver()

    private var observer: NSObjectProtocol?
    private var screenChangeGeneration: UInt64 = 0

    private init() {}

    func prepareForStartup() {
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

    private func handleScreenParametersChanged() {
        WindowMotion.shared.screensChanged()
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
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard generation == screenChangeGeneration else { return }
            WindowMotion.shared.screensSettled()
            refreshMonitorPolicy(refreshReason: "\(NSApplication.didChangeScreenParametersNotification.rawValue).settled")
        }
    }
}
