import AppKit
import Common
import Foundation

@MainActor public func initAppBundle() {
    Task {
        do { try await startAppBundle() }
        catch { NSLog("WinMuxX startup failed: %@", String(describing: error)) }
    }
}

@MainActor private func startAppBundle() async throws {
    initTerminationHandler()
    isCli = false
    AssistiveTechnology.startObserving()
    initServerArgs()
    var bootstrappedConfigUrl: URL? = nil
    do {
        bootstrappedConfigUrl = try ensureBootstrapConfigExistsIfNeeded()
        let editable = bootstrappedConfigUrl ?? preferredEditableConfigUrl()
        if FileManager.default.fileExists(atPath: editable.path) {
            try migrateLegacyConfiguration(at: editable)
        }
    } catch {
        MessageModel.shared.message = Message(
            description: "Config Bootstrap Error",
            body: error.localizedDescription,
        )
    }
    if try await !reloadConfig(forceConfigUrl: bootstrappedConfigUrl) {
        var out = ""
        check(
            try await reloadConfig(forceConfigUrl: defaultConfigUrl, stdout: &out),
            """
            Can't load default config. Your installation is probably corrupted.
            Please don't modify '\(defaultConfigUrl)'

            \(out)
            """,
        )
    }
    if isDebug { await toggleReleaseServerIfDebug(.off) }
    MonitorConfigurationObserver.shared.prepareForStartup()

    checkAccessibilityPermissions()
    requestScreenRecordingPermissionsIfNeeded()
    startUnixSocketServer()
    GlobalObserver.initObserver()
    MonitorConfigurationObserver.shared.startObserving()
    let didLoadPersistedFrozenWorld = loadPersistedFrozenWorldForStartupIfPresent()
    Workspace.reconcileWorkspaceState() // init workspaces
    _ = Workspace.all.first?.focusWorkspace()
    await runStartupSessions(restoredWorld: didLoadPersistedFrozenWorld)
    reloadConfigIfSavedDuringStartup()
    schedulePersistedFrozenWorldSave()
    showSetupCheckIfNeeded()
}

/// Discovers the open windows, applies the startup layout, then lets native events through.
/// An app that does not answer Accessibility while it launches fails a session. Startup still
/// finishes: until it does every native event is ignored, and nothing would run it again. The
/// refresh scheduled at the end discovers the windows again, and the saved placement of a
/// window not seen yet stays pending.
@MainActor
func runStartupSessions(restoredWorld: Bool) async {
    do {
        try await runRefreshSessionBlocking(.startup, layoutWorkspaces: false)
    } catch {
        NSLog("WinMuxX startup window discovery failed: %@", error.localizedDescription)
    }
    do {
        try await runLightSession(.startup, .forceRun) {
            applyStartupWorkspacePlacement(restoredWorld: restoredWorld)
            applyStartupWindowLayout(restoredWorld: restoredWorld)
            _ = try await config.afterStartupCommand.runCmdSeq(hookEnvironment(event: "startup"), .emptyStdin)
        }
    } catch {
        NSLog("WinMuxX startup layout failed: %@", error.localizedDescription)
    }
    isWinMuxRuntimeReady = true
    scheduleRefreshSession(.workspaceRestoration) // Catch events deferred during startup.
}

/// Startup placement is separate from display ownership during normal switching.
/// A restored world already says which workspace each display shows, so it is kept unless
/// `start-workspaces-on-main-monitor` discards it. Otherwise each existing workspace that
/// `workspace-to-monitor-force-assignment` places on a secondary display starts showing there.
/// The assignment itself holds at all times; see `Workspace.forceAssignedMonitor`.
@MainActor
func applyStartupWorkspacePlacement(restoredWorld: Bool) {
    guard !restoredWorld || config.startWorkspacesOnMainMonitor else { return }
    let main = mainMonitor
    let focused = focus.workspace
    let focusedDisplay = focused.isVisible ? focused.workspaceMonitor.rect.topLeftCorner : nil
    // A secondary display shows one workspace, so the first name for it, in numeric order, wins.
    var assigned: [(workspace: Workspace, monitor: Monitor)] = []
    var assignedWorkspaces: [Workspace] = []
    for name in config.workspaceToMonitorForceAssignment.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
        guard let workspace = Workspace.existing(byName: name),
              let monitor = resolvedForceAssignedMonitor(forWorkspaceName: name) else { continue }
        assignedWorkspaces.append(workspace)
        let point = monitor.rect.topLeftCorner
        if point != main.rect.topLeftCorner, assigned.contains(where: { $0.monitor.rect.topLeftCorner == point }) { continue }
        assigned.append((workspace, monitor))
    }
    if config.startWorkspacesOnMainMonitor {
        // Snapshot first: the empty secondary viewports created below stay on their displays.
        for workspace in Workspace.all where !assigned.contains(where: { $0.workspace == workspace }) {
            if let source = workspace.visibleMonitor,
               source.rect.topLeftCorner != main.rect.topLeftCorner {
                let blank = createBlankWorkspace(projectId: workspace.projectId, monitor: source)
                check(source.setActiveWorkspace(blank))
            }
            workspace.preferredMonitorPoint = main.rect.topLeftCorner
        }
    }
    for (workspace, monitor) in assigned {
        // A secondary display shows one workspace, so an assignment there shows it; main owns
        // its hidden workspaces, so one assigned there only needs to leave another display.
        if monitor.rect.topLeftCorner != main.rect.topLeftCorner || workspace.isVisible {
            _ = activateWorkspaceOnMonitorPreservingSourceViewport(workspace, targetMonitor: monitor, reserved: assignedWorkspaces)
        } else {
            workspace.preferredMonitorPoint = main.rect.topLeftCorner
        }
    }
    // Focus stays on its display: an assignment that replaced the focused workspace takes focus.
    if let focusedDisplay, !focused.isVisible,
       case let replacement = focusedDisplay.monitorApproximation.activeWorkspace,
       assigned.contains(where: { $0.workspace == replacement })
    {
        _ = replacement.focusWorkspace()
    } else {
        _ = focused.focusWorkspace()
    }
    syncClosedWindowsCacheToCurrentWorld()
}

@MainActor
func applyStartupWindowLayout(restoredWorld: Bool) {
    if config.defaultRootContainerLayout == .dwindle {
        if applyDwindleToExistingTiledWorkspaces() { syncClosedWindowsCacheToCurrentWorld() }
        return
    }
    guard !restoredWorld else { return }
    let workspace = focus.workspace
    let root = workspace.rootTilingContainer
    if root.children.count <= 3 {
        root.layout = .tiles
    } else {
        root.layout = .tabGroup
    }
}

@TaskLocal
var _isStartup: Bool? = false
var isStartup: Bool { _isStartup ?? dieT("isStartup is not initialized") }

struct ServerArgs: Sendable {
    var configLocation: String? = nil
}

private let serverHelp = """
    USAGE: \(CommandLine.arguments.first ?? "WinMuxX.app/Contents/MacOS/WinMuxX") [<options>]

    OPTIONS:
      -h, --help              Print help
      -v, --version           Print WinMuxX.app version
      --config-path <path>    Config path. Takes priority over ${XDG_CONFIG_HOME}/winmuxx/winmux.toml
                              (defaults to ~/.config/winmuxx/winmux.toml).
    """

nonisolated(unsafe) private var _serverArgs = ServerArgs()
var serverArgs: ServerArgs { _serverArgs }
private func initServerArgs() {
    let args = CommandLine.arguments.slice(1...) ?? []
    if args.contains(where: { $0 == "-h" || $0 == "--help" }) {
        exit(0, out: serverHelp)
    }
    var index = 0
    while index < args.count {
        let current = args[index]
        index += 1
        switch current {
            case "--version", "-v":
                exit(0, out: "\(winMuxAppVersion) \(gitHash)")
            case "--config-path":
                if let arg = args.getOrNil(atIndex: index) {
                    _serverArgs.configLocation = arg
                } else {
                    exit(1, err: "Missing <path> in --config-path flag")
                }
                index += 1
            case "-NSDocumentRevisionsDebugMode" where isDebug:
                // Skip Xcode CLI args.
                // Usually it's '-NSDocumentRevisionsDebugMode NO'/'-NSDocumentRevisionsDebugMode YES'
                while args.getOrNil(atIndex: index)?.starts(with: "-") == false { index += 1 }
            default:
                exit(1, err: "Unrecognized flag '\(args.first.orDie())'")
        }
    }
    if let path = serverArgs.configLocation, !FileManager.default.fileExists(atPath: path) {
        exit(1, err: "\(path) doesn't exist")
    }
}
