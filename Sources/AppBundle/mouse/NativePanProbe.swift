import AppKit
import Common

/// Main-thread time per pan component, reset by the probe.
@MainActor let nativePanTiming = NativePanTiming()

@MainActor
final class NativePanTiming {
    private var entries: [String: (count: Int, total: Double, max: Double)] = [:]
    /// Only the probe records; otherwise measuring costs one flag check.
    private(set) var enabled = false
    func reset() { entries = [:] }
    func begin() { entries = [:]; enabled = true }
    func end() { enabled = false }
    func count(_ name: @autoclosure () -> String) {
        guard enabled else { return }
        entries[name(), default: (0, 0, 0)].count += 1
    }
    func record(_ name: String, _ duration: Duration) {
        guard enabled else { return }
        let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        let old = entries[name] ?? (0, 0, 0)
        entries[name] = (old.count + 1, old.total + ms, max(old.max, ms))
    }
    func measure<T>(_ name: String, _ body: () -> T) -> T {
        guard enabled else { return body() }
        let start = ContinuousClock.now
        defer { record(name, start.duration(to: .now)) }
        return body()
    }
    var report: String {
        entries.sorted { $0.value.total > $1.value.total }.map {
            $0.value.total == 0 ? "  \($0.key): \($0.value.count)" :
                String(format: "  %@: %d× total %.0f ms, avg %.1f ms, max %.1f ms", $0.key, $0.value.count, $0.value.total,
                       $0.value.total / Double($0.value.count), $0.value.max)
        }.joined(separator: "\n")
    }
}

/// Posts a trackpad-like Option scroll through the real event tap and samples where
/// the windows of the panned desktop actually are, against where layout asked them
/// to be. The result separates input delivery, layout rate and window movement.
@MainActor
func simulateNativePan() async -> String {
    // Pan toward whichever side has room, then back, so a clamped edge never hides lag.
    guard let workspace = sortedMonitors.lazy.compactMap(nativeActiveDesktop(on:)).first(where: { $0.arrangement == .scrolling }) else {
        return await simulateNativePan(stepDelta: -10)
    }
    let metrics = workspace.scrollingMetrics
    let roomRight = metrics.clampedOffset(.greatestFiniteMagnitude) - workspace.scrollingOffset
    let first = roomRight > workspace.scrollingOffset ? -10.0 : 10.0
    let out = await simulateNativePan(stepDelta: first)
    try? await Task.sleep(for: .milliseconds(600))
    return out + "\n" + (await simulateNativePan(stepDelta: -first))
}

/// Collects on-screen window x positions off the main thread.
private final class PanSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private(set) var samples: [(time: Double, x: [UInt32: CGFloat])] = []
    func stop() { lock.withLock { running = false } }
    var isRunning: Bool { lock.withLock { running } }
    func append(_ sample: (Double, [UInt32: CGFloat])) { lock.withLock { samples.append(sample) } }
    var all: [(time: Double, x: [UInt32: CGFloat])] { lock.withLock { samples } }
}

@MainActor
func simulateNativePan(steps: Int = 120, stepDelta: Double, interval: Duration = .milliseconds(8)) async -> String {
    guard runtime.workspaceBackend.nativeTilingEnabled else { return "Native tiling is not active" }
    guard CGPreflightPostEventAccess() else { return "WinMuxX cannot post events (Accessibility)" }
    guard let monitor = sortedMonitors.first(where: { nativeActiveDesktop(on: $0)?.arrangement == .scrolling }),
          let workspace = nativeActiveDesktop(on: monitor) else {
        return "No visible scrolling desktop"
    }
    let point = monitor.rect.center
    let windows = workspace.allLeafWindowsRecursive
    let ids = Set(windows.map(\.windowId))
    let start = ContinuousClock.now
    @Sendable func seconds(_ instant: ContinuousClock.Instant) -> Double {
        let d = start.duration(to: instant)
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
    func post(_ delta: Double, phase: Int64) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: Int32(delta), wheel3: 0) else { return }
        event.flags = .maskAlternate
        event.location = point
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: delta)
        event.post(tap: .cghidEventTap)
    }
    let sampler = PanSampler()
    Thread.detachNewThread {
        while sampler.isRunning {
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            var x: [UInt32: CGFloat] = [:]
            for entry in info {
                guard let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value, ids.contains(id),
                      let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat], let value = bounds["X"] else { continue }
                x[id] = value
            }
            sampler.append((seconds(.now), x))
            usleep(4000)
        }
    }
    let before = workspace.scrollingOffset
    nativePanTiming.begin()
    defer { nativePanTiming.end() }
    try? await Task.sleep(for: .milliseconds(50))
    // Where each window should be once the layout for this input has run.
    let base = Dictionary(windows.compactMap { w in w.lastAppliedLayoutPhysicalRect.map { (w.windowId, $0.minX) } }, uniquingKeysWith: { a, _ in a })
    let widths = Dictionary(windows.compactMap { w in w.lastAppliedLayoutPhysicalRect.map { (w.windowId, $0.width) } }, uniquingKeysWith: { a, _ in a })
    let screen = monitor.rect
    var intended: [(time: Double, offset: CGFloat)] = [(seconds(.now), before)]
    var late: [Double] = []
    for step in 0..<steps {
        let due = start.advanced(by: .milliseconds(50) + interval * step)
        try? await Task.sleep(until: due, clock: .continuous)
        late.append(seconds(.now) - seconds(due))
        post(stepDelta, phase: step == 0 ? 1 : 2)
        await Task.yield()
        intended.append((seconds(.now), workspace.scrollingOffset))
    }
    post(0, phase: 4)
    let inputEnd = seconds(.now)
    let finalOffset = workspace.scrollingOffset
    try? await Task.sleep(for: .milliseconds(800))
    sampler.stop()
    let samples = sampler.all
    // Lag per window: how long ago the input asked for the position the window shows now.
    var lags: [Double] = []
    var updates = 0
    var previous: [UInt32: CGFloat] = [:]
    for sample in samples where sample.time <= inputEnd + 0.3 {
        for (id, x) in sample.x {
            guard let x0 = base[id], let width = widths[id] else { continue }
            if let old = previous[id], old != x { updates += 1 }
            previous[id] = x
            let shown = before + (x0 - x) // the offset this window position corresponds to
            // Columns kept at the display edges do not travel; measure windows in view.
            guard x > screen.minX + 2, x + width < screen.maxX - 2 else { continue }
            guard sample.time <= inputEnd, let match = intended.last(where: { abs($0.offset - shown) <= abs(stepDelta) }) else { continue }
            lags.append(max(0, sample.time - match.time))
        }
    }
    let settled = samples.first { sample in
        sample.time > inputEnd && sample.x.allSatisfy { id, x in base[id].map { abs((before + ($0 - x)) - finalOffset) <= 2 } ?? true }
    }.map { $0.time - inputEnd }
    lags.sort()
    func pct(_ p: Double) -> String { lags.isEmpty ? "n/a" : String(format: "%.0f ms", lags[min(lags.count - 1, Int(Double(lags.count) * p))] * 1000) }
    return """
        Simulated pan: \(steps) events in \(String(format: "%.2f", inputEnd - 0.05)) s (posting late by max \(String(format: "%.0f", (late.max() ?? 0) * 1000)) ms), offset \(Int(before)) -> \(Int(finalOffset))
        Window lag behind input: median \(pct(0.5)), p90 \(pct(0.9)), max \(pct(1)) over \(lags.count) samples
        Window position updates: \(updates) across \(ids.count) windows (\(String(format: "%.0f", Double(updates) / max(inputEnd - 0.05, 0.01) / Double(max(ids.count, 1))))/s per window), \(samples.count) samples
        Windows settled \(settled.map { String(format: "%.0f ms", $0 * 1000) } ?? "not within 800 ms") after the last event
        \(runtime.workspaceBackend.nativeTiling.scrollingLayoutTiming)
        Main-thread time and counts:
        \(nativePanTiming.report)
        """
}
