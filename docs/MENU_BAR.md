# Menu bar, diagnostics and recovery

The status item, the native menu, `winmuxx doctor`, and how WinMuxX restores your windows after a restart or crash.

## Menu-bar indicator

Settings → Appearance → Menu bar offers Icon or Workspace. Workspace follows the
focused monitor and shows the label initial, or the workspace number when there
is no label. Icon supports color or monochrome appearance. Clicking the status
item opens the native action menu.
Settings saves these choices to TOML:

```toml
[menu-bar]
indicator = 'icon'          # icon or workspace
icon-appearance = 'color'  # color or monochrome
```

## The menu

The menu follows Dinky’s everyday actions: workspace navigation and moves, Focus,
Move Window, Join With, Resize, Layout, Fullscreen and Balance Sizes. Display and
Mode menus appear only when there is more than one choice. Settings, Reload Config,
Enabled and Quit stay directly accessible. Projects, tab controls, extra container
operations and maintenance tools live in Settings or the CLI.

Shortcuts come from the effective configuration for the active mode, and the menu
updates whenever it opens. Actions without shortcuts remain clickable.

## Dinky adaptations

| Dinky | What it added | Notes |
| --- | --- | --- |
| 0.19 | `hyper`/`meh` shortcut aliases, bundle-ID regex rules, per-display workspace layouts, settled display-change actions | [Notes](archive/DINKY_019_ADOPTION.md) |
| 0.20 | Master layout and `swap-with-master`, app-activation exclusions, browser overlay filtering, original-frame restoration on disable/quit | [Notes](archive/DINKY_020_ADOPTION.md) |
| 0.21 | `workspace-layout dwindle master` for workspace modes, `workspace-layout tabbed`, `%{workspace-layout}` | [Migration](DINKY_021_ADOPTION.md) |

Master mode arranges each top-level group as a whole, keeping nested splits and
tabs. `layout` acts on a container; `workspace-layout dwindle` restores the
workspace's default arrangement. See [layouts](LAYOUTS.md#tabbed).

## Diagnostics

Run `winmuxx doctor` to inspect the loaded config path, file validation, effective
default layout, permissions, monitors, conflicting window managers and per-app
accessibility latency. It uses the same generator as the app and changes nothing.
Review local paths and app names before sharing a report. Upcoming work is in
[the roadmap](ROADMAP.md).

## Recovery

After an interrupted session, the menu can offer **Recover N Windows from Previous Session…**.
Recovery pauses tiling and restores the original positions and sizes recorded before WinMux moved
the windows. It validates the owning app's process and launch identity, skips disconnected displays
and native fullscreen/minimized windows, and retains failed entries for another attempt. Turn
**Enabled** back on to resume tiling. The recovery journal is separate from the saved managed layout.

## Restarts

WinMuxX saves workspace assignments and layout during use (one second after a
change) and on normal quit. Saves run on a bounded background writer and skip
unchanged snapshots. Restarting or updating WinMuxX keeps workspace names,
projects and automatic display numbers.

State lives in `window-state.json` in the fork's Application Support directory,
with the previous valid snapshot kept as a backup.

### Matching windows

- Existing windows are verified against their app and process launch.
- After an app or computer restart, matching prefers the document URL and the AX
  window identifier. A unique nonempty title is the fallback.
- Conflicting identifiers and ambiguous matches are skipped. Changed titles can
  still match by document or identifier.
- Apps with delayed metadata are retried for up to 30 seconds, stopping if window
  placement changes.
- Apps that reopen later keep their pending assignments across WinMuxX restarts.
  WinMuxX never reopens apps or documents itself.
- Old ID-only snapshots cannot safely match reopened windows; new snapshots record
  verified identities. Diagnostics reports how many windows still await a unique
  match.

### Restoring layout

- Available windows recover their saved layout at startup. Tiled sizes follow the
  saved proportions on the current monitor.
- Floating sizes and the manual width of a lone tiled window are saved too.
  Oversized floating windows fit the screen; fullscreen and minimized windows are
  not resized.
- For 30 seconds after startup, delayed windows from the same app process also
  recover their tree slots and split ratios, unless a layout command, mouse edit
  or unrelated new window intervened. Later arrivals recover only their workspace,
  so old layouts never overwrite your current changes.
- Monitors match by display UUID, with coordinates as the fallback for older
  snapshots. Deleted workspaces discard pending assignments, and late arrivals
  respect current project assignments.
