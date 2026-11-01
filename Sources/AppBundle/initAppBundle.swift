import AppKit
import Common
import Foundation

@MainActor public func initAppBundle() {
    Task {
        initTerminationHandler()
        isCli = false
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
            // An invalid native configuration must never fall back to a virtual
            // manager that starts parking windows. Defaults remain available for
            // diagnostics/UI, but startup stays physically read-only until restart.
            // A config that never asked for native Spaces falls back as it always did.
            if bootstrappedConfigUrl.map(configFileRequestsNativeBackend) ?? false { _serverArgs.isReadOnly = true }
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
        runtime.workspaceBackend.lockSelection()
        if runtime.workspaceBackend.kind == .native {
            // Defense in depth: low-level AX setters and recovery also enforce
            // this immutable startup flag. No permission prompts or virtual hooks.
            _serverArgs.isReadOnly = _serverArgs.isReadOnly || !config.nativeSpaces.tilingEnabled
            let owner = runtime
            WindowBorderController.shared.startMissionControlMonitoring()
            if config.nativeSpaces.tilingEnabled { NativeScrollingPan.shared.start() }
            GlobalObserver.initNativeInputObserver()
            owner.workspaceBackend.native.windowsPresentAtLaunch = Set(
                (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
                    .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
            owner.workspaceBackend.native.startObservation { [weak owner] inventory, _ in
                // The observer reports both a read's start and its result; chrome follows results.
                guard inventory.status != .reading else { return }
                owner?.withValue { NativeObservationChrome.shared.schedule() }
            }
            isWinMuxRuntimeReady = true
            startUnixSocketServer()
            syncConfigFileWatcher()
            showSetupCheckIfNeeded()
            return
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
        showSetupCheckIfNeeded()
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

/// Whether a config file asks for native Spaces, read from its text so that it works
/// even when the file does not parse.
func configFileRequestsNativeBackend(_ url: URL) -> Bool {
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
    return configTextRequestsNativeBackend(text)
}

func configTextRequestsNativeBackend(_ text: String) -> Bool {
    let lines = text.split(separator: "\n").map { $0.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "" }
        .map { $0.trimmingCharacters(in: .whitespaces) }
    var inBackendTable = false
    for line in lines where !line.isEmpty {
        if line.hasPrefix("[") { inBackendTable = line == "[workspace-backend]"; continue }
        let compact = line.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "\"")
        if inBackendTable, compact == "type=\"native\"" { return true }
        if compact == "workspace-backend.type=\"native\"" { return true }
    }
    return false
}
