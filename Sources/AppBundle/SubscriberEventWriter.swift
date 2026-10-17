import Foundation

/// A subscriber has one ordered writer. Slow readers are disconnected before
/// their queued events can grow without bound; other subscribers keep draining.
@MainActor
final class SubscriberEventWriter {
    private let maxEvents: Int
    private let maxBytes: Int
    private let send: (Data) async -> Bool
    private let disconnect: () -> Void
    private var pending: [Data] = []
    private var task: Task<Void, Never>?
    private var sending = false
    private(set) var bufferedBytes = 0
    private(set) var isClosed = false
    var bufferedEventCount: Int { pending.count + (sending ? 1 : 0) }

    init(maxEvents: Int = 64, maxBytes: Int = 1024 * 1024,
         send: @escaping (Data) async -> Bool, disconnect: @escaping () -> Void) {
        self.maxEvents = maxEvents
        self.maxBytes = maxBytes
        self.send = send
        self.disconnect = disconnect
    }

    func enqueue(_ payload: Data) {
        guard !isClosed else { return }
        guard bufferedEventCount < maxEvents, payload.count <= maxBytes - bufferedBytes else {
            close()
            return
        }
        pending.append(payload)
        bufferedBytes += payload.count
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in await self?.drain() }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        pending.removeAll()
        bufferedBytes = 0
        sending = false
        task?.cancel()
        task = nil
        disconnect()
    }

    private func drain() async {
        while !pending.isEmpty, !isClosed {
            let payload = pending.removeFirst()
            sending = true
            let succeeded = await send(payload)
            guard !isClosed else { return }
            sending = false
            bufferedBytes -= payload.count
            guard succeeded, !Task.isCancelled else { close(); return }
        }
        task = nil
    }

    isolated deinit { task?.cancel() }
}
