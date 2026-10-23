# Command guide

Run `winmuxx --help` for the command list and `winmuxx <command> --help` for
arguments. This guide groups commands by what they affect.

**Focused window:** `focus`, `move`, `resize`, `swap`, `join-with`, `layout`,
`fullscreen`, `close`, `macos-native-fullscreen` and
`macos-native-minimize`. These use the current focused window unless a command's
help documents an explicit target.

**Workspace tree:** `workspace-layout` changes the focused window's workspace;
`flatten-workspace-tree` rebuilds its tree; `balance-sizes` redistributes sizes.
`layout` changes the selected window's container. These scopes differ; see
[layouts](LAYOUTS.md).

**Workspace and project:** `workspace` selects a workspace;
`workspace-back-and-forth` returns to the previous one; `project` selects a
project. `move-node-to-workspace`, `move-node-to-project` and
`move-workspace-to-monitor` explicitly change ownership or placement.

**Display:** `focus-monitor`, `move-node-to-monitor` and `list-monitors` operate
on displays. A workspace switch does not implicitly move its workspace.

**Inspect and maintain:** `list-workspaces`, `list-windows`, `list-apps`,
`list-modes`, `list-exec-env-vars`, `config`, `doctor`, `reload-config` and
`enable` provide queries, diagnostics or runtime controls. `agent` validates and
applies agent-oriented layout JSON; consult its own help before using it.

**Automation:** `exec-and-forget`, `trigger-binding`, `mode` and `subscribe` are
used by configured workflows. `debug-windows` records Accessibility debugging
information; review its output before sharing it.

Compatibility aliases remain available. Use `winmuxx --help` as the live command
inventory because aliases and options can change between releases.
