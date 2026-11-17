# Command guide

Run `winmuxx --help` for the command list and `winmuxx <command> --help` for
arguments. Help works without the app running. Commands are grouped here by what
they affect.

| Group | Commands | Notes |
| --- | --- | --- |
| Focused window | `focus`, `focus-back-and-forth`, `move`, `resize`, `swap`, `split`, `join-with`, `stack-with`, `layout`, `fullscreen`, `close`, `close-all-windows-but-current`, `macos-native-fullscreen`, `macos-native-minimize` | Use the focused window unless the command's help documents a target. `move-through` is an alias for `move`; `move-workspace-to-display` for `move-workspace-to-monitor` |
| Workspace tree | `workspace-layout`, `flatten-workspace-tree`, `balance-sizes`, `swap-with-master` | `workspace-layout` changes the whole workspace; `layout` changes the selected container. See [layouts](LAYOUTS.md) |
| Scrolling | `scrolling-focus`, `scrolling-move`, `scrolling-width`, `scrolling-center`, `scrolling-pan`, `scrolling-pin`, `scrolling-minimap` | Act on the columns of a Scrolling workspace. See [layouts](LAYOUTS.md#scrolling) |
| Workspace and project | `workspace`, `workspace-back-and-forth`, `project`, `move-node-to-workspace`, `move-node-to-project`, `move-workspace-to-monitor`, `summon-workspace` | The `move-*` commands and `summon-workspace` explicitly change ownership or placement |
| Display | `focus-monitor`, `move-node-to-monitor`, `list-monitors`, `move-mouse` | A workspace switch never moves the workspace |
| Interface | `open-sidebar`, `palette`, `no-peek`, `retile`, `undo-layout` | Detailed below and in [shortcuts](SHORTCUTS.md#window-search-palette) |
| Inspect and maintain | `state`, `list-workspaces`, `list-windows`, `list-apps`, `list-modes`, `list-exec-env-vars`, `config`, `doctor`, `reload-config`, `enable` | `state` reads a versioned snapshot; see the [State API](STATE_API.md). `agent` validates and applies agent-oriented layout JSON; read its help first |
| Automation | `trigger-binding`, `mode`, `subscribe`, `debug-windows` | `debug-windows` records Accessibility details; review before sharing |

`exec-and-forget` is a configuration command for bindings and callbacks, not a CLI
subcommand.

## Undo

`undo-layout` restores the focused workspace's layout to how it was before its last
layout command (`layout`, `move`, `join-with`, `resize`, `balance-sizes`,
`workspace-layout` and similar), one step at a time, up to 20 steps. It rearranges
only windows still on that workspace, and a window opened since is tiled into the
restored layout. In the menu: Commands → Container Layout → Undo Layout Change.

## Retile

`retile` puts every tiled window on the showing workspaces back on its tile and
reports how many had moved ("Put 2 windows back" or "Nothing had moved"), briefly on
screen as well. It is in the menu as Retile.

It also renews the put-back budget for apps that keep moving their windows: a window
is put back at most three times in 10 seconds per tile, then left alone until that
time passes or the tile changes.

## No peek

`no-peek [on|off|toggle]` darkens and blurs everything except the focused window on
every display, so people beside you or on a call can't read your other windows. It
follows focus, stays out of Mission Control and native fullscreen, and clicks still
reach the windows behind it. Without an argument it toggles; in the menu it is No Peek.

## Aliases

Compatibility aliases remain available. Use `winmuxx --help` as the live command
inventory because aliases and options can change between releases.
