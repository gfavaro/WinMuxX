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
        /// Percentiles of retained samples, not full-session history.
        let latencyPercentilesMilliseconds: [String: [String: Double]]
    }

    /// Fixed-capacity FIFO: overwriting the oldest sample is O(1), unlike removeFirst().
    private struct SampleRing {
        var values: [Double] = []
        var next = 0

        mutating func append(_ value: Double, limit: Int) -> Bool {
            if values.count < limit {
                values.append(value)
                return false
            }
            values[next] = value
            next = (next + 1) % limit
            return true
        }

        var chronological: [Double] {
            guard next != 0 else { return values }
            return Array(values[next...]) + Array(values[..<next])
        }
    }

    /// Nearest-rank percentile of observed (retained) samples.
    static func percentile(_ percentile: Int, samples: [Double]) -> Double? {
        guard !samples.isEmpty, (0...100).contains(percentile) else { return nil }
        let sorted = samples.sorted()
        let rank = max(1, Int(ceil(Double(percentile) * Double(sorted.count) / 100)))
        return sorted[rank - 1]
    }

    private struct State {
        var enabled = false
        var generation: UInt64 = 0
        var counts: [String: Int] = [:]
        var failures = 0
        var samples: [String: SampleRing] = [:]
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
            // Non-finite times must not poison JSON diagnostics.
            guard duration.isFinite else { return }
            let value = max(0, duration * 1000)
            var samples = s.samples[operation.rawValue, default: SampleRing()]
            if samples.append(value, limit: sampleLimit) { s.dropped += 1 }
            s.samples[operation.rawValue] = samples
        }
    }

    func snapshot() -> Snapshot {
        state.withLock { s in
            let samples = s.samples.mapValues(\.chronological)
            let percentiles = samples.mapValues { durations in
                ["p50": Self.percentile(50, samples: durations)!,
                 "p95": Self.percentile(95, samples: durations)!,
                 "p99": Self.percentile(99, samples: durations)!]
            }
            return Snapshot(operations: s.counts, failures: s.failures,
                            durationsMilliseconds: samples, droppedSamples: s.dropped,
                            latencyPercentilesMilliseconds: percentiles)
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
