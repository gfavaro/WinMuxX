import CoreGraphics

enum AxWindowReachability: Equatable, Sendable {
    case reachable
    /// The app answers but lists no element for the window.
    case unreachable
    /// The app object holding the window was destroyed; it has no AX thread.
    case appRetired
    case unknown(String)
}

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

struct WindowServerWindowSummary: Equatable, Sendable {
    let id: UInt32
    let frame: CGRect
    let onScreen: Bool
}

/// A tracked window a frame write may not reach. Titles are left out: doctor output is shared.
struct WindowReachabilityFinding: Equatable, Sendable {
    let windowId: UInt32
    let appName: String
    let workspace: String?
    let windowServerFrame: CGRect?
    let reachability: AxWindowReachability
    /// For a retired app object: whether a live one is registered for the same process.
    var liveAppRegistered = false
}

/// What one app exposes, probed once however many of its windows are listed.
struct AppReachabilityDetail: Equatable, Sendable {
    let appName: String
    /// Nil when the app was not probed because it did not answer.
    let axWindows: [AxWindowProbe]?
    let windowServerWindows: [WindowServerWindowSummary]
}

private let detailLimit = 12

func windowReachabilityReport(trackedCount: Int, findings: [WindowReachabilityFinding], details: [AppReachabilityDetail]) -> [String] {
    guard !findings.isEmpty else { return ["  all \(trackedCount) tracked windows are reachable through Accessibility"] }
    var lines: [String] = []
    for item in findings {
        let window = "window \(item.windowId) (\(item.appName), workspace \(item.workspace ?? "none"))"
        let frame = "WindowServer: \(describe(item.windowServerFrame))"
        switch item.reachability {
        case .reachable: continue
        case .unreachable:
            lines.append("  \(window) has no Accessibility element, so WinMux cannot move or park it. \(frame)")
        case .appRetired:
            lines.append("  \(window) belongs to a destroyed app object while \(item.appName) still runs "
                + "(live object registered: \(item.liveAppRegistered ? "yes" : "no")), so WinMux cannot move or park it. \(frame)")
        case .unknown(let reason):
            lines.append("  \(window) could not be checked: \(reason). \(frame)")
        }
    }
    for app in details {
        guard let axWindows = app.axWindows else {
            lines.append("  \(app.appName) Accessibility windows: not probed, the app did not answer")
            lines.append(windowServerLine(app))
            continue
        }
        lines.append("  \(app.appName) Accessibility windows, unfiltered:")
        if axWindows.isEmpty { lines.append("    none") }
        for probe in axWindows.prefix(detailLimit) {
            if let failure = probe.failure {
                lines.append("    \(probe.source): unreadable (\(failure))")
            } else {
                let id = probe.windowId.map(String.init) ?? "none (\(probe.idError ?? "unknown"))"
                lines.append("    \(probe.source): id=\(id) role=\(probe.role ?? "-") subrole=\(probe.subrole ?? "-") frame=\(describe(probe.frame))")
            }
        }
        if axWindows.count > detailLimit { lines.append("    …") }
        lines.append(windowServerLine(app))
    }
    return lines
}

private func windowServerLine(_ app: AppReachabilityDetail) -> String {
    let shown = app.windowServerWindows.prefix(detailLimit)
    return "  \(app.appName) WindowServer windows (layer 0): " + (shown.isEmpty ? "none" : shown.map {
        "\($0.id) \($0.onScreen ? "on" : "off") \(describe($0.frame))"
    }.joined(separator: "; ")) + (app.windowServerWindows.count > shown.count ? "; …" : "")
}

private func describe(_ frame: CGRect?) -> String {
    guard let frame else { return "unknown" }
    return "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
}
