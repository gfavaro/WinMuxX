import Common
import Foundation

/// The process owns one runtime. Scoped bindings let tests exercise independent worlds,
/// including async work, without adding another mutable global for each subsystem.
@MainActor
final class WinMuxRuntime {
    let configuration: ConfigurationState
    var workspaces = WinMuxWorkspaceState()
    let workspaceBackend = WorkspaceBackendState()
    let focus = WorkspaceFocusState()
    let nativeFocus = NativeFocusState()
    let displays = MonitorState()
    let hotkeys = HotkeyState()
    let publicState = PublicStateStore()
    let recovery = WorkspaceRecoveryState()
    let refresh = RefreshCoordinator()
    let events = RuntimeEventRecorder()
    let workMetrics = RuntimeWorkMetrics.shared

    init(config: Config = defaultConfig, configURL: URL = defaultConfigUrl) {
        configuration = ConfigurationState(value: config, url: configURL)
        workspaceBackend.selectForStartup(config.workspaceBackend)
    }

    private static var process = WinMuxRuntime()
    @TaskLocal private static var bound: WinMuxRuntime?

    static var current: WinMuxRuntime { bound ?? process }

    func withValue<T>(_ operation: () throws -> T) rethrows -> T {
        try Self.$bound.withValue(self, operation: operation)
    }

    func withValue<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await Self.$bound.withValue(self, operation: operation)
    }

    /// Inherits the owner at creation, rather than looking up the process fixture after a delay.
    func task(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        withValue { Task { @MainActor in await operation() } }
    }

    func throwingTask(_ operation: @escaping @MainActor () async throws -> Void) -> Task<Void, any Error> {
        withValue { Task { @MainActor in try await operation() } }
    }

    static func replaceForTests() {
        precondition(isUnitTest)
        precondition(bound == nil, "Replace the fixture outside a scoped runtime binding")
        process.hotkeys.modeSession.invalidate()
        process.refresh.invalidate()
        process.workspaceBackend.stop()
        process.recovery.reset()
        process.displays.displayChangeTask?.cancel()
        process.configuration.reloadScheduler?.cancelPending()
        process = WinMuxRuntime()
    }
}

@MainActor var runtime: WinMuxRuntime { WinMuxRuntime.current }
