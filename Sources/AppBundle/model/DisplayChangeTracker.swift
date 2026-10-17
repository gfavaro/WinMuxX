import Common

/// Seeded at startup; compared only after a successful settled topology refresh.
struct DisplayChangeTracker {
    private var known: Set<String>?

    mutating func seed(_ identities: Set<String>) { known = identities }

    mutating func update(_ identities: Set<String>) -> [String: String]? {
        defer { known = identities }
        guard let previous = known, previous != identities else { return nil }
        return [WINMUX_DISPLAYS: String(identities.count), WINMUX_PREV_DISPLAYS: String(previous.count)]
    }
}

@MainActor
func displayTopologyIdentities(_ monitors: [Monitor]) -> Set<String> {
    Set(monitors.map { $0.displayUUID ?? "\($0.name):\($0.rect.topLeftCorner)" })
}

@MainActor
func runSettledDisplayChangeHook() {
    guard runtime.displays.displayHookPending else { return }
    runtime.displays.displayHookPending = false
    guard let environment = runtime.displays.changes.update(displayTopologyIdentities(monitors)),
          let token: RunSessionGuard = .isServerEnabled, !config.onDisplayChanged.isEmpty else { return }
    let commands = config.onDisplayChanged
    let context = CmdEnv.defaultEnv.withFocus(focus).copy(\.extraEnvironment, environment)
    runtime.displays.displayChangeTask?.cancel()
    runtime.displays.displayChangeTask = runtime.task {
        guard TrayMenuModel.shared.isEnabled else { return }
        do {
            try Task.checkCancellation()
            try await runLightSession(.onDisplayChanged, token,
                                      shouldSchedulePostRefresh: !commands.canSkipPostCommandRefresh) {
                _ = try await commands.runCmdSeq(context, .emptyStdin)
            }
        } catch { debugFocusLog("Display change hook failed: \(error)") }
    }
}
