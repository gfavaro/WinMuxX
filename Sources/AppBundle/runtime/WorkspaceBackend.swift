import Common

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
    /// A workspace user-facing regardless of its windows (a native desktop).
    func isAlwaysUserFacing(_ workspace: Workspace) -> Bool

    /// Brings a window forward from the palette or minimap; returns an error to show.
    func bringForward(_ windowId: UInt32) async throws -> String?
    /// The workspace a display shows; native desktops never fall back to virtual rearrangement.
    func shownWorkspace(on monitor: Monitor) -> Workspace?
    /// Displays currently covered by native fullscreen content.
    func fullscreenDisplayIDs() -> Set<String>
    /// After a command outside native tiling's fence moved focus.
    func focusDidMove(to window: Window?)

    /// The `doctor` report, or nil for the shared one.
    func diagnosticsReport() async -> String?
    /// A window's geometry changed (a move when `moved`); false leaves it to the shared mouse handling.
    func windowGeometryChanged(_ windowId: UInt32?, moved: Bool) -> Bool
}
