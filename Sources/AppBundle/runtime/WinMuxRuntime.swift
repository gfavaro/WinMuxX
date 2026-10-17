import Common
import Foundation

/// The process owns one runtime. Scoped bindings let tests exercise independent worlds,
/// including async work, without adding another mutable global for each subsystem.
@MainActor
final class WinMuxRuntime {
    let configuration: ConfigurationState
    var workspaces = WinMuxWorkspaceState()
    let focus = WorkspaceFocusState()
    let nativeFocus = NativeFocusState()
    let displays = MonitorState()
    let hotkeys = HotkeyState()
    let recovery = WorkspaceRecoveryState()

    init(config: Config = defaultConfig, configURL: URL = defaultConfigUrl) {
        configuration = ConfigurationState(value: config, url: configURL)
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

    static func replaceForTests() {
        precondition(isUnitTest)
        precondition(bound == nil, "Replace the fixture outside a scoped runtime binding")
        process.recovery.reset()
        process.configuration.reloadScheduler?.cancelPending()
        process = WinMuxRuntime()
    }
}

@MainActor var runtime: WinMuxRuntime { WinMuxRuntime.current }
