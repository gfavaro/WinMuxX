import AppKit
import Common
import CoreGraphics

private struct MonitorImpl: Sendable {
    var hardwareIdentity: MonitorHardwareIdentity? = nil
    var displayUUID: String? = nil
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool
}

extension MonitorImpl: Monitor {
    var height: CGFloat { rect.height }
    var width: CGFloat { rect.width }
}

/// Use it instead of NSScreen because it can be mocked in tests
protocol Monitor: WinMuxAny, Sendable {
    var hardwareIdentity: MonitorHardwareIdentity? { get }
    var displayUUID: String? { get }
    /// The index in NSScreen.screens array. 1-based index
    var monitorAppKitNsScreenScreensId: Int { get }
    var name: String { get }
    var rect: Rect { get }
    var visibleRect: Rect { get }
    var width: CGFloat { get }
    var height: CGFloat { get }
    var isMain: Bool { get }
}

extension Monitor {
    var hardwareIdentity: MonitorHardwareIdentity? { nil }
    var displayUUID: String? { nil }
}

// Note to myself: Don't use NSScreen.main, it's garbage
// 1. The name is misleading, it's supposed to be called "focusedScreen"
// 2. It's inaccurate because NSScreen.main doesn't work correctly from NSWorkspace.didActivateApplicationNotification &
//    kAXFocusedWindowChangedNotification callbacks.
extension NSScreen {
    var hardwareIdentity: MonitorHardwareIdentity? {
        guard let id = displayId else { return nil }
        return MonitorHardwareIdentity(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
    }
    var displayUUID: String? {
        guard let id = displayId, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
    var displayId: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID(truncating: $0) }
    }

    fileprivate func toMonitor(monitorAppKitNsScreenScreensId: Int, mainHeight: CGFloat? = nil, isMain: Bool? = nil) -> Monitor {
        let height = mainHeight ?? mainMonitor.height
        return MonitorImpl(
            hardwareIdentity: hardwareIdentity,
            displayUUID: displayUUID,
            monitorAppKitNsScreenScreensId: monitorAppKitNsScreenScreensId,
            name: localizedName,
            rect: frame.monitorFrameNormalized(mainHeight: height),
            visibleRect: visibleFrame.monitorFrameNormalized(mainHeight: height),
            isMain: isMain ?? isMainScreen,
        )
    }

    fileprivate var isMainScreen: Bool {
        displayId == CGMainDisplayID()
    }
}

private let testMonitorRect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
private let testMonitor = MonitorImpl(
    monitorAppKitNsScreenScreensId: 1,
    name: "Test Monitor",
    rect: testMonitorRect,
    visibleRect: testMonitorRect,
    isMain: true,
)
/// Native lookup remains available off-main; only main-actor access uses runtime caches.
@MainActor
final class MonitorState {
    private(set) var overrideForTests: [Monitor]?
    private var cached: [Monitor]?
    private var mainCache: Monitor?
    private let readMonitors: () -> [Monitor]
    private let readMain: () -> Monitor
    private let notifications: NotificationCenter
    private let observeChanges: Bool
    private var sortedCache: [Monitor]?
    private var observer: NSObjectProtocol?

    init(readMonitors: @escaping () -> [Monitor] = { isUnitTest ? [testMonitor] : computeMonitors() },
         readMain: @escaping () -> Monitor = { isUnitTest ? testMonitor : computeMainMonitor() },
         notifications: NotificationCenter = .default, observeChanges: Bool = !isUnitTest) {
        self.readMonitors = readMonitors
        self.readMain = readMain
        self.notifications = notifications
        self.observeChanges = observeChanges
    }

    isolated deinit {
        if let observer { notifications.removeObserver(observer) }
    }

    func invalidate() {
        cached = nil
        mainCache = nil
        sortedCache = nil
    }

    private func observeScreenChanges() {
        guard observeChanges, observer == nil else { return }
        observer = notifications.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidate() }
        }
    }

    func main() -> Monitor {
        if let overrides = overrideForTests {
            return overrides.first(where: \.isMain) ?? overrides.first ?? testMonitor
        }
        observeScreenChanges()
        if let mainCache { return mainCache }
        let result = readMain()
        mainCache = result
        return result
    }

    func all() -> [Monitor] {
        if let overrideForTests { return overrideForTests }
        observeScreenChanges()
        if let cached { return cached }
        let result = readMonitors()
        cached = result
        return result
    }

    func sorted() -> [Monitor] {
        if let sortedCache { return sortedCache }
        let result = sortMonitors(all())
        sortedCache = result
        return result
    }

    func setOverride(_ monitors: [Monitor]?) {
        precondition(isUnitTest)
        overrideForTests = monitors
        invalidate()
    }
}

@MainActor
func setMonitorsForTests(_ monitors: [Monitor]?) {
    runtime.displays.setOverride(monitors)
}

var mainMonitor: Monitor {
    if Thread.isMainThread {
        return MainActor.assumeIsolated { runtime.displays.main() }
    }
    return isUnitTest ? testMonitor : computeMainMonitor()
}

private func computeMainMonitor() -> Monitor {
    let screens = NSScreen.screens
    // During display reconfiguration, fall back to the first available screen.
    let screen = screens.withIndex.singleOrNil(where: \.value.isMainScreen) ?? screens.first.map { (0, $0) }
    guard let screen else { return testMonitor }
    return screen.value.toMonitor(monitorAppKitNsScreenScreensId: screen.index + 1,
                                  mainHeight: screen.value.frame.height, isMain: true)
}

private func computeMonitors() -> [Monitor] {
    let screens = NSScreen.screens
    guard !screens.isEmpty else { return [mainMonitor] }
    return screens.withIndex.map { index, screen in
        screen.toMonitor(monitorAppKitNsScreenScreensId: index + 1)
    }
}

var monitors: [Monitor] {
    if Thread.isMainThread {
        return MainActor.assumeIsolated { runtime.displays.all() }
    }
    return isUnitTest ? [testMonitor] : computeMonitors()
}

private func sortMonitors(_ monitors: [Monitor]) -> [Monitor] {
    monitors.sorted {
        if $0.rect.minX != $1.rect.minX { return $0.rect.minX < $1.rect.minX }
        if $0.rect.minY != $1.rect.minY { return $0.rect.minY < $1.rect.minY }
        return $0.monitorAppKitNsScreenScreensId < $1.monitorAppKitNsScreenScreensId
    }
}

var sortedMonitors: [Monitor] {
    if Thread.isMainThread {
        return MainActor.assumeIsolated { runtime.displays.sorted() }
    }
    return sortMonitors(monitors)
}
