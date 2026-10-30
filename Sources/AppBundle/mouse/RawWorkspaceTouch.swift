import AppKit
import Common
import PrivateApi

@MainActor
final class RawWorkspaceTouchSource: ObservableObject {
    static let shared = RawWorkspaceTouchSource()
    nonisolated static let mailbox = WorkspaceTouchMailbox()
    @Published private(set) var status = "Disabled"
    @Published private(set) var maximumFingerCount = 0
    private(set) var deviceCount = 0
    private(set) var frameCount = 0
    private var generation: UInt64 = 0
    private var notifications: [(NotificationCenter, NSObjectProtocol)] = []
    private var revalidation: Task<Void, Never>?
    private var suspended = false
    var onFrame: ((WorkspaceTouchFrame) -> Void)?

    private var wantsTouch: Bool {
        let scrollingWorkspaceVisible = config.scrolling.gestureEnabled &&
            sortedMonitors.contains { runtime.workspaces.visibleWorkspace(for: $0)?.arrangement == .scrolling }
        return workspaceGesturesNeedRawTouch(horizontal: rawWorkspaceSwipeEnabled,
            overview: workspaceOverviewGestureEnabled,
            overviewOpen: WorkspaceOverviewController.shared.isOpen || scrollingWorkspaceVisible,
            runtimeEnabled: TrayMenuModel.shared.isEnabled)
    }

    @discardableResult
    func updateDemand() -> Bool {
        guard wantsTouch != !notifications.isEmpty else { return false }
        syncConfiguration()
        return true
    }

    func syncConfiguration() {
        stop()
        guard wantsTouch, !isUnitTest else { return }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, sleeping: false)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification, sleeping: true)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification, sleeping: true)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification, sleeping: false)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification, sleeping: false)
        _ = winmux_touch_watch_topology {
            MainActor.assumeIsolated { RawWorkspaceTouchSource.shared.scheduleRevalidation() }
        }
        startDevices()
    }

    func stop() {
        revalidation?.cancel()
        revalidation = nil
        generation &+= 1
        Self.mailbox.activate(0)
        if !isUnitTest { winmux_touch_stop(); winmux_touch_unwatch_topology() }
        for (center, token) in notifications { center.removeObserver(token) }
        notifications.removeAll()
        deviceCount = 0
        frameCount = 0
        maximumFingerCount = 0
        suspended = false
        status = "Disabled"
    }

    private func startDevices() {
        guard wantsTouch, !suspended else { return }
        generation &+= 1
        Self.mailbox.activate(generation)
        frameCount = 0
        maximumFingerCount = 0
        let count = winmux_touch_start(generation, workspaceTouchFrameCallback)
        deviceCount = max(0, Int(count))
        status = count < 0 ? "Raw touch API unavailable" : count == 0 ? "No trackpad registered" : "Listening on \(count) trackpad(s)"
    }

    fileprivate func drain() {
        let batch = Self.mailbox.take()
        guard batch.generation == generation, !suspended, wantsTouch else { return }
        frameCount = batch.received
        for frame in batch.frames {
            guard batch.generation == generation, !suspended, wantsTouch else { break }
            if frame.fingers > maximumFingerCount { maximumFingerCount = frame.fingers }
            onFrame?(frame)
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, sleeping: Bool) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                WorkspaceGestureCoordinator.shared.reset()
                if sleeping {
                    self.suspended = true
                    self.revalidation?.cancel()
                    self.generation &+= 1
                    Self.mailbox.activate(0)
                    winmux_touch_stop()
                    self.deviceCount = 0
                    self.status = "Paused while sleeping"
                } else {
                    self.suspended = false
                    self.scheduleRevalidation()
                }
            }
        }
        notifications.append((center, token))
    }

    private func scheduleRevalidation() {
        guard wantsTouch, !suspended else { return }
        revalidation?.cancel()
        revalidation = Task { @MainActor [weak self] in
            // Allow Bluetooth and built-in devices to settle after topology changes.
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self, !Task.isCancelled, wantsTouch, !self.suspended else { return }
            WorkspaceGestureCoordinator.shared.reset()
            self.startDevices()
            self.revalidation = nil
        }
    }
}

// A C callback must not inherit the main actor from startDevices(). The driver
// calls this function on its own thread; only copied data and the locked mailbox
// are touched until an explicit hop to the main queue.
nonisolated func workspaceTouchFrameCallback(_ generation: UInt64, _ device: UInt64, _ fingers: Int32,
                                             _ x: Double, _ y: Double, _ timestamp: Double, _ contacts: UInt64,
                                             _ points: UnsafePointer<WinMuxTouchContact>?) {
    let copied: WorkspaceTouchContacts?
    if fingers == 3, let points {
        func contact(_ index: Int) -> WorkspaceTouchContact {
            let point = points[index]
            return WorkspaceTouchContact(identifier: point.identifier, y: point.y)
        }
        copied = WorkspaceTouchContacts(first: contact(0), second: contact(1), third: contact(2))
    } else { copied = nil }
    let frame = WorkspaceTouchFrame(device: device, fingers: Int(fingers), x: x, y: y,
                                   timestamp: timestamp, contacts: contacts, touchContacts: copied)
    guard RawWorkspaceTouchSource.mailbox.offer(frame, generation: generation) else { return }
    DispatchQueue.main.async { RawWorkspaceTouchSource.shared.drain() }
}
