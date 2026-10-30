import AppKit
import Common

// macOS's own three-finger swipes drive workspace swipes and the workspace overview, so
// recognition (start distance, resting palms and thumbs, flicks, taking a swipe back) is
// exactly native. macOS turns each gesture into private Dock swipe events; a session event
// tap keeps the ones WinMuxX acts on from the Dock and hands the rest back untouched.
// Interception after InstantSpaceSwitcher (MIT, jurplel) and iss (ISC, joshuarli); the
// macOS 27 handling of the final event and the vertical direction follow both and Space
// Rabbit's measurements. Raw touch remains the fallback when macOS assigns a gesture to
// four fingers or turns it off.

enum DockSwipeStart: Equatable {
    /// WinMuxX previews and may act.
    case started
    /// WinMuxX owns the swipe but does nothing with it (Option held, a switch settling).
    case ignored
    /// Nothing for WinMuxX that way, or WinMuxX is not taking swipes: macOS gets the swipe.
    case unavailable
}

@MainActor
protocol DockSwipeReceiver: AnyObject {
    /// Asked when the fingers touch down; `.unavailable` leaves the whole swipe to macOS.
    func dockSwipeMayStart() -> DockSwipeStart
    /// `positive` is the sign of macOS's progress, as macOS reports it for the axis.
    func dockSwipeBegan(positive: Bool, progress: Double, timestamp: Double) -> DockSwipeStart
    func dockSwipeChanged(_ progress: Double, timestamp: Double)
    func dockSwipeEnded(commit: Bool, progress: Double, velocity: Double, timestamp: Double)
}

/// One Dock swipe at a time: whether WinMuxX or macOS owns it, and when WinMuxX releases
/// it, whether it completes. Progress is macOS's travel since touchdown, signed by direction.
@MainActor
struct DockSwipeTracker {
    enum Verdict: Equatable {
        case pass
        /// Kept from the Dock until WinMuxX knows the swipe is its own.
        case hold
        case swallow
        /// macOS gets the swipe after all: post what was held, then this event.
        case replayHeldThenPass
        /// The Dock still sees the gesture end, with no motion to act on.
        case passWithoutMotion
    }
    enum Phase: Int64 { case began = 1, changed = 2, ended = 4, cancelled = 8 }
    private enum State: Equatable { case idle, passing, undecided, ignoring, claimed(sign: Double) }

    /// Below this, the sign of the travel is touchdown wobble rather than a direction.
    static let directionThreshold = 0.05
    /// On macOS 27 the Dock needs the real Ended to close its gesture state.
    let dockNeedsEnd: Bool
    private var state = State.idle
    private var progress = 0.0
    private var sampleTime = 0.0
    private(set) var velocity = 0.0
    private(set) var summary = DockSwipeSummary()

    init(dockNeedsEnd: Bool = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27) {
        self.dockNeedsEnd = dockNeedsEnd
    }

    /// WinMuxX owns the swipe, so the generic gesture events that come with it stay away from the Dock.
    var ownsGesture: Bool {
        switch state {
            case .claimed, .ignoring: true
            default: false
        }
    }

    /// Not yet known whose the swipe is: its generic gesture events wait with it.
    var isUndecided: Bool { state == .undecided }

    /// The same release rule as raw touch: past halfway, or a quick flick that has travelled.
    static func shouldCommit(progress: Double, velocity: Double) -> Bool {
        progress >= 0.5 || (progress >= 0.16 && velocity >= 2.5)
    }

    /// Ends a swipe WinMuxX owns without completing it, when its events stop arriving.
    mutating func abandon(_ receiver: some DockSwipeReceiver) {
        if case .claimed = state {
            receiver.dockSwipeEnded(commit: false, progress: progress, velocity: 0, timestamp: sampleTime)
        }
        state = .idle
    }

    mutating func receive(phase rawPhase: Int64, progress raw: Double, endVelocity: Double, timestamp: Double,
                          to receiver: some DockSwipeReceiver) -> Verdict {
        guard let phase = Phase(rawValue: rawPhase) else {
            switch state {
                case .idle, .passing: return .pass
                case .undecided: return .hold
                case .ignoring, .claimed: return .swallow
            }
        }
        switch phase {
            case .began:
                abandon(receiver)
                summary = DockSwipeSummary()
                switch receiver.dockSwipeMayStart() {
                    case .unavailable:
                        state = .passing
                        summary.outcome = "left to macOS"
                        return .pass
                    case .ignored:
                        state = .ignoring
                        summary.outcome = "ignored"
                        return .swallow
                    case .started:
                        state = .undecided
                        return .hold
                }
            case .changed:
                summary.samples += 1
                summary.maximumProgress = max(summary.maximumProgress, abs(raw))
                switch state {
                    case .idle, .passing: return .pass
                    case .ignoring: return .swallow
                    case .undecided:
                        guard abs(raw) >= Self.directionThreshold else { return .hold }
                        return start(sign: raw > 0 ? 1 : -1, progress: abs(raw), timestamp: timestamp, receiver)
                    case .claimed(let sign):
                        track(min(1, max(0, raw * sign)), timestamp: timestamp)
                        receiver.dockSwipeChanged(progress, timestamp: timestamp)
                        return .swallow
                }
            case .ended:
                summary.endVelocity = endVelocity
                defer { state = .idle }
                let close: Verdict = dockNeedsEnd ? .passWithoutMotion : .swallow
                switch state {
                    case .idle, .passing: return .pass
                    case .ignoring: return close
                    case .undecided:
                        // A flick can end before any sample travelled far enough to say which way.
                        guard endVelocity != 0 else { summary.outcome = "no direction"; return .replayHeldThenPass }
                        let verdict = start(sign: endVelocity > 0 ? 1 : -1, progress: 0, timestamp: timestamp, receiver)
                        guard verdict == .swallow else { return verdict }
                        if case .claimed = state { finish(commit: true, velocity: 0, timestamp: timestamp, receiver) }
                        return close
                    case .claimed:
                        // A velocity from a sample long before the lift is not a flick.
                        let velocity = timestamp - sampleTime < 0.08 ? velocity : 0
                        finish(commit: Self.shouldCommit(progress: progress, velocity: velocity),
                               velocity: velocity, timestamp: timestamp, receiver)
                        return close
                }
            case .cancelled:
                defer { state = .idle }
                switch state {
                    case .idle, .passing: return .pass
                    case .claimed:
                        finish(commit: false, velocity: 0, timestamp: timestamp, receiver)
                        return .swallow
                    case .undecided, .ignoring: return .swallow
                }
        }
    }

    private mutating func start(sign: Double, progress: Double, timestamp: Double,
                                _ receiver: some DockSwipeReceiver) -> Verdict {
        switch receiver.dockSwipeBegan(positive: sign > 0, progress: progress, timestamp: timestamp) {
            case .started:
                state = .claimed(sign: sign)
                self.progress = progress
                sampleTime = timestamp
                velocity = 0
                return .swallow
            case .ignored:
                state = .ignoring
                summary.outcome = "ignored"
                return .swallow
            case .unavailable:
                state = .passing
                summary.outcome = "left to macOS"
                return .replayHeldThenPass
        }
    }

    private mutating func track(_ next: Double, timestamp: Double) {
        let dt = timestamp - sampleTime
        if dt > 0.001 && dt <= 0.1 {
            let instant = (next - progress) / dt
            velocity = velocity == 0 ? instant : (velocity + instant) / 2
        } else if dt > 0.1 {
            velocity = 0
        }
        progress = next
        sampleTime = timestamp
    }

    private mutating func finish(commit: Bool, velocity: Double, timestamp: Double, _ receiver: some DockSwipeReceiver) {
        summary.finalProgress = progress
        summary.velocity = velocity
        summary.outcome = commit ? "completed" : "cancelled"
        receiver.dockSwipeEnded(commit: commit, progress: progress, velocity: velocity, timestamp: timestamp)
    }
}

/// The last swipe, for `winmuxx doctor`: macOS's progress scale and end velocity are
/// private, so these are what to compare when a swipe does not feel native.
struct DockSwipeSummary: Equatable {
    var samples = 0
    var maximumProgress = 0.0
    var finalProgress = 0.0
    var velocity = 0.0
    var endVelocity = 0.0
    var outcome = "none"
}

/// Horizontal swipes switch workspaces on the display under the pointer.
@MainActor
final class DockWorkspaceSwipeReceiver: DockSwipeReceiver {
    func dockSwipeMayStart() -> DockSwipeStart {
        let pointer = mouseLocation
        // A native fullscreen Space under the pointer is macOS's to swipe away from.
        if let monitor = sortedMonitors.first(where: { $0.rect.contains(pointer) }),
           shouldSuppressChromeForFullscreenContent(on: monitor) { return .unavailable }
        guard WorkspaceSwipeController.shared.canNavigate else { return .unavailable }
        // Option with three fingers pans a scrolling workspace through raw touch; it never switches.
        return NSEvent.modifierFlags.contains(.option) ? .ignored : .started
    }

    /// Positive progress heads for the next Space, following Natural scrolling already.
    func dockSwipeBegan(positive: Bool, progress: Double, timestamp: Double) -> DockSwipeStart {
        WorkspaceSwipeController.shared.beginDockSwipe(slidesLeft: positive, progress: progress, timestamp: timestamp)
    }

    func dockSwipeChanged(_ progress: Double, timestamp: Double) {
        WorkspaceSwipeController.shared.updateDockSwipe(progress, timestamp: timestamp)
    }

    func dockSwipeEnded(commit: Bool, progress: Double, velocity: Double, timestamp: Double) {
        WorkspaceSwipeController.shared.endDockSwipe(commit: commit, timestamp: timestamp)
    }
}

/// Vertical swipes open the overview (up) and close it (down) in place of Mission Control.
@MainActor
final class DockOverviewSwipeReceiver: DockSwipeReceiver {
    @MainActor
    struct Dependencies {
        var canStart: () -> Bool
        var enabled: () -> Bool
        var isOpen: () -> Bool
        var naturalScrolling: () -> Bool
        var begin: (_ opening: Bool, _ progress: Double) -> Bool
        var update: (Double) -> Void
        var end: (_ commit: Bool, _ velocity: Double) -> Void
        var show: () -> Void
        var hide: () -> Void

        static var live: Self {
            let overview = WorkspaceOverviewController.shared
            return Self(
                canStart: {
                    isWinMuxRuntimeReady && TrayMenuModel.shared.isEnabled && !WindowBorderController.shared.isMissionControlActive &&
                        !isMouseManipulationActive && !isLeftMouseButtonDown && !isWorkspaceSidebarDragInProgress()
                },
                enabled: { workspaceOverviewGestureEnabled }, isOpen: { overview.isOpen },
                naturalScrolling: naturalScrollingEnabled,
                begin: { overview.beginGesture(opening: $0, progress: $1) }, update: { overview.updateGesture(progress: $0) },
                end: { overview.endGesture(commit: $0, velocity: $1) },
                show: { _ = overview.show() }, hide: { overview.dismiss() })
        }
    }
    private let dependencies: Dependencies
    private var natural = true
    private var opens = false
    private var interactive = false

    init(dependencies: Dependencies = .live) { self.dependencies = dependencies }

    func dockSwipeMayStart() -> DockSwipeStart {
        guard dependencies.canStart() else { return .unavailable }
        // Read once per gesture so a changed setting applies without a restart.
        natural = dependencies.naturalScrolling()
        return .started
    }

    /// Vertical progress follows Natural scrolling: with it on, fingers moving up report negative.
    func dockSwipeBegan(positive: Bool, progress: Double, timestamp: Double) -> DockSwipeStart {
        let up = natural ? !positive : positive
        if dependencies.isOpen() {
            // Further up has nothing to open; Mission Control stays out from over the overview.
            guard !up else { return .ignored }
            opens = false
        } else {
            // Down (App Exposé) and a disabled overview stay with macOS.
            guard up, dependencies.enabled() else { return .unavailable }
            opens = true
        }
        interactive = dependencies.begin(opens, progress)
        return .started
    }

    func dockSwipeChanged(_ progress: Double, timestamp: Double) {
        if interactive { dependencies.update(progress) }
    }

    func dockSwipeEnded(commit: Bool, progress: Double, velocity: Double, timestamp: Double) {
        // Closing takes less travel than opening, as with raw touch.
        let commits = commit || (!opens && progress >= 0.25)
        if interactive {
            interactive = false
            dependencies.end(commits, velocity)
        } else if commits {
            if opens { dependencies.show() } else { dependencies.hide() }
        }
    }
}

@MainActor
final class DockWorkspaceSwipeSource {
    static let shared = DockWorkspaceSwipeSource()
    private(set) var status = "Disabled"
    /// macOS's three-finger horizontal swipe switches workspaces instead of raw touch.
    private(set) var readsHorizontal = false
    /// macOS's three-finger vertical swipe opens and closes the overview instead of raw touch.
    private(set) var readsVertical = false
    private var horizontal = DockSwipeTracker()
    private var vertical = DockSwipeTracker()
    private let workspaces = DockWorkspaceSwipeReceiver()
    private let overview = DockOverviewSwipeReceiver()
    private var held: [CGEvent] = []
    private var dockTap: (port: CFMachPort, source: CFRunLoopSource)?
    private var envelopeTap: (port: CFMachPort, source: CFRunLoopSource)?
    private var envelopeEnabled = false
    private var wakeObservers: [NSObjectProtocol] = []

    var horizontalSummary: DockSwipeSummary { horizontal.summary }
    var verticalSummary: DockSwipeSummary { vertical.summary }

    func syncConfiguration() {
        stop()
        guard !isUnitTest else { return }
        let wantsHorizontal = workspaceSwipeGestureEnabled && macTrackpadGesture("TrackpadThreeFingerHorizSwipeGesture") == 2
        let wantsVertical = workspaceOverviewGestureEnabled && macTrackpadGesture("TrackpadThreeFingerVertSwipeGesture") == 2
        guard wantsHorizontal || wantsVertical else {
            if workspaceSwipeGestureEnabled || workspaceOverviewGestureEnabled { status = "macOS three-finger swipes are not on three fingers; using raw touch" }
            return
        }
        let dock = makeTap(type: Self.dockControl)
        guard let dock, let envelope = makeTap(type: Self.gesture) else {
            dock.map(discard)
            status = "Event tap unavailable; using raw touch"
            return
        }
        dockTap = dock
        envelopeTap = envelope
        CGEvent.tapEnable(tap: envelope.port, enable: false)
        readsHorizontal = wantsHorizontal
        readsVertical = wantsVertical
        status = "Reading macOS three-finger swipes " + [wantsHorizontal ? "left/right" : nil, wantsVertical ? "up/down" : nil]
            .compactMap(\.self).joined(separator: " and ")
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            wakeObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { DockWorkspaceSwipeSource.shared.reviveIfNeeded() }
            })
        }
    }

    func stop() {
        abandon()
        for tap in [dockTap, envelopeTap].compactMap(\.self) { discard(tap) }
        dockTap = nil
        envelopeTap = nil
        envelopeEnabled = false
        readsHorizontal = false
        readsVertical = false
        wakeObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        wakeObservers.removeAll()
        status = "Disabled"
    }

    private func abandon() {
        horizontal.abandon(workspaces)
        vertical.abandon(overview)
        held.removeAll()
    }

    private func discard(_ tap: (port: CFMachPort, source: CFRunLoopSource)) {
        CGEvent.tapEnable(tap: tap.port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), tap.source, .commonModes)
        CFMachPortInvalidate(tap.port)
    }

    /// Sleep or a locked session can disable a tap, or invalidate its port, while nothing runs to notice.
    private func reviveIfNeeded() {
        guard let dockTap, let envelopeTap else { return }
        if !CFMachPortIsValid(dockTap.port) || !CFMachPortIsValid(envelopeTap.port) {
            syncConfiguration()
        } else if !CGEvent.tapIsEnabled(tap: dockTap.port) {
            CGEvent.tapEnable(tap: dockTap.port, enable: true)
        }
    }

    private func makeTap(type: Int64) -> (port: CFMachPort, source: CFRunLoopSource)? {
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(1) << CGEventMask(type),
                                           callback: dockSwipeTapCallback, userInfo: nil),
              let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return (port, source)
    }

    /// Whether the event is kept from the Dock.
    fileprivate func handle(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Events missed while disabled cannot be finished; start clean.
            abandon()
            if let dockTap { CGEvent.tapEnable(tap: dockTap.port, enable: true) }
            setEnvelope(false)
            return false
        }
        defer {
            setEnvelope(horizontal.ownsGesture || horizontal.isUndecided || vertical.ownsGesture || vertical.isUndecided)
        }
        let subtype = event.getIntegerValueField(Self.field(Self.eventTypeField))
        if subtype == Self.gesture {
            // Held in order with the swipe, so a swipe handed back reaches the Dock whole.
            if horizontal.isUndecided || vertical.isUndecided {
                if let copy = event.copy() { held.append(copy) }
                return true
            }
            return horizontal.ownsGesture || vertical.ownsGesture
        }
        // Physical swipes come from the HID system; another app's synthetic ones are not ours.
        guard subtype == Self.dockControl,
              event.getIntegerValueField(Self.field(Self.hidType)) == Self.dockSwipe,
              event.getIntegerValueField(.eventSourceUnixProcessID) == 0 else { return false }
        let phase = event.getIntegerValueField(Self.field(Self.phase))
        let progress = event.getDoubleValueField(Self.field(Self.progress))
        let time = Double(event.timestamp) / 1_000_000_000
        let verdict: DockSwipeTracker.Verdict
        switch event.getIntegerValueField(Self.field(Self.swipeMotion)) {
            case Self.motionHorizontal where readsHorizontal:
                verdict = horizontal.receive(phase: phase, progress: progress,
                                             endVelocity: event.getDoubleValueField(Self.field(Self.velocityX)), timestamp: time, to: workspaces)
            case Self.motionVertical where readsVertical:
                verdict = vertical.receive(phase: phase, progress: progress,
                                           endVelocity: event.getDoubleValueField(Self.field(Self.velocityY)), timestamp: time, to: overview)
            default:
                return false
        }
        switch verdict {
            case .pass:
                held.removeAll()
                return false
            case .hold:
                if let copy = event.copy() { held.append(copy) }
                return true
            case .swallow:
                held.removeAll()
                return true
            case .replayHeldThenPass:
                for earlier in held { earlier.tapPostEvent(proxy) }
                held.removeAll()
                return false
            case .passWithoutMotion:
                held.removeAll()
                for field in [Self.progress, Self.velocityX, Self.velocityY] { event.setDoubleValueField(Self.field(field), value: 0) }
                return false
        }
    }

    /// Generic gesture events arrive for every trackpad touch, so that tap runs only during a swipe WinMuxX may keep.
    private func setEnvelope(_ enabled: Bool) {
        guard enabled != envelopeEnabled, let envelopeTap else { return }
        envelopeEnabled = enabled
        CGEvent.tapEnable(tap: envelopeTap.port, enable: enabled)
    }

    // Private CGEvent fields and values of Dock swipes, as in NativeDockSwipe.
    private static let eventTypeField = 55, hidType = 110, swipeMotion = 123, progress = 124
    private static let velocityX = 129, velocityY = 130, phase = 132
    private static let gesture: Int64 = 29, dockControl: Int64 = 30, dockSwipe: Int64 = 23
    private static let motionHorizontal: Int64 = 1, motionVertical: Int64 = 2
    private static func field(_ raw: Int) -> CGEventField { CGEventField(rawValue: UInt32(raw))! }
}

private func dockSwipeTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent,
                                  _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // The taps' sources run on the main run loop. These borrowed values stay on that
    // thread for the synchronous callback; neither crosses a task boundary.
    nonisolated(unsafe) let mainThreadProxy = proxy
    nonisolated(unsafe) let mainThreadEvent = event
    let kept = MainActor.assumeIsolated { DockWorkspaceSwipeSource.shared.handle(mainThreadProxy, type, mainThreadEvent) }
    return kept ? nil : Unmanaged.passUnretained(event)
}

/// macOS trackpad gesture settings; 2 assigns the gesture to three fingers.
func macTrackpadGesture(_ key: String) -> Int {
    ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"].compactMap {
        CFPreferencesAppSynchronize($0 as CFString)
        return CFPreferencesCopyAppValue(key as CFString, $0 as CFString) as? Int
    }.max() ?? 0
}

/// "Natural scrolling", unset meaning on. The cache is flushed first: a change made in
/// System Settings does not invalidate this process's copy.
func naturalScrollingEnabled() -> Bool {
    CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    return CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication) as? Bool ?? true
}
