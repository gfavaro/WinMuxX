import AppKit
import Common
import NativeSpaces

/// Which workspaces a listing covers.
enum WorkspaceListScope {
    /// `list-workspaces` and menus: user-facing, in presentation order.
    case presentation
    /// `list-windows`: user-facing, in tree order.
    case userFacing
    /// The palette: every workspace that can hold a window.
    case all
}

/// What differs between virtual workspaces and native Spaces. Shared code asks the
/// current backend instead of checking which one runs.
@MainActor
protocol WorkspaceBackend: AnyObject {
    /// The backend's own implementation of a command, or nil to run the shared one.
    func run(_ command: any Command, env: CmdEnv, io: CmdIo) async throws -> Bool?

    func listedWorkspaces(_ scope: WorkspaceListScope) -> [Workspace]
    /// Workspaces menus offer, each with the `workspace` argument that reaches it.
    func commandTargets() -> [(workspace: Workspace, target: String)]
    /// The name scripts and queries see.
    func scriptName(of workspace: Workspace) -> String
    /// Resolves a name a user typed.
    func workspace(named name: String) -> Workspace?
    /// The title menus and the palette show.
    func title(ofWorkspaceNamed name: String) -> String
    /// Whether projects group this backend's workspaces.
    var hasProjects: Bool { get }
    /// A workspace user-facing regardless of its windows (a native desktop).
    func isAlwaysUserFacing(_ workspace: Workspace) -> Bool

    func sidebarWorkspaces(currentFocus: LiveFocus, labels: [String: String],
                           monitors: [Monitor]) async -> [WorkspaceSidebarWorkspaceViewModel]
    /// Handles a sidebar action itself; false leaves it to the shared handler.
    func handleSidebarAction(_ action: WorkspaceSidebarAction, viewModel: TrayMenuModel, targetMonitorScopeId: String?) -> Bool

    /// Brings a window forward from the palette or minimap; returns an error to show.
    func bringForward(_ windowId: UInt32) async throws -> String?
    /// Palette entries beyond the workspace trees.
    func extraPaletteItems() -> [SwitcherPaletteItem]
    /// After a command outside native tiling's fence moved focus.
    func focusDidMove(to window: Window?)
}

@MainActor
final class VirtualWorkspaceBackend: WorkspaceBackend {
    func run(_ command: any Command, env: CmdEnv, io: CmdIo) async throws -> Bool? { nil }

    func listedWorkspaces(_ scope: WorkspaceListScope) -> [Workspace] {
        switch scope {
            case .presentation: userFacingWorkspaces(orderedWorkspacesForPresentation(), focusedWorkspace: focus.workspace)
            case .userFacing: userFacingWorkspaces(Workspace.all, focusedWorkspace: focus.workspace)
            case .all: Workspace.all
        }
    }

    func commandTargets() -> [(workspace: Workspace, target: String)] {
        listedWorkspaces(.presentation)
            .filter { $0.projectId == focus.workspace.projectId }
            .map { workspace in
                let target = workspace.usesAutomaticDisplayName
                    ? automaticWorkspaceDisplayIndex(workspace, focusedWorkspace: focus.workspace).map(String.init) ?? workspace.name
                    : workspace.name
                return (workspace, target)
            }
    }

    func scriptName(of workspace: Workspace) -> String { workspace.name }
    func workspace(named name: String) -> Workspace? { Workspace.existing(byName: name) }
    func title(ofWorkspaceNamed name: String) -> String { workspaceDisplayName(name) }
    var hasProjects: Bool { true }
    func isAlwaysUserFacing(_ workspace: Workspace) -> Bool { false }

    func sidebarWorkspaces(currentFocus: LiveFocus, labels: [String: String],
                           monitors: [Monitor]) async -> [WorkspaceSidebarWorkspaceViewModel] {
        await buildWorkspaceSidebarWorkspaceViewModels(currentFocus: currentFocus, workspaceLabels: labels, availableMonitors: monitors)
    }

    func handleSidebarAction(_ action: WorkspaceSidebarAction, viewModel: TrayMenuModel, targetMonitorScopeId: String?) -> Bool { false }

    func bringForward(_ windowId: UInt32) async throws -> String? {
        guard let window = Window.get(byId: windowId), let liveFocus = window.toLiveFocusOrNil() else { return nil }
        window.markAsMostRecentChild()
        _ = setFocus(to: liveFocus)
        window.nativeFocus()
        return nil
    }

    func extraPaletteItems() -> [SwitcherPaletteItem] { [] }
    func focusDidMove(to window: Window?) {}
}

/// Native Spaces: macOS owns desktops, so they are numbered in Control-N order, and
/// navigation and cross-Space moves run outside native tiling's command fence.
@MainActor
final class NativeWorkspaceBackend: WorkspaceBackend {
    private unowned let state: WorkspaceBackendState
    init(_ state: WorkspaceBackendState) { self.state = state }

    func run(_ command: any Command, env: CmdEnv, io: CmdIo) async throws -> Bool? {
        switch command {
            case let command as WorkspaceCommand: await state.nativeNavigation.run(command.args, io: io)
            case is WorkspaceBackAndForthCommand: await state.nativeNavigation.runBackAndForth(io: io)
            case let command as MoveNodeToWorkspaceCommand: await state.nativeWindowMoves.run(command.args, env: env, io: io)
            case let command as MoveNodeToMonitorCommand: await state.nativeWindowMoves.run(command.args, env: env, io: io)
            case let command as MoveWorkspaceToMonitorCommand: await state.nativeWindowMoves.run(command.args, env: env, io: io)
            case let command as FocusMonitorCommand: nativeFocusMonitor(command.args, env: env, io: io)
            default: nil
        }
    }

    func listedWorkspaces(_ scope: WorkspaceListScope) -> [Workspace] { nativeDesktopWorkspaces().map(\.workspace) }
    func commandTargets() -> [(workspace: Workspace, target: String)] {
        nativeDesktopWorkspaces().map { ($0.workspace, String($0.number)) }
    }
    func scriptName(of workspace: Workspace) -> String { nativeDesktopNumber(of: workspace).map(String.init) ?? workspace.name }
    func workspace(named name: String) -> Workspace? {
        Int(name).flatMap { number in nativeDesktopWorkspaces().first { $0.number == number }?.workspace }
    }
    func title(ofWorkspaceNamed name: String) -> String {
        nativeDesktopNumber(forSidebarWorkspace: name).map { nativeDesktopDisplayName($0) } ?? workspaceDisplayName(name)
    }
    var hasProjects: Bool { false }
    func isAlwaysUserFacing(_ workspace: Workspace) -> Bool { nativeDesktopNumber(of: workspace) != nil }

    func sidebarWorkspaces(currentFocus: LiveFocus, labels: [String: String],
                           monitors: [Monitor]) async -> [WorkspaceSidebarWorkspaceViewModel] {
        await buildNativeWorkspaceSidebarWorkspaceViewModels(currentFocus: currentFocus, workspaceLabels: labels, availableMonitors: monitors)
    }

    func handleSidebarAction(_ action: WorkspaceSidebarAction, viewModel: TrayMenuModel, targetMonitorScopeId: String?) -> Bool {
        handleNativeWorkspaceSidebarAction(action, viewModel: viewModel, targetMonitorScopeId: targetMonitorScopeId)
        return true
    }

    func bringForward(_ windowId: UInt32) async throws -> String? { try await focusNativeWindow(windowId) }
    func extraPaletteItems() -> [SwitcherPaletteItem] { nativeListedPaletteItems() }

    func focusDidMove(to window: Window?) {
        // Inside the fence the coordinator brings the result forward itself.
        guard !NativeTilingCommandScope.active else { return }
        window?.nativeFocus()
    }
}
