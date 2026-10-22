import AppKit
import Common
import os

/// Becomes true once the initial workspace model exists. Config parsing happens earlier during
/// launch, when scheduling a live layout pass would race app initialization.
@MainActor var isWinMuxRuntimeReady: Bool {
    get { runtime.configuration.isReady }
    set { runtime.configuration.isReady = newValue }
}
@MainActor var lastConfigReloadError: String? {
    get { runtime.configuration.lastReloadError }
    set { runtime.configuration.lastReloadError = newValue }
}

/// Manual and automatic reloads share this gate because applying config contains awaits.
@MainActor
final class ConfigReloadGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { busy = false }
        else { waiters.removeFirst().resume() }
    }
}
@MainActor
private final class ConfigReloadScope {
    var active = true
}
private enum ConfigReloadContext {
    @TaskLocal static var scope: ConfigReloadScope?
}


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
    automatic: Bool = false,
    stdout: inout String,
) async throws -> Bool {
    if ConfigReloadContext.scope?.active == true {
        stdout.append("A configuration reload cannot run recursively from its own callbacks")
        return false
    }
    let owner = runtime
    return try await owner.withValue {
        try await reloadConfigInCurrentRuntime(args: args, forceConfigUrl: forceConfigUrl,
                                             automatic: automatic, stdout: &stdout)
    }
}

@MainActor private func reloadConfigInCurrentRuntime(
    args: ReloadConfigCmdArgs, forceConfigUrl: URL?, automatic: Bool, stdout: inout String
) async throws -> Bool {
    let state = runtime.configuration
    await state.reloadGate.acquire()
    defer {
        state.reloadGate.release()
        if !args.dryRun { syncConfigFileWatcher() }
    }
    try Task.checkCancellation()
    if automatic && !config.autoReloadConfig { return false }
    let scope = ConfigReloadScope()
    defer { scope.active = false }
    return try await ConfigReloadContext.$scope.withValue(scope) {
        try await applyConfigReload(args: args, forceConfigUrl: forceConfigUrl, automatic: automatic, stdout: &stdout)
    }
}

@MainActor private func applyConfigReload(
    args: ReloadConfigCmdArgs,
    forceConfigUrl: URL?,
    automatic: Bool,
    stdout: inout String
) async throws -> Bool {
    let result: Bool
    switch readConfig(forceConfigUrl: forceConfigUrl ?? (isWinMuxRuntimeReady ? preferredEditableConfigUrl() : nil)) {
        case .success(let (parsedConfig, url)):
            if !args.dryRun {
                lastConfigReloadError = nil
                runtime.configuration.lastAutomaticNotification = nil
                let previousRootLayout = config.defaultRootContainerLayout
                let previousRootOrientation = config.defaultRootContainerOrientation
                resetHotKeys()
                runtime.configuration.publish(parsedConfig, from: url)
                runtime.publicState.configRevision &+= 1
                requestPublicStateUpdate(structural: true)
                WorkspaceGestureCoordinator.shared.syncConfiguration()
                materializePersistedWorkspaces()
                applyUpdatedDefaultWindowLayout(previousLayout: previousRootLayout)
                applyUpdatedDwindleOrientation(previousOrientation: previousRootOrientation)
                try await activateMode(activeMode.map { parsedConfig.modes[$0] == nil ? mainModeId : $0 })
                syncStartAtLogin()
                applyReloadedConfigurationToRunningApp()
                MessageModel.shared.message = nil
            }
            result = true
        case .failure(let msg):
            if !args.dryRun { lastConfigReloadError = msg }
            stdout.append(msg)
            if !args.dryRun { Logger(subsystem: winMuxAppId, category: "config").error("\(msg, privacy: .public)") }
            if !args.noGui && (!automatic || runtime.configuration.lastAutomaticNotification != msg) {
                if automatic { runtime.configuration.lastAutomaticNotification = msg }
                MessageModel.shared.message = Message(description: "WinMux Config Error", body: msg)
            }
            result = false
    }
    return result
}

@MainActor
func applyUpdatedDefaultWindowLayout(previousLayout: Layout) {
    guard isWinMuxRuntimeReady, TrayMenuModel.shared.isEnabled, previousLayout != config.defaultRootContainerLayout else { return }
    if applyDwindleToExistingTiledWorkspaces() { syncClosedWindowsCacheToCurrentWorld() }
}

/// Apply a newly loaded config to all running surfaces. This is intentionally part of config
/// reload rather than individual Settings controls, so GUI edits, config-editor saves, and
/// filesystem auto-reloads share the same live-update behavior.
@MainActor private func applyReloadedConfigurationToRunningApp() {
    if !isUnitTest {
        NSApp?.appearance = config.appearance.nativeAppearance
        WindowResizePreviewPanel.existing?.refreshAppearance()
    }
    TrayMenuModel.shared.setIfChanged(\.menuBarConfiguration, config.menuBar)
    updateTrayText()
    ShortcutSettingsModel.shared.reload()
    WorkspaceSidebarPanel.refreshAll()
    WindowTabStripPanelController.shared.refresh()
    SecureInputPanel.shared.refresh()

    guard isWinMuxRuntimeReady else { return }
    scheduleRefreshSession(.configAutoReload)
}

@MainActor
func applyUpdatedDwindleOrientation(previousOrientation: DefaultContainerOrientation) {
    guard isWinMuxRuntimeReady, TrayMenuModel.shared.isEnabled, previousOrientation != config.defaultRootContainerOrientation else { return }
    for workspace in Workspace.all where workspace.rootTilingContainer.layout == .dwindle &&
        config.workspaceLayouts[workspace.name]?.settings(on: workspace.workspaceMonitor).orientation == nil {
        workspace.rootTilingContainer.dwindleOrientation = switch config.defaultRootContainerOrientation {
            case .auto: nil
            case .horizontal: .h
            case .vertical: .v
        }
    }
    syncClosedWindowsCacheToCurrentWorld()
}
