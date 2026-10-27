import AppKit
import Common

/// Posts a trackpad-like Option scroll through the real event tap and samples where
/// the windows of the panned desktop actually are, against where layout asked them
/// to be. The result separates input delivery, layout rate and window movement.
@MainActor
func simulateNativePan() async -> String {
    // Pan toward whichever side has room, then back, so a clamped edge never hides lag.
    guard let workspace = sortedMonitors.first(where: { $0.activeWorkspace.arrangement == .scrolling })?.activeWorkspace else {
        return await simulateNativePan(stepDelta: -10)
    }
    let metrics = workspace.scrollingMetrics
    let roomRight = metrics.clampedOffset(.greatestFiniteMagnitude) - workspace.scrollingOffset
    let first = roomRight > workspace.scrollingOffset ? -10.0 : 10.0
    let out = await simulateNativePan(stepDelta: first)
    try? await Task.sleep(for: .milliseconds(600))
    return out + "\n" + (await simulateNativePan(stepDelta: -first))
}

@MainActor
func simulateNativePan(steps: Int = 120, stepDelta: Double, interval: Duration = .milliseconds(8)) async -> String {
    guard runtime.workspaceBackend.nativeTilingEnabled else { return "Native tiling is not active" }
    guard CGPreflightPostEventAccess() else { return "WinMuxX cannot post events (Accessibility)" }
    guard let monitor = sortedMonitors.first(where: { $0.activeWorkspace.arrangement == .scrolling }) else {
        return "No visible scrolling desktop"
    }
    let workspace = monitor.activeWorkspace
    let point = monitor.rect.center
    let ids = Set(workspace.allLeafWindowsRecursive.map(\.windowId))
    var samples: [(time: Double, error: Double, actual: [UInt32: CGFloat])] = []
    let start = ContinuousClock.now
    func elapsed() -> Double {
        let d = start.duration(to: .now)
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
    func sample() {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        var actual: [UInt32: CGFloat] = [:]
        for entry in info {
            guard let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value, ids.contains(id),
                  let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat], let x = bounds["X"] else { continue }
            actual[id] = x
        }
        let errors = workspace.allLeafWindowsRecursive.compactMap { window -> Double? in
            guard let target = window.lastAppliedLayoutPhysicalRect, let x = actual[window.windowId] else { return nil }
            return abs(Double(x - target.minX))
        }
        samples.append((elapsed(), errors.max() ?? 0, actual))
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
    let before = workspace.scrollingOffset
    runtime.workspaceBackend.nativeTiling.probeCounts = [:]
    sample()
    for step in 0..<steps {
        post(stepDelta, phase: step == 0 ? 1 : 2)
        try? await Task.sleep(for: interval)
        sample()
    }
    post(0, phase: 4)
    let inputEnd = elapsed()
    for _ in 0..<60 { try? await Task.sleep(for: .milliseconds(16)); sample() }
    let during = samples.filter { $0.time <= inputEnd }
    var moves = 0
    for (previous, next) in zip(samples, samples.dropFirst()) where previous.actual != next.actual { moves += 1 }
    let movesDuring = zip(during, during.dropFirst()).filter { $0.0.actual != $0.1.actual }.count
    let settledAt = samples.last { $0.error > 2 }.map { $0.time - inputEnd } ?? 0
    let meanError = during.map(\.error).reduce(0, +) / Double(max(during.count, 1))
    return """
        Simulated pan: \(steps) scroll events over \(String(format: "%.2f", inputEnd)) s, offset \(Int(before)) -> \(Int(workspace.scrollingOffset))
        Window positions changed in \(movesDuring) of \(during.count) samples while scrolling (\(String(format: "%.0f", Double(movesDuring) / inputEnd))/s), \(moves) in total
        Distance between target and actual window: mean \(String(format: "%.0f", meanError)) px, max \(String(format: "%.0f", during.map { $0.error }.max() ?? 0)) px
        Windows reached their targets \(String(format: "%.2f", settledAt)) s after the last event
        \(runtime.workspaceBackend.nativeTiling.scrollingLayoutTiming)
        \(runtime.workspaceBackend.nativeTiling.probeCounts.sorted { $0.key < $1.key }.map { "  \($0.key): \($0.value)" }.joined(separator: "\n"))
        """
}
