# Concepts

WinMuxX groups work into **projects**, each with its own **workspaces**. A
workspace holds a tree of tiled windows and containers; containers arrange their
windows as tiles or tabs. Floating windows keep their own position above the tiles.

| Term | Meaning |
| --- | --- |
| Project | A set of workspaces you switch between in the sidebar |
| Workspace | A tree of windows shown on one display |
| Container | A group of windows arranged as tiles or tabs |
| Label | The name the sidebar shows; it can differ from the internal name used by commands and configuration |

Persistent workspace names stay available when empty; see
[persistent workspaces](CONFIGURATION.md#persistent-workspaces).

## Displays

Every workspace belongs to a display. Ordinary navigation never changes that owner.

- Selecting a workspace that is visible elsewhere focuses it there. Selecting `Code`
  in the sidebar goes to the display where `Code` lives.
- Selecting a hidden workspace owned by another display shows it there and leaves
  focus where you are, so the sidebar can change another display without pulling
  you away from your work.
- Moving a workspace is explicit: right-click it and choose **Move to Display**.
  Its windows and layout move together. Configured display assignments still apply.
- With several displays, the expanded sidebar shows each workspace's owner.

## What WinMuxX is not

WinMuxX workspaces are managed by WinMuxX and are separate from macOS Spaces. Native
macOS fullscreen is separate from WinMuxX's workspace fullscreen command.

WinMuxX saves assignments and layout for restart recovery. See
[configuration and session data](CONFIGURATION.md#configuration-versus-session-data).
