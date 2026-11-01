import AppKit
import Foundation
import NativeSpaces

/// Read-only: safe beside the installed virtual manager. Never starts a WM,
/// captures pixels, requests permissions, changes settings, switches or moves.
@main
struct NativeSpacesProbe {
    @MainActor
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args == ["--help"] {
            print("USAGE: winmuxx-native-spaces-probe [--watch <seconds>] [--window-id <id>]...\nRead-only JSON Lines. Watch is event-driven; 1–300 seconds. No permission prompts.")
            return
        }
        var watch: Double?
        var ids: [UInt32] = []
        var index = 0
        while index < args.count {
            guard index + 1 < args.count else { fail("missing argument value") }
            switch args[index] {
            case "--watch":
                guard watch == nil, let value = Double(args[index + 1]), value.isFinite, (1...300).contains(value) else { fail("watch must be 1–300 seconds") }
                watch = value
            case "--window-id":
                guard let id = UInt32(args[index + 1]), id != 0, ids.count < 1024 else { fail("invalid window ID or read budget exceeded") }
                ids.append(id)
            default: fail("unknown option \(args[index])")
            }
            index += 2
        }
        // Workspace notifications require the AppKit event loop, not just an
        // async-main executor. This process has no windows or menu bar.
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let session = ProbeSession(windowIDs: ids.isEmpty ? nil : ids, watch: watch)
        withExtendedLifetime(session) {
            session.start()
            application.run()
        }
    }

    static func emit(_ snapshot: NativeSpacesSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(snapshot)
            try FileHandle.standardOutput.write(contentsOf: data + Data([0x0A]))
        } catch {
            fail("could not write diagnostic snapshot: \(error)")
        }
    }

    static func log(_ text: String) {
        FileHandle.standardError.write(Data("\(text)\n".utf8))
    }

    static func fail(_ reason: String) -> Never {
        log(reason)
        exit(1)
    }
}

@MainActor
private final class ProbeSession {
    private let reader = NativeSpacesReader()
    private let windowIDs: [UInt32]?
    private let watch: Double?
    private var registrations: [(NotificationCenter, NSObjectProtocol)] = []
    private var timeout: Task<Void, Never>?
    private var reading = false
    private var pendingEvent: String?
    private var pendingTime: ContinuousClock.Instant?
    private var successfulReads = 0

    init(windowIDs: [UInt32]?, watch: Double?) {
        self.windowIDs = windowIDs
        self.watch = watch
    }

    func start() {
        if let watch {
            observe()
            timeout = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(watch)) }
                catch { return }
                finish()
            }
        }
        requestRead(event: "initial", at: .now)
    }

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        for (source, name, label) in [
            (workspace, NSWorkspace.activeSpaceDidChangeNotification, "activeSpaceDidChange"),
            (workspace, NSWorkspace.screensDidWakeNotification, "screensDidWake"),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, "displayTopologyChanged"),
        ] {
            let token = source.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.requestRead(event: label, at: .now) }
            }
            registrations.append((source, token))
        }
    }

    private func requestRead(event: String, at observedAt: ContinuousClock.Instant) {
        // One in-flight read and one newest pending event, with no idle polling.
        guard !reading else {
            pendingEvent = event
            pendingTime = observedAt
            return
        }
        reading = true
        Task { @MainActor in
            do {
                let snapshot = try await reader.snapshot(windowIDs: windowIDs)
                NativeSpacesProbe.emit(snapshot)
                successfulReads += 1
                let elapsed = observedAt.duration(to: .now).components
                let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
                NativeSpacesProbe.log("event: \(event); observed-to-published-ms: \(milliseconds)")
            } catch { NativeSpacesProbe.log("read rejected for \(event): \(error)") }
            reading = false
            guard watch != nil else { finish() }
            if let event = pendingEvent, let at = pendingTime {
                pendingEvent = nil
                pendingTime = nil
                requestRead(event: event, at: at)
            }
        }
    }

    private func finish() -> Never {
        timeout?.cancel()
        for (center, token) in registrations { center.removeObserver(token) }
        registrations = []
        exit(successfulReads > 0 ? 0 : 1)
    }
}
