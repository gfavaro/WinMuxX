import Foundation
import os

/// One active write and one replaceable snapshot. Encoding and filesystem work
/// stay on the serial worker; a clean quit drains it before writing final state.
final class RestartStateWriter: Sendable {
    typealias Write = @Sendable (PersistedFrozenWorldEnvelope, URL) throws -> Void
    private struct Request: Equatable, Sendable {
        let envelope: PersistedFrozenWorldEnvelope
        let url: URL
    }
    private struct State {
        var pending: Request?
        var running = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "WinMuxX.restart-state", qos: .utility)
    private let write: Write
    // Accessed exclusively on queue.
    nonisolated(unsafe) private var lastSaved: Request?

    init(write: @escaping Write = { envelope, url in _ = try saveRestartEnvelope(envelope, to: url) }) {
        self.write = write
    }

    func submit(_ envelope: PersistedFrozenWorldEnvelope, to url: URL) {
        state.withLock { state in
            state.pending = Request(envelope: envelope, url: url)
            guard !state.running else { return }
            state.running = true
            queue.async { self.drain() }
        }
    }

    func flush(_ envelope: PersistedFrozenWorldEnvelope? = nil, to url: URL? = nil) throws {
        try queue.sync {
            if let envelope, let url { try save(Request(envelope: envelope, url: url)) }
        }
    }

    private func drain() {
        while let request = state.withLock({ state -> Request? in
            guard let pending = state.pending else { state.running = false; return nil }
            state.pending = nil
            return pending
        }) {
            do { try save(request) }
            catch { NSLog("WinMuxX: unable to save workspace state: %@", error.localizedDescription) }
        }
    }

    private func save(_ request: Request) throws {
        guard lastSaved != request else { return }
        try write(request.envelope, request.url)
        lastSaved = request
    }
}
