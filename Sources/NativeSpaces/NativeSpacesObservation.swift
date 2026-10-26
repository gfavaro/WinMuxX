import AppKit
import Foundation

/// Event-driven read ownership shared by the diagnostic and the optional app
/// backend. A Space/display/session event immediately invalidates the old read.
@MainActor
public final class NativeSpacesObservation {
    public private(set) var inventory = NativeWorkspaceInventory()
    public var onChange: (@MainActor (NativeWorkspaceInventory, String) -> Void)?
    private let read: @Sendable () async throws -> NativeSpacesSnapshot
    private var registrations: [(NotificationCenter, NSObjectProtocol)] = []
    private var task: Task<Void, Never>?
    private var pending: (NativeSpacesReadToken, String)?
    private var running = false

    public convenience init(windowIDs: [UInt32]? = nil) {
        let reader = NativeSpacesReader()
        self.init { try await reader.snapshot(windowIDs: windowIDs) }
    }

    init(read: @escaping @Sendable () async throws -> NativeSpacesSnapshot) {
        self.read = read
    }

    public func start() {
        guard !running else { return }
        running = true
        let workspace = NSWorkspace.shared.notificationCenter
        for (source, name, label) in [
            (workspace, NSWorkspace.activeSpaceDidChangeNotification, "activeSpaceDidChange"),
            (workspace, NSWorkspace.screensDidWakeNotification, "screensDidWake"),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, "sessionDidBecomeActive"),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, "displayTopologyChanged"),
        ] {
            let token = source.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.requestRead(event: label) }
            }
            registrations.append((source, token))
        }
        requestRead(event: "initial")
    }

    public func stop() {
        running = false
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
        pending = (inventory.invalidate(), event)
        onChange?(inventory, event)
        beginPendingRead()
    }

    private func beginPendingRead() {
        guard task == nil, running, let (token, event) = pending else { return }
        pending = nil
        let read = read
        task = Task { [weak self] in
            let result: Result<NativeSpacesSnapshot, Error>
            do { result = .success(try await read()) }
            catch { result = .failure(error) }
            guard let self else { return }
            switch result {
                case .success(let snapshot): _ = self.inventory.publish(snapshot, for: token)
                case .failure(let error): self.inventory.fail(String(describing: error), for: token)
            }
            self.task = nil
            if self.running {
                // Superseded completions never expose a stale available snapshot.
                if self.inventory.status != .reading { self.onChange?(self.inventory, event) }
                self.beginPendingRead()
            }
        }
    }
}
