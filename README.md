<p align="center">
  <img src="resources/winmux-logo.svg" width="96" alt="WinMuxX logo">
</p>

<h1 align="center">WinMuxX</h1>

<p align="center">A sidebar window manager for macOS, with Dwindle tiling and room to work on ultrawide displays.</p>

<p align="center">
  <a href="https://github.com/gfavaro/WinMuxX/releases">Download</a> ·
  <a href="#settings">Settings</a> ·
  <a href="docs/FORK.md">Fork guide</a> ·
  <a href="HACKING.md">Development</a> ·
  <a href="docs/README.md">Documentation</a>
</p>

Personal fork by gfavaro, based on ZimengXiong/WinMux. Automatic upstream updates
are disabled; releases and configuration belong to this fork.

https://github.com/user-attachments/assets/51983568-a168-494f-8ae3-5f50ca1efce1

## In this fork

WinMuxX builds on upstream's sidebar, projects, tab groups and window commands.
These are the defaults and features maintained here:

- Dwindle is the default layout, with built-in window borders enabled.
- A single tiled window has a configurable width limit and alignment on ultrawide
  displays; manual width resizing is respected.
- A global minimum keeps workspaces available without maintaining a list of names.
- Settings has separate Sidebar and Appearance pages, accessible controls, and
  animated spacing previews.
- Sidebar, tab groups and the switcher share glass or solid styling. Expanded glass
  surfaces use a frosted background.
- Selecting a workspace already visible on another display focuses it there.
  Sidebar clicks offer an explicit override; an unused override dismisses when
  the pointer or focus leaves the workspace button.
- Learned application minimum sizes constrain layouts. Borders use an AppKit
  fallback when the private renderer is unavailable.
- The native menu includes diagnostics and recovery of original window frames
  after an interrupted session.

The app has its own identity, CLI, configuration and recovery state. On first
launch, it can copy your original WinMux configuration while leaving that file
untouched. Releases use `gf-v` tags in this repository.

## Settings

Open Settings from the WinMuxX menu. The window is resizable, and the controls
support keyboard navigation, accessible labels and values, Reduce Motion, Reduce
Transparency, and increased contrast.

| Page | Options |
| --- | --- |
| General | Start at login and automatic configuration reload |
| Workspaces | Minimum quantity, project deletion behavior and workspace shortcuts |
| Windows | New-window behavior, layout, ultrawide ratio/alignment, pointer focus and tab strips |
| Sidebar | Visibility, placement, widths, display mode, clock and status content |
| Appearance | Shared glass/solid style, menu-bar indicator, motion, spacing and borders |
| Shortcuts | Presets and editable window-management shortcuts |
| Automation | Startup and event commands |
| Configuration | Complete TOML editor, validation and advanced reference |

Settings apply through configuration reload. Your drafts stay in place when you
switch pages or reload; if saving fails, you can retry the same edit. The editor
preserves dotted TOML properties, table sections, comments and multiline monitor
rules.
Menu-bar and double-sided window preferences are stored locally in UserDefaults.

## How it works

### Single window on ultrawide

One tiled window is centered at a maximum 3:2 ratio on ultrawide screens
(screen width/height at least 2.3). The limit applies only when the workspace has
one available window; an extra floating window prevents it. Minimized windows,
hidden apps and popups do not count. Tab groups and WinMuxX fullscreen bypass
the limit. The available area accounts for the sidebar and
outer gaps; known application minimum widths take priority.
Set `single-window-aspect-ratio = 0` to disable, or choose a different ratio in
Settings → Windows. Per-monitor rules use the same syntax as gaps:

```toml
single-window-aspect-ratio = [{ monitor."S34CG50" = 1.5 }, 0]
```

Settings → Windows exposes the default ratio and alignment. Per-monitor ratio
overrides remain available in TOML and are preserved when changing the default.
Changes take effect on configuration reload. Monitor overrides still require an
ultrawide screen.

Manually resizing a lone ultrawide tile overrides its default aspect-ratio width
for the current session. The window keeps its alignment and layout height. You
can make it wider than 3:2; available space and the app's minimum width still apply. Mouse resizing and `resize width`/`resize smart` both support this.
The preference returns when the window becomes a lone tile again.

Use `single-window-alignment = 'center'`, `'left'` or `'right'` to choose its
horizontal position, also available in Settings → Windows. Center is the default.

For a lone ultrawide tile, a mouse resize that changes height switches the window
to floating and preserves the resulting size and position. Width-only resizing
keeps it tiled with the selected alignment. Small native frame rounding changes
are ignored.

### Native sidebar appearance

Settings → Appearance controls the shared visual style; Settings → Sidebar controls
placement, sizing and content. Choose Liquid Glass for native glass
on macOS 26 and later, or Solid color for an opaque preset/custom color. Earlier
macOS versions use a native material fallback. Reduce Transparency forces an
opaque system background in Liquid Glass. Expanded Liquid Glass always uses a
frosted background; Show background controls the compact rail.

In Sidebar, choose Left or Right and a Standard, Centered or Full height. Every mode reserves
space for the menu bar, even when it auto-hides, and respects the notch. Centered
fits its content up to 90% of the safe height, then scrolls. Standard and Full
currently share the same safe geometry. Expanded and collapsed widths have
Small, Medium and Large presets. Always expanded reserves window space on the
chosen side.

Tiled windows glide into place by default (150 ms). Set `animations.enabled = false`
or `animations.duration-ms = 0` for immediate placement. Reduce Motion disables
the glide. See [window motion](docs/WINDOW_MOTION.md) for configuration and limits.

```toml
[workspace-sidebar]
    chrome-style = 'liquid-glass' # or 'solid'
    menu-bar-background = false
    position = 'left'            # or 'right'
    height-mode = 'standard'     # or 'centered', 'full'
```

`appearance`, `background` and `frosted-tint` remain accepted for older configs;
`chrome-style` is the appearance selector used at runtime. Legacy
`menu-bar-reserve-height` applies only when height-mode is absent and cannot
reduce the mandatory system reservation.

### Menu-bar indicator

Settings → Appearance → Menu bar offers Icon or Workspace. Workspace follows the
focused monitor and shows the label initial, or the workspace number when there
is no label. Icon supports color or monochrome appearance. Both open the same
native action menu. These choices persist locally, outside the TOML config.

### Menu-bar actions and diagnostics

Click the WinMuxX menu-bar icon for window, layout, workspace, project and monitor actions.
Shortcuts come from the effective configuration for the active mode, and the menu updates whenever
it opens. Actions without shortcuts remain clickable. Custom command chains, modifier taps and
key sequences are available under **Other Key Bindings** when not represented by a catalog action.

Choose **Diagnostics…** to inspect the loaded config path, file validation, effective default layout,
permissions, monitors, potentially conflicting window managers and per-app accessibility latency.
The window offers **Refresh** and **Copy Diagnostics**; `winmux doctor` uses the same report generator.
Checks do not change macOS preferences or stop other apps. Review local paths and app names before
sharing a report. Upcoming improvements are tracked in [the roadmap](docs/ROADMAP.md).

After an interrupted session, the menu can offer **Recover N Windows from Previous Session…**.
Recovery pauses tiling and restores the original positions and sizes recorded before WinMux moved
the windows. It validates the owning app's process and launch identity, skips disconnected displays
and native fullscreen/minimized windows, and retains failed entries for another attempt. Choose
**Enable** to resume tiling. The recovery journal is separate from the saved managed layout.

Workspace assignments are also saved during use (with a one-second delay) and on
normal quit. Restarting WinMuxX or updating it preserves workspace names, projects
and automatic display numbers. Existing windows are verified against their app
and process launch; after an app or computer restart, matching prefers the document
URL and AX window identifier exposed by the app. A unique nonempty title is the
fallback. Conflicting documents/identifiers and ambiguous matches are skipped.
Apps may reopen later: pending assignments survive subsequent WinMuxX restarts.
Changed titles can still match by document/identifier. Apps with delayed metadata
are retried for up to 30 seconds, stopping if window placement changes. WinMuxX
does not reopen apps or documents itself. During startup, available windows recover their saved layout;
later arrivals recover their workspace without replaying old layouts over current
user changes. State lives in `window-state.json` in the fork's Application Support
directory, with a previous valid snapshot as backup. Monitor matching uses display
UUIDs when available, with coordinates as fallback for older snapshots. Deleted
workspaces discard pending assignments, and late arrivals respect current project
assignments. Diagnostics reports the number of windows still awaiting a unique
match. Old ID-only snapshots cannot
safely match reopened windows; this build starts recording verified identities.

### Workspaces to keep

Settings → Workspaces → Workspaces to keep sets a minimum total across all
projects. The default is **1**; **0** disables the configured minimum:

```toml
minimum-workspace-count = 1
```

Occupied workspaces count. Each project and active display retains its required
workspace even with a minimum of zero. Existing empty slots are reused; missing
slots are created in the default project without changing focus. Reducing the
minimum allows excess empty slots to be collected.

Older configurations retain their named `persistent-workspaces` behavior until
the quantity is saved in Settings. Saving replaces that list with
`minimum-workspace-count`; an explicit count takes precedence over named and
shortcut-inferred persistence.

### Projects

A project groups its own workspaces. Switch projects in the sidebar to keep
different sets of windows together.

### Sidebar
The sidebar shows your workspaces beside your windows. You can use it as an
alternative to [Sketchybar](https://github.com/felixkratz/sketchybar) or a workspace
menu in the menu bar.

Drag windows or tab groups through the sidebar to move them between workspaces.
You can also drag a window back onto the current workspace.

By default the sidebar rests as a compact rail and expands when hovered. To hide the rail
completely until the pointer reaches the selected display edge, enable auto-hide.
Sidebar appearance also controls tabs and the switcher. To use an opaque color:

```toml
[workspace-sidebar]
    auto-hide = true
    chrome-style = 'solid'
    solid-chrome-color = 'blue' # Or choose Custom in Appearance.
```

To keep the full sidebar visible, reserve its expanded width when laying out tiled windows:

```toml
[workspace-sidebar]
    always-expanded = true
    width = 240
```

`always-expanded` takes precedence over `auto-hide`. The outer gap on the selected side remains
the spacing between the sticky sidebar and tiled windows, and monitor selection continues to
control which displays reserve sidebar space.

The sidebar clock can be configured independently:

```toml
[workspace-sidebar]
    show-clock = true
    show-seconds = true
    show-date = true
    show-weekday = true
```

`show-clock = false` hides the entire clock card. Seconds can appear in both
compact and expanded modes. Date and weekday appear only in the expanded sidebar
and are independently controlled; for example, `show-date = false` with
`show-weekday = true` leaves a weekday-only calendar label in the expanded sidebar.

### Window borders

WinMux draws click-through borders around visible managed windows, with a different color for the
focused window. Built-in borders are enabled by default. The settings follow [Dinky's `[borders]` configuration](https://github.com/mikker/Dinky/blob/main/docs/configuration.md#borders):

```toml
[borders]
    enabled = true
    width = 4                     # Points; fractional values are supported.
    active-color = '#e1e3e4'       # #RRGGBB or #RRGGBBAA.
    inactive-color = '#494d64'
    order = 'below'               # 'above' draws the ring over the window.
    exclude-apps = []             # Application bundle IDs.
```

Changes apply on config reload. Borders hide with their windows and in fullscreen. If you previously
started JankyBorders in `after-startup-command`, remove that command and stop the external `borders`
process to avoid drawing two sets of borders.

### Window and sidebar spacing

Settings → Appearance → Window spacing offers six sliders and numeric fields:
space between windows horizontally/vertically, plus the four display edges. The
four-window preview animates as values change; dragging updates the preview and
applies the layout when the gesture ends. Numeric fields apply on Enter or focus
loss. Reduce Motion disables the preview animation. Existing values outside the
slider's usual range remain editable, and disconnected monitor overrides are
preserved.


The `[gaps]` settings control the visible borders around tiled windows. `inner.horizontal`
and `inner.vertical` set the space between neighboring windows. The outer gaps set the space
at each display edge; when the sidebar is enabled, `outer.left` is the space between the
sidebar and the tiled windows on the selected sidebar edge. Any of these values can be reduced or set to zero independently.

For borderless tiling, including no border beside the sidebar:

```toml
[gaps]
    inner.horizontal = 0
    inner.vertical = 0
    outer.left = 0
    outer.bottom = 0
    outer.top = 0
    outer.right = 0
```
### Tab groups

![Tab groups](resources/screenshots/tab-groups.png)

Several windows can share one tile, with a tab bar for choosing which window to
view. This works well for reference windows beside an editor or separate browser
profiles. Click a tab to activate it, rearrange the tabs, or use relative and
absolute keybindings to navigate the group.

Drag a tab into another window's [intent zone](#managed-tiling-mode) or move it to
another workspace through the sidebar.

Settings → Windows → Show tab strips controls the visible tab bar. Turning it off
keeps the group as overlapping windows with offsets. Double-sided windows replaces
the strip for two-window groups when enabled; three or more windows continue to
use tabs. Option-click or Option-Tab flips between the two sides. This preference
requires Show tab strips and Screen Recording access, and respects Reduce Motion.
Tab chrome follows the sidebar's glass or solid style.

<a id="managed-tiling-mode"></a>

### Tiling and floating

With `default-root-container-layout = 'dwindle'`, existing tiled windows also use dwindle at startup,
including tiled roots restored from older saved state. Switching the default to dwindle while WinMux
is running updates existing tiled roots on config reload. Floating windows and tab groups are preserved;
manual layout choices made afterward remain active during ordinary refreshes and unrelated config edits.

WinMux tiles newly discovered windows by default. To keep their existing macOS size and position while still using WinMux's sidebar, workspaces, and manual layout commands, disable automatic tiling:

```toml
automatically-tile-new-windows = false
```

This applies to windows discovered when WinMux starts and windows opened later. You can still tile an individual floating window with `winmux layout tiling` or the configured `layout floating tiling` shortcut.

While dragging a window by its title bar, shake it horizontally to toggle between floating and tiling. The gesture requires several deliberate direction changes in quick succession, and does not activate during resize, sidebar, tab-strip, or tab-group drags. Disable it with:

```toml
enable-shake-to-toggle-tiling = false
```

### Workspace navigation

Empty workspaces are collected when no longer needed. The configured minimum,
legacy persistent names, and active display/project requirements keep the
workspaces that still need to exist. Numeric workspace arguments are display positions; use `workspace --name <name>` to
select an internal workspace name directly.

Workspace activation can target a monitor explicitly:

```shell
winmux workspace 2 --monitor secondary
winmux workspace --name 9
```

Workspace commands activate on the focused monitor unless `--monitor` specifies another display.
Selecting a workspace already visible elsewhere focuses it on its existing display without
moving either workspace or changing monitor history. Hidden workspace activation still respects
`workspace-to-monitor-force-assignment`.
`workspace next` and `workspace prev` skip workspaces visible on other displays; numbering stays
project-wide. `workspace-back-and-forth` and `--auto-back-and-forth` use each display's own history.
Clicking a sidebar activates hidden workspaces on that sidebar's display. A workspace
already visible on another display offers override confirmation before being brought here.

### Multiple monitors

All monitors share the project and workspace list. Each display has its own
sidebar and selects its own workspace. Two displays can use the same project,
but each must show a different workspace.

### Launching apps

WinMux supports single-modifier keybindings, such as triggering an action when
you press `⌘`.

A shortcut that opens a new window helps you launch an app into the current
workspace instead of returning to a window on another workspace. These examples
use separate Chrome profiles and scripts for cmux and Finder:

```toml
[mode.main.binding-tap]
    left-alt = 'exec-and-forget /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --profile-directory="Default"'
    right-cmd = 'exec-and-forget /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --profile-directory="Profile 1"'

[mode.main.binding]
    # Disable the native "Hide App" shortcut.
    cmd-h = []

    cmd-d = 'exec-and-forget osascript ~/Documents/scripts/launchTerminalWindow.scpt'
    cmd-e = 'exec-and-forget osascript ~/Documents/scripts/launchFinderWindow.scpt'
```

```applescript
# ~/Documents/scripts/launchTerminalWindow.scpt
tell application "cmux"
    if it is running
        tell application "System Events" to tell process "cmux"
            click menu item "New Window" of menu "File" of menu bar 1
        end tell
    else
        activate
    end if
end tell

# ~/Documents/scripts/launchFinderWindow.scpt
tell application "Finder"
    if it is running
        tell application "System Events" to tell process "Finder"
            click menu item "New Finder Window" of menu "File" of menu bar 1
        end tell
    else
        activate
    end if
end tell

```

## Installation

Download a ZIP from [WinMuxX releases](https://github.com/gfavaro/WinMuxX/releases)
and extract `WinMuxX.app`, or build this fork with
`make fork-build BUILD_NUMBER=<new-number>`, then install
`.release/WinMuxX.app` as described in [HACKING.md](HACKING.md). Fork builds retain
the configured local signing identity, are not notarized, and have automatic
upstream updates disabled. The upstream Homebrew cask installs WinMux, not WinMuxX.

## Migrating

The fork owns `${XDG_CONFIG_HOME:-~/.config}/winmux-gf/winmux.toml`. On first launch
it copies an existing original WinMux config without modifying it. If no original
config is found, AeroSpace import remains available; otherwise it generates a
starter config. `--config-path` selects an explicit file. See
[fork configuration ownership](docs/FORK.md#app-isolation) for details.

## Credits

WinMuxX is based on ZimengXiong/WinMux. Configuration and command support also
build on [Aerospace](https://github.com/nikitabobko/AeroSpace).
