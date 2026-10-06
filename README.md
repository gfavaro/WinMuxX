
<p align="left">
  <img src="resources/winmux-logo.svg" width="80" alt="WinMux logo">
</p>

# WinMuxX

Personal fork by gfavaro, based on ZimengXiong/WinMux.
See [fork maintenance, builds and releases](docs/FORK.md),
[development guide](HACKING.md), and [documentation index](docs/README.md).
Automatic upstream updates are disabled. Build with `make fork-build`.

<p align="left">A powerful sidebar-first window manager for macOS.</p>

https://github.com/user-attachments/assets/51983568-a168-494f-8ae3-5f50ca1efce1

## Highlights

### Native sidebar appearance

Settings → Appearance controls the sidebar. Choose Liquid Glass for native glass
on macOS 26 and later, or Solid color for an opaque preset/custom color. Earlier
macOS versions use a native material fallback. Reduce Transparency forces an
opaque system background in Liquid Glass. Expanded Liquid Glass always uses a
frosted background; Show background controls the compact rail.

Choose Left or Right, and Standard, Centered or Full height. Every mode reserves
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

Click the WinMux menu-bar icon to browse window, layout, workspace, project and monitor actions.
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

### Projects
Projects are collection of workspaces. Think of it like a parent/child hiearchy, you can switch between projects. Each project has it's own set of workspaces.

### Sidebar
The sidebar is a more interactively-performant and useful alternative to [Sketchybar](https://github.com/felixkratz/sketchybar) and traditional workspace menu bar dropdowns for most everyday tasks. It provides better visibility into spaces and spatial awareness on the desktop.

You can drag windows in and out of the sidebar from and to the current workspace. You can rearrange windows across all spaces using the sidebar, including tab groups.

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

`show-clock` hides the entire clock card. The other settings independently control seconds,
the month and day, and the weekday; for example, `show-date = false` with
`show-weekday = true` leaves a weekday-only calendar label in the expanded sidebar.

### Window borders

WinMux draws click-through borders around visible managed windows, with a different color for the
focused window. The settings follow [Dinky's `[borders]` configuration](https://github.com/mikker/Dinky/blob/main/docs/configuration.md#borders):

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

The `[gaps]` settings control the visible borders around tiled windows. `inner.horizontal`
and `inner.vertical` set the space between neighboring windows. The outer gaps set the space
at each display edge; when the sidebar is enabled, `outer.left` is the space between the
sidebar and the tiled windows. Any of these values can be reduced or set to zero independently.

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
### Tab Groups
![](resources/screenshots/tab-groups.png)
Tab groups allow you to have many windows occupy the same footprint, similar to Yabai stacks but with browser-like tab behavior. This is useful when you want to have multiple pieces of reference information next to an editor, multiple tabs in different browser profiles, or, when you simply want multiple fullscreen views without the additional friction and overhead of creating a new workspace.

Unlike stack-only layouts, WinMux tab groups behave more intuitively like you would expect tabs to in browsers, and don't need a keyboard shortcut to activate. You can drag tabs from tab groups into another window's [intent zone](#managed-tiling-mode), or in between workspaces. You can also rearrange tab order within a tab group, and navigate through them with relative and absolute keybindings.

### Philosophy

#### Automatic tiling

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

#### Workspaces
Empty workspaces are collected when no longer needed, but configured persistent workspaces and the active viewport
workspace can remain empty. Numeric workspace arguments are display positions; use `workspace --name <name>` to
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

### Multi-Monitors
Monitors share the global project/workspace state. Each monitor can be treated as *independent* from each other. They each just use the sidebar to browse through projects and 'select' a workspace to view.

Monitors can not be attached to the same workspace at the same time. They can be on the same project at the same time.

#### App Launching
WinMux supports single-modifer keybindings (e.g. triggering an action on press of `⌘`)

I highly recommend that you configure the apps you use every day to be launch with Left/Right Option+Command, or similar shortcuts, otherwise it might be hard to launch common things into the current workspace (and instead, take you to the other workspace where the app is currently active). Here is some of the apps that I have keybinded:

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

Build this fork with `make fork-build BUILD_NUMBER=<new-number>`, then install
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
[Aerospace](https://github.com/nikitabobko/AeroSpace)

A lone tiled window is centered at a maximum 3:2 ratio on ultrawide screens
(screen width/height at least 2.3). Floating windows, tab groups and WinMuxX
fullscreen bypass this limit. The available area accounts for the sidebar and
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
for the current session. The window keeps the configured alignment and layout height; the
chosen width may exceed 3:2 and is clamped to the available area and application
minimum. Mouse resizing and `resize width`/`resize smart` both support this.
The preference returns when the window becomes a lone tile again.

Use `single-window-alignment = 'center'`, `'left'` or `'right'` to choose its
horizontal position, also available in Settings → Windows. Center is the default.

For a lone ultrawide tile, a mouse resize that changes height switches the window
to floating and preserves the resulting size and position. Width-only resizing
keeps it tiled with the selected alignment. Small native frame rounding changes
are ignored.

Settings groups everyday options into General, Workspaces, Windows, Sidebar,
Appearance and Shortcuts. Automation and the Configuration editor/reference hold
advanced settings. The window can be widened; controls support keyboard access,
accessible names and values, and system accessibility preferences.

`minimum-workspace-count = 1` keeps a minimum total across all projects. Set it to
`0` to disable the configured minimum. Occupied workspaces count; each project
and active display still retains its required workspace. Missing slots are
created in the default project without changing focus. Reducing the minimum
allows only excess empty slots to be collected.

Older configs keep their named `persistent-workspaces` behavior until the
quantity is saved in Settings → Workspaces. Saving replaces the old list with
`minimum-workspace-count`; an explicit count takes precedence over named or
shortcut-inferred persistence.

Appearance → Window spacing has sliders and numeric fields. The four-window
preview updates while dragging; finishing the gesture applies the final value to
the real layout. Per-monitor spacing overrides are preserved. Reduce Motion
turns off preview animation.

Windows → Show tab strips retains the overlapping layout with offsets when off.
Double-sided windows replaces the strip for two-window groups when enabled.
Settings edits preserve dotted TOML properties such as `window-tabs.enabled`,
as well as conventional table sections, comments and multiline monitor rules.
