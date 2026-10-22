import AppKit
import Common
import Foundation

@MainActor public func initAppBundle() {
    Task {
        initTerminationHandler()
        isCli = false
        initServerArgs()
        var bootstrappedConfigUrl: URL? = nil
        if isDebug {
            await toggleReleaseServerIfDebug(.off)
        }
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
        MonitorConfigurationObserver.shared.prepareForStartup()

        checkAccessibilityPermissions()
        requestScreenRecordingPermissionsIfNeeded()
        startUnixSocketServer()
        GlobalObserver.initObserver()
        MonitorConfigurationObserver.shared.startObserving()
        let didLoadPersistedFrozenWorld = loadPersistedFrozenWorldForStartupIfPresent()
        Workspace.reconcileWorkspaceState() // init workspaces
        _ = Workspace.all.first?.focusWorkspace()
        try await runRefreshSessionBlocking(.startup, layoutWorkspaces: false)
        try await runLightSession(.startup, .forceRun) {
            applyStartupWorkspacePlacement()
            applyStartupWindowLayout(restoredWorld: didLoadPersistedFrozenWorld)
            _ = try await config.afterStartupCommand.runCmdSeq(hookEnvironment(event: "startup"), .emptyStdin)
        }
        isWinMuxRuntimeReady = true
        scheduleRefreshSession(.workspaceRestoration) // Catch events deferred during startup.
        reloadConfigIfSavedDuringStartup()
        schedulePersistedFrozenWorldSave()
    }
}

/// Startup placement is separate from display ownership during normal switching.
@MainActor
func applyStartupWorkspacePlacement() {
    guard config.startWorkspacesOnMainMonitor else { return }
    let main = mainMonitor
    let focused = focus.workspace
    // Snapshot first: the empty secondary viewports created below stay on their displays.
    for workspace in Workspace.all where workspace.forceAssignedMonitor == nil {
        if let source = workspace.visibleMonitor,
           source.rect.topLeftCorner != main.rect.topLeftCorner {
            let blank = createBlankWorkspace(projectId: workspace.projectId, monitor: source)
            check(source.setActiveWorkspace(blank))
        }
        workspace.preferredMonitorPoint = main.rect.topLeftCorner
    }
    _ = focused.focusWorkspace()
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
    var isReadOnly: Bool = false
}

private let serverHelp = """
    USAGE: \(CommandLine.arguments.first ?? "WinMuxX.app/Contents/MacOS/WinMuxX") [<options>]

    OPTIONS:
      -h, --help              Print help
      -v, --version           Print WinMuxX.app version
      --config-path <path>    Config path. Takes priority over ${XDG_CONFIG_HOME}/winmuxx/winmux.toml
                              (defaults to ~/.config/winmuxx/winmux.toml).
      --read-only             Run without mutating macOS windows.
                              Useful if you want to use only debug-windows or other query commands.
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
            case "--read-only": // todo rename to '--disabled' and unite with disabled feature
                _serverArgs.isReadOnly = true
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
