import CoreGraphics

/// One entry of an app's raw AX window sources, as `doctor` reports it.
struct AxWindowProbe: Equatable, Sendable {
    let source: String
    var windowId: UInt32? = nil
    /// Why the element did not resolve to a window id.
    var idError: String? = nil
    var frame: CGRect? = nil
    var role: String? = nil
    var subrole: String? = nil
    /// Why the source itself could not be read.
    var failure: String? = nil
}

/// A tracked window that WinMux can neither move nor park, with what the app and
/// WindowServer expose instead. Titles are left out: doctor output is shared.
struct UnreachableWindowDiagnosis: Equatable, Sendable {
    let windowId: UInt32
    let appName: String
    let workspace: String?
    let windowServerFrame: CGRect?
    let axWindows: [AxWindowProbe]
    let appWindowServerWindows: [WindowServerWindowSummary]
}

struct WindowServerWindowSummary: Equatable, Sendable {
    let id: UInt32
    let frame: CGRect
    let onScreen: Bool
}

func windowReachabilityReport(trackedCount: Int, unreachable: [UnreachableWindowDiagnosis]) -> [String] {
    guard !unreachable.isEmpty else { return ["  all \(trackedCount) tracked windows are reachable through Accessibility"] }
    var lines: [String] = []
    for item in unreachable {
        lines.append("  window \(item.windowId) (\(item.appName), workspace \(item.workspace ?? "none")) is not reachable through "
            + "Accessibility: WinMux cannot move or park it. WindowServer: \(describe(item.windowServerFrame))")
        lines.append("    \(item.appName) Accessibility windows, unfiltered:")
        if item.axWindows.isEmpty { lines.append("      none") }
        for probe in item.axWindows {
            if let failure = probe.failure {
                lines.append("      \(probe.source): unreadable (\(failure))")
            } else {
                let id = probe.windowId.map(String.init) ?? "none (\(probe.idError ?? "unknown"))"
                lines.append("      \(probe.source): id=\(id) role=\(probe.role ?? "-") subrole=\(probe.subrole ?? "-") frame=\(describe(probe.frame))")
            }
        }
        let shown = item.appWindowServerWindows.prefix(12)
        lines.append("    \(item.appName) WindowServer windows (layer 0): " + (shown.isEmpty ? "none" : shown.map {
            "\($0.id) \($0.onScreen ? "on" : "off") \(describe($0.frame))"
        }.joined(separator: "; ")) + (item.appWindowServerWindows.count > shown.count ? "; …" : ""))
    }
    return lines
}

private func describe(_ frame: CGRect?) -> String {
    guard let frame else { return "unknown" }
    return "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
}
