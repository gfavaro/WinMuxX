# Command guide

With the experimental native read-only backend, `doctor` reports native Space
observations and `reload-config` validates configuration. Other commands return an
unsupported error. The separate experimental native tiling opt-in also supports
workspace-local focus/move/resize/swap, Dwindle/Master, tiles/orientation/floating,
split, balance and shortcut modes. Native navigation and cross-display movement
remain unsupported. See [Native Spaces](NATIVE_SPACES.md) for exact limits and the
unverified native release gates; virtual remains the default.

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

**Scrolling workspaces:** `scrolling-width next|previous|full` changes the focused group's width; `scrolling-center` centers it. `scrolling-focus 1-9|first|last` focuses a column by place (9 is the last), `scrolling-move 1-9|first|last` moves the focused column there, and `scrolling-pin left|right` pins the focused column to a screen edge (again to unpin). `scrolling-minimap toggle` opens or closes the clickable workspace map; explicit opening keeps it visible and supports Left/Right, Return and Escape, also available from Layout → Show Scrolling Minimap and Control–Option–M in fresh configurations.

**Undo:** `undo-layout` puts the focused workspace's layout back as it was before its last layout command (`layout`, `move`, `join-with`, `resize`, `balance-sizes`, `workspace-layout`, scrolling moves, widths and pins, and similar), one step at a time, up to 20 steps. It rearranges only windows still on that workspace, and a window opened since is tiled into the restored layout. Available from Layout → Undo Layout Change.

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
