import Common

/// Shows and focuses a workspace from a UI action by running `workspace`.
/// Returns the failure's message.
@MainActor
func selectWorkspaceFromUi(_ name: String) async throws -> String? {
    guard let workspace = Workspace.existing(byName: name),
          let target = workspaceCommandTargets().first(where: { $0.workspace === workspace })?.target,
          case .cmd(let parsed) = parseCommand(["workspace", target]),
          let command = parsed as? WorkspaceCommand else { return nil }
    let io = CmdIo(stdin: .emptyStdin)
    return try await [command].runCmdSeq(.defaultEnv, io) ? nil : io.stderr.last ?? "workspace \(name) failed"
}
