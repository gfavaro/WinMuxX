@testable import Common
import Network
import XCTest

@MainActor
final class NativeIPCDeadlineTest: XCTestCase {
    func testSilentPeerTimesOutAndExplicitCancellationCompletes() async throws {
        let holder = IPCPeerHolder()
        let path = "/tmp/wx-ipc-\(UUID().uuidString).sock"
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .unix(path: path)
        let listener = try NWListener(using: parameters)
        defer { listener.cancel(); holder.close(); try? FileManager.default.removeItem(atPath: path) }
        let ready = expectation(description: "Local listener ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
            if case .failed(let error) = state { XCTFail("Listener failed: \(error)"); ready.fulfill() }
        }
        listener.newConnectionHandler = { peer in
            peer.start(queue: .global())
            Task { @MainActor in holder.add(peer) }
        }
        listener.start(queue: .global())
        await fulfillment(of: [ready], timeout: 2)
        for cancelExplicitly in [false, true] {
            let client = NWConnection(to: .unix(path: path), using: .tcp)
            defer { client.cancel() }
            let connected = await client.startBlocking()
            XCTAssertNil(connected.error)
            let ended = expectation(description: "Receive terminated")
            let task = Task {
                let result = await client.readNonAtomic(timeout: cancelExplicitly ? nil : .milliseconds(50))
                guard case .failure = result else { ended.fulfill(); return XCTFail("Silent peer returned a message") }
                ended.fulfill()
            }
            defer { task.cancel() }
            if cancelExplicitly { task.cancel() }
            await fulfillment(of: [ended], timeout: 2)
        }
    }
}

@MainActor
private final class IPCPeerHolder {
    private var peers: [NWConnection] = []
    private var closed = false
    func add(_ peer: NWConnection) {
        if closed { peer.cancel() } else { peers.append(peer) }
    }
    func close() { closed = true; peers.forEach { $0.cancel() }; peers.removeAll() }
}
