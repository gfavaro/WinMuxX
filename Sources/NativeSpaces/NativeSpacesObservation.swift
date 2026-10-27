import AppKit
import Foundation

/// Event-driven read ownership shared by the diagnostic and the optional app
/// backend. A Space/display/session event immediately invalidates the old read.
@MainActor
public final class NativeSpacesObservation {
    public private(set) var inventory = NativeWorkspaceInventory()
    public var onChange: (@MainActor (NativeWorkspaceInventory, String) -> Void)?
    public var onWindowClosed: (@MainActor (UInt32) -> Void)?
    public var onWindowsChanged: (@MainActor () -> Void)?
    private let read: @Sendable (NativeSpacesSnapshot?, Bool) async throws -> NativeSpacesSnapshot
    private let topology: (@Sendable () async throws -> [NativeSpaceDisplay])?
    private var registrations: [(NotificationCenter, NSObjectProtocol)] = []
    private var task: Task<Void, Never>?
    private var pending: (NativeSpacesReadToken, String, Bool)?
    private var inFlightAllCurrent = false
    private var running = false
    private var auditTask: Task<Void, Never>?
    private var revision: UInt64 = 0
    private var auditFailures = 0
    private let auditInterval: Duration?
    private let observeSystemEvents: Bool
    public private(set) var windowEventsAvailable = false
    public private(set) var snapshotReadCount = 0
    public private(set) var topologyAuditCount = 0
    public private(set) var lastTopologyAuditMilliseconds: Double?
    public private(set) var windowEventCount = 0
    private var windowEventsSubscription: UUID?
    private var windowEventTask: Task<Void, Never>?

    public convenience init(windowIDs: [UInt32]? = nil) {
        let reader = NativeSpacesReader()
        self.init(read: { previous, allCurrent in
            if let windowIDs { return try await reader.snapshot(windowIDs: windowIDs) }
            return try await reader.observationSnapshot(previous: previous?.displays, allCurrentSpaces: allCurrent)
        }, topology: { try await reader.topology() }, auditInterval: .milliseconds(500), observeSystemEvents: true)
    }

    convenience init(read: @escaping @Sendable () async throws -> NativeSpacesSnapshot) {
        self.init(read: { _, _ in try await read() }, topology: nil)
    }

    init(read: @escaping @Sendable (NativeSpacesSnapshot?, Bool) async throws -> NativeSpacesSnapshot,
         topology: (@Sendable () async throws -> [NativeSpaceDisplay])?, auditInterval: Duration? = nil,
         observeSystemEvents: Bool = false) {
        self.read = read
        self.topology = topology
        self.auditInterval = auditInterval
        self.observeSystemEvents = observeSystemEvents
    }

    public func start() {
        guard !running else { return }
        running = true
        if observeSystemEvents { subscribeToSystemEvents() }
        requestRead(event: "initial")
        if topology != nil, let auditInterval {
            auditTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: auditInterval) } catch { return }
                    guard let self else { return }
                    await self.auditTopology()
                }
            }
        }
    }

    /// While true, ordinary window events and app notifications are held instead of
    /// read: a pan's own window moves would otherwise trigger a full read per step.
    /// Closures and Space/display changes are never held. The holder reads once after.
    public var holdsWindowReads: (() -> Bool)?
    /// Every WindowServer window event, with its window when the event names one.
    public var onWindowEvent: ((UInt32?) -> Void)?
    public private(set) var heldEventCount = 0

    private func holds(_ event: String) -> Bool {
        guard holdsWindowReads?() == true,
              !["activeSpaceDidChange", "windowServerSpaceChange", "displayTopologyChanged", "screensDidWake",
                "sessionDidBecomeActive", "stopped"].contains(event) else { return false }
        heldEventCount += 1
        return true
    }

    private func subscribeToSystemEvents() {
        windowEventsSubscription = NativeSpacesWindowEvents.shared.subscribe { [weak self] event in
            guard let self else { return }
            self.windowEventCount += 1
            self.onWindowEvent?(event.windowID)
            if !event.confirmsClosure, !event.changesTopology, self.holds("windowServerWindowChange") { return }
            self.onWindowsChanged?()
            if event.confirmsClosure, let id = event.windowID { self.onWindowClosed?(id) }
            if event.changesTopology { self.requestRead(event: "windowServerSpaceChange") }
            else { self.scheduleWindowRead() }
        }
        windowEventsAvailable = windowEventsSubscription != nil
        let workspace = NSWorkspace.shared.notificationCenter
        for (source, name, label) in [
            (workspace, NSWorkspace.activeSpaceDidChangeNotification, "activeSpaceDidChange"),
            (workspace, NSWorkspace.screensDidWakeNotification, "screensDidWake"),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, "sessionDidBecomeActive"),
            (workspace, NSWorkspace.didLaunchApplicationNotification, "applicationLaunched"),
            (workspace, NSWorkspace.didTerminateApplicationNotification, "applicationTerminated"),
            (workspace, NSWorkspace.didActivateApplicationNotification, "applicationActivated"),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, "displayTopologyChanged"),
        ] {
            let token = source.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.holds(label) else { return }
                    self.requestRead(event: label)
                }
            }
            registrations.append((source, token))
        }
    }

    public func stop() {
        running = false
        revision &+= 1
        auditTask?.cancel()
        auditTask = nil
        windowEventTask?.cancel()
        windowEventTask = nil
        if let windowEventsSubscription { NativeSpacesWindowEvents.shared.unsubscribe(windowEventsSubscription) }
        windowEventsSubscription = nil
        windowEventsAvailable = false
        pending = nil
        inventory.stop()
        task?.cancel()
        // Keep an in-flight task owned until it finishes: restarting must not
        // overlap it with another private API read.
        for (center, token) in registrations { center.removeObserver(token) }
        registrations = []
        onChange?(inventory, "stopped")
    }

    public func requestRead(event: String = "manual") {
        guard running else { return }
        revision &+= 1
        if event != "topologyAudit" { auditFailures = 0 }
        let onlyTopology = ["activeSpaceDidChange", "windowServerSpaceChange", "topologyAudit"].contains(event)
        // A Space event must not erase a simultaneous window/app reconciliation
        // on another display, including one whose in-flight read is superseded.
        let allCurrent = !onlyTopology || pending?.2 == true || (task != nil && inFlightAllCurrent)
        pending = (inventory.invalidate(), event, allCurrent)
        onChange?(inventory, event)
        beginPendingRead()
    }

    public func watchManagedWindows(_ ids: Set<UInt32>) {
        guard running, let windowEventsSubscription else { return }
        windowEventsAvailable = NativeSpacesWindowEvents.shared.watch(ids, subscriber: windowEventsSubscription)
    }

    private func scheduleWindowRead() {
        guard running, windowEventTask == nil else { return }
        windowEventTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            guard let self else { return }
            self.windowEventTask = nil
            self.requestRead(event: "windowServerWindowChange")
        }
    }

    private func beginPendingRead() {
        guard task == nil, running, let (token, event, allCurrent) = pending else { return }
        pending = nil
        snapshotReadCount += 1
        inFlightAllCurrent = allCurrent
        let read = read
        let previous = inventory.lastSnapshot
        task = Task { [weak self] in
            let result: Result<NativeSpacesSnapshot, Error>
            do { result = .success(try await read(previous, allCurrent)) }
            catch { result = .failure(error) }
            guard let self else { return }
            switch result {
                case .success(let snapshot):
                    if self.inventory.publish(snapshot, for: token) { self.auditFailures = 0 }
                case .failure(let error):
                    self.inventory.fail(String(describing: error), for: token)
                    if event == "topologyAudit" { self.auditFailures += 1 }
            }
            self.task = nil
            self.inFlightAllCurrent = false
            if self.running {
                // Superseded completions never expose a stale available snapshot.
                if self.inventory.status != .reading { self.onChange?(self.inventory, event) }
                self.beginPendingRead()
            }
        }
    }

    /// Also callable with injected topology/time in tests. Unchanged audits never
    /// invalidate membership or start full window queries. Stop after three API
    /// failures; a real event/manual refresh re-arms recovery.
    func auditTopology() async {
        guard running, task == nil, auditFailures < 3, let topology else { return }
        let version = revision
        topologyAuditCount += 1
        let started = ContinuousClock.now
        do {
            let current = try await topology()
            guard running, revision == version else { return }
            let duration = started.duration(to: .now).components
            lastTopologyAuditMilliseconds = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
            if inventory.currentSnapshot == nil || current != inventory.lastSnapshot?.displays {
                requestRead(event: "topologyAudit")
            }
        } catch {
            guard running, revision == version else { return }
            auditFailures += 1
            let token = inventory.invalidate()
            inventory.fail(String(describing: error), for: token)
            onChange?(inventory, "topologyAuditFailed")
        }
    }
}
