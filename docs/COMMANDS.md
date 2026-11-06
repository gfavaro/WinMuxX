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


**Undo:** `undo-layout` puts the focused workspace's layout back as it was before its last layout command (`layout`, `move`, `join-with`, `resize`, `balance-sizes`, `workspace-layout` and similar), one step at a time, up to 20 steps. It rearranges only windows still on that workspace, and a window opened since is tiled into the restored layout. Available from Commands → Container Layout → Undo Layout Change.

**Retile:** `retile` puts every tiled window on the showing workspaces back on its tile and reports how many had moved ("Put 2 windows back" or "Nothing had moved"), briefly on screen as well. It also renews the put-back budget for windows whose apps kept moving them: an app that moves its tiled window off its tile again and again is put back at most three times in 10 seconds per tile, then left alone until that time passes or the tile changes. Available as Retile in the menu.

**No peek:** `no-peek [on|off|toggle]` darkens and blurs everything except the focused window, on every display, so people beside you or on a call can't read your other windows. It follows focus, stays out of Mission Control and native fullscreen, and clicks still reach the windows behind it. Without an argument it toggles; also in the menu as No Peek.

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
