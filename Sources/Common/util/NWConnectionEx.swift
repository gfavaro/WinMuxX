import Network
import Foundation

extension NWConnection {
    public func writeAtomic(_ msg: Codable, _ encoder: JSONEncoder = JSONEncoder()) async -> ((), error: NWError?) {
        let payload = Result { try encoder.encode(msg) }.getOrDie()
        guard payload.count <= maximumIPCFrameBytes else { return ((), .posix(.EMSGSIZE)) }
        var data = withUnsafeBytes(of: UInt32(payload.count)) { Data($0) }
        check(data.count == 4)
        data.append(payload)
        return await withCheckedContinuation { cont in
            send(content: data, completion: .contentProcessed { error in
                if let error {
                    cont.resume(returning: ((), error))
                } else {
                    cont.resume(returning: ((), nil))
                }
            })
        }
    }

    public func startBlocking() async -> ((), error: NWError?) {
        await withCheckedContinuation { cont in
            let isDone = IsDone()
            stateUpdateHandler = { state in
                Task {
                    let error: NWError?
                    switch state {
                        case .cancelled: error = .posix(.ECANCELED)
                        case .preparing, .setup: return
                        case .ready: error = nil
                        case .failed(let e), .waiting(let e): error = e
                        @unknown default: die("Unknown NWConnection.State: \(state)")
                    }
                    // Make sure to resume continuation only once
                    if await isDone.markAsDone().wasAlreadyDone {
                        return
                    }
                    self.stateUpdateHandler = nil
                    cont.resume(returning: ((), error))
                }
            }
            start(queue: .global())
        }
    }

    public func readTillError() async {
        await withTaskCancellationHandler {
            while !Task.isCancelled {
                let isError = await withCheckedContinuation { continuation in
                    receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
                        continuation.resume(returning: error != nil || complete || data == nil || data?.isEmpty == true)
                    }
                }
                if isError { return }
            }
        } onCancel: { self.cancel() }
    }

    public func readNonAtomic(timeout: Duration? = nil) async -> Result<Data, NWError> {
        let deadline = timeout.map { timeout in
            Task {
                do { try await Task.sleep(for: timeout) } catch { return }
                self.cancel()
            }
        }
        defer { deadline?.cancel() }
        return await withTaskCancellationHandler {
            await readIPCFrame { minimum, maximum in
                await withCheckedContinuation { continuation in
                    self.receive(minimumIncompleteLength: minimum, maximumLength: maximum) { data, _, complete, error in
                        if let error { continuation.resume(returning: .failure(error)) }
                        else { continuation.resume(returning: .success(IPCReadChunk(data: data ?? Data(), complete: complete))) }
                    }
                }
            }
        } onCancel: { self.cancel() }
    }

}

private actor IsDone {
    private var isDone: Bool = false

    func markAsDone() -> (wasAlreadyDone: Bool, ()) {
        let old = isDone
        isDone = true
        return (old, ())
    }
}
