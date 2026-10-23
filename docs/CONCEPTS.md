# Concepts

WinMuxX groups work into **projects**, each with its own **workspaces**. A
workspace contains a tree of tiled windows and containers. Containers arrange
windows as tiles, an accordion or tabs. Floating windows keep their own position
above tiled windows.

The sidebar shows projects and workspace labels. A label can differ from the
workspace's internal name, which configuration and commands use. Persistent
workspace names remain available when empty; see
[persistent workspaces](CONFIGURATION.md#persistent-workspaces).

Every workspace belongs to a display. Selecting a workspace already visible on
another display focuses it there. Moving the workspace to a different display is
an explicit action; ordinary navigation does not change its owner. For example,
selecting `Code` in the sidebar focuses the display where `Code` currently lives.
Use **Move Workspace to Display** when you want to change that assignment.

WinMuxX saves workspace assignments and layout state for restart recovery. Its
workspaces are managed by WinMuxX; they are distinct from macOS Spaces. Native
macOS fullscreen is also distinct from WinMuxX's workspace fullscreen command.
See [configuration and session data](CONFIGURATION.md#configuration-versus-session-data).
