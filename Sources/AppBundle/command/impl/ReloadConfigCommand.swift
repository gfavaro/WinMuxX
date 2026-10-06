import AppKit
import Common

/// Becomes true once the initial workspace model exists. Config parsing happens earlier during
/// launch, when scheduling a live layout pass would race app initialization.
@MainActor var isWinMuxRuntimeReady = false
@MainActor var lastConfigReloadError: String? = nil

struct ReloadConfigCommand: Command {
    let args: ReloadConfigCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        var stdout = ""
        let isOk = try await reloadConfig(args: args, stdout: &stdout)
        if !stdout.isEmpty {
            io.out(stdout)
        }
        return isOk
    }
}

@MainActor func reloadConfig(forceConfigUrl: URL? = nil) async throws -> Bool {
    var devNull = ""
    return try await reloadConfig(forceConfigUrl: forceConfigUrl, stdout: &devNull)
}

@MainActor func reloadConfig(
    args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []),
    forceConfigUrl: URL? = nil,
    stdout: inout String,
) async throws -> Bool {
    let result: Bool
    switch readConfig(forceConfigUrl: forceConfigUrl) {
        case .success(let (parsedConfig, url)):
            if !args.dryRun {
                lastConfigReloadError = nil
                let previousRootLayout = config.defaultRootContainerLayout
                let previousRootOrientation = config.defaultRootContainerOrientation
                resetHotKeys()
                config = parsedConfig
                configUrl = url
                materializePersistedWorkspaces()
                applyUpdatedDefaultWindowLayout(previousLayout: previousRootLayout)
                applyUpdatedDwindleOrientation(previousOrientation: previousRootOrientation)
                try await activateMode(activeMode)
                syncStartAtLogin()
                applyReloadedConfigurationToRunningApp()
                MessageModel.shared.message = nil
            }
            result = true
        case .failure(let msg):
            if !args.dryRun { lastConfigReloadError = msg }
            stdout.append(msg)
            if !args.noGui {
                Task { @MainActor in
                    MessageModel.shared.message = Message(description: "WinMux Config Error", body: msg)
                }
            }
            result = false
    }
    if !args.dryRun {
        syncConfigFileWatcher()
    }
    return result
}

@MainActor
func applyUpdatedDefaultWindowLayout(previousLayout: Layout) {
    guard isWinMuxRuntimeReady, previousLayout != config.defaultRootContainerLayout else { return }
    if applyDwindleToExistingTiledWorkspaces() { syncClosedWindowsCacheToCurrentWorld() }
}

/// Apply a newly loaded config to all running surfaces. This is intentionally part of config
/// reload rather than individual Settings controls, so GUI edits, config-editor saves, and
/// filesystem auto-reloads share the same live-update behavior.
@MainActor private func applyReloadedConfigurationToRunningApp() {
    ShortcutSettingsModel.shared.reload()
    WorkspaceSidebarPanel.refreshAll()
    WindowTabStripPanelController.shared.refresh()
    SecureInputPanel.shared.refresh()

    guard isWinMuxRuntimeReady else { return }
    scheduleRefreshSession(.configAutoReload)
}

@MainActor
func applyUpdatedDwindleOrientation(previousOrientation: DefaultContainerOrientation) {
    guard isWinMuxRuntimeReady, previousOrientation != config.defaultRootContainerOrientation else { return }
    for workspace in Workspace.all where workspace.rootTilingContainer.layout == .dwindle {
        workspace.rootTilingContainer.dwindleOrientation = switch config.defaultRootContainerOrientation {
            case .auto: nil
            case .horizontal: .h
            case .vertical: .v
        }
    }
    syncClosedWindowsCacheToCurrentWorld()
}
