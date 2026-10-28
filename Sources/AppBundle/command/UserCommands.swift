import Common

// UI actions that switch workspaces or focus run commands, never the backends'
// primitives: the command layer is the one place that knows how each backend does it.

/// Runs commands in order, stopping at the first failure; a Space switch must land
/// before focusing. Returns the failure's message.
@MainActor
func runUserCommands(_ commands: [String]) async throws -> String? {
    for text in commands {
        guard case .cmd(let command) = parseCommand(text) else { continue }
        let io = CmdIo(stdin: .emptyStdin)
        guard try await [command].runCmdSeq(.defaultEnv, io) else { return io.stderr.last ?? "\(text) failed" }
    }
    return nil
}

/// Shows and focuses a workspace from a UI action, as `workspace` does in each backend.
/// Returns the failure's message.
@MainActor
func selectWorkspaceFromUi(_ name: String) async throws -> String? {
    guard let workspace = Workspace.existing(byName: name),
          let target = runtime.workspaceBackend.current.commandTargets().first(where: { $0.workspace === workspace })?.target,
          case .cmd(let command) = parseCommand(["workspace", target]) else { return nil }
    let io = CmdIo(stdin: .emptyStdin)
    return try await [command].runCmdSeq(.defaultEnv, io) ? nil : io.stderr.last ?? "workspace \(name) failed"
}
