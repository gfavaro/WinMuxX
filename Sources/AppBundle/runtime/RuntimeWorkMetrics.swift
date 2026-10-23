import ApplicationServices
import Foundation
import os

/// Opt-in, bounded measurements for native window-management work.
/// The lock permits recording directly on an application's AX thread.
final class RuntimeWorkMetrics: @unchecked Sendable {
    static let shared = RuntimeWorkMetrics()
    enum Operation: String, Codable, CaseIterable { case axRead, axWrite, axAction, runLoopQueueWait }
    struct Snapshot: Codable, Equatable {
        let operations: [String: Int]
        let failures: Int
        let durationsMilliseconds: [String: [Double]]
        let droppedSamples: Int
    }
    private struct State {
        var enabled = false
        var generation: UInt64 = 0
        var counts: [String: Int] = [:]
        var failures = 0
        var samples: [String: [Double]] = [:]
        var dropped = 0
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let sampleLimit: Int

    init(sampleLimit: Int = 256) { self.sampleLimit = max(1, sampleLimit) }

    var isRecording: Bool { state.withLock { $0.enabled } }

    @discardableResult func start() -> UInt64 {
        state.withLock { s in
            s = State(enabled: true, generation: s.generation &+ 1)
            return s.generation
        }
    }

    func stop() { state.withLock { s in s = State(generation: s.generation &+ 1) } }

    func record(_ operation: Operation, failed: Bool, duration: Double, generation: UInt64) {
        state.withLock { s in
            guard s.enabled, s.generation == generation else { return }
            s.counts[operation.rawValue, default: 0] += 1
            if failed { s.failures += 1 }
            let value = max(0, duration * 1000)
            var samples = s.samples[operation.rawValue, default: []]
            if samples.count == sampleLimit { samples.removeFirst(); s.dropped += 1 }
            samples.append(value)
            s.samples[operation.rawValue] = samples
        }
    }

    func snapshot() -> Snapshot {
        state.withLock { s in
            Snapshot(operations: s.counts, failures: s.failures,
                     durationsMilliseconds: s.samples, droppedSamples: s.dropped)
        }
    }

    func generationIfRecording() -> UInt64? {
        state.withLock { $0.enabled ? $0.generation : nil }
    }
}

@discardableResult
func measuredAXOperation(_ operation: RuntimeWorkMetrics.Operation, _ body: () -> AXError) -> AXError {
    let metrics = RuntimeWorkMetrics.shared
    let generation = metrics.generationIfRecording()
    let started = generation.map { _ in DispatchTime.now().uptimeNanoseconds }
    let error = body()
    if let generation, let started {
        metrics.record(operation, failed: error != .success,
            duration: Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000,
            generation: generation)
    }
    return error
}
