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
- `persistent-workspaces` keeps the named slots you choose, in the configured order.
- Settings has separate Sidebar and Appearance pages, accessible controls, and
  animated spacing previews.
- Sidebar, tab groups and the switcher share glass or solid styling. Expanded glass
  surfaces use a frosted background.
- Selecting a workspace already visible on another display focuses it there.
  Sidebar clicks on another display ask before bringing the workspace there.
- Learned application minimum sizes constrain layouts. Borders use an AppKit
  fallback when the private renderer is unavailable.
- The native menu includes diagnostics and recovery of original window frames
  after an interrupted session.

The app has its own identity, CLI, configuration and recovery state. On first
launch, it can copy your original WinMux configuration while leaving that file
untouched. Releases use `gf-v` tags in this repository.

Run `winmuxx` or `winmuxx --help` to list all CLI commands, including compatibility
aliases. Use `winmuxx <command> --help` for details. Help works without the app running.

## Settings

Open Settings from the WinMuxX menu. The window is resizable, and the controls
support keyboard navigation, accessible labels and values, Reduce Motion, Reduce
Transparency, and increased contrast.

| Page | Options |
| --- | --- |
| General | Start at login and automatic configuration reload |
| Workspaces | Persistent workspace names/order, project deletion behavior and workspace shortcuts |
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
TOML stores all behavior and appearance preferences, including the menu bar and
double-sided windows. Settings writes the same file and reloads it. Window placement,
learned application sizes and the last-opened Settings page remain local session data.
See [configuration and migration](docs/CONFIGURATION.md).

## How it works

### Single window on ultrawide

One tiled window is centered at a maximum 3:2 ratio on ultrawide screens
(screen width/height at least 2.3). The limit applies only when the workspace has
one tiled window; floating windows do not count. Minimized windows,
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

With auto-hide enabled, reach the outermost **2 points** of the chosen display
edge to reveal the sidebar, like the Dock. The hidden trigger is independent of
the collapsed rail size. The wider exit tolerance applies after revealing.
The sidebar waits 400 ms before revealing on hover by default. Change
`hover-open-delay-ms` in `[workspace-sidebar]`, or **Settings → Sidebar → Hover
reveal delay**. Moving away cancels the pending reveal. A left-button press begun
outside the sidebar keeps a collapsed sidebar from revealing or trapping the
pointer during text selection; releasing starts a fresh hover delay. Sidebar
clicks, recognized window/sidebar drags, and `winmuxx open-sidebar` retain their
existing immediate interactions.

Tiled windows glide into place by default (150 ms). Set `animations.enabled = false`
or `animations.duration-ms = 0` for immediate placement. Reduce Motion disables
the glide. See [window motion](docs/WINDOW_MOTION.md) for configuration and limits.

```toml
[workspace-sidebar]
    hover-open-delay-ms = 400 # 0–5000; Settings → Sidebar → Hover reveal delay
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
native action menu. Settings saves these choices to TOML:

```toml
[menu-bar]
indicator = 'icon'          # icon or workspace
icon-appearance = 'color'  # color or monochrome
```

### Layout for the next window

Run `winmuxx layout floating --for-next-detected-window` before opening a window
(or use `tiling` instead of `floating`). This changes only the next newly detected
normal window; existing windows keep their layout. The request applies once,
overrides automatic layout rules, and a second request replaces the first.
Popups, native fullscreen/minimized/hidden windows and windows restored from saved
state do not consume it. The request stays in memory until used or WinMuxX quits.
Only one `floating` or `tiling` argument is allowed, without `--window-id`.

### Menu-bar actions and diagnostics

The tray menu follows Dinky’s everyday actions: workspace navigation and moves,
Focus, Move Window, Join With, Resize, Layout, Fullscreen and Balance Sizes.
Display and Mode menus appear only when there is more than one choice. Settings,
Reload Config, Enabled and Quit remain directly accessible. Projects, tab controls,
extra container operations, utilities and maintenance tools stay in Settings or the CLI.
Shortcuts come from the effective configuration for the active mode, and the menu updates whenever
it opens. Actions without shortcuts remain clickable. Custom command chains, modifier taps and key sequences remain available through configuration.

Dinky 0.19 adaptations include `hyper`/`meh` shortcut aliases, bundle-ID regex
rules, optional workspace layouts per display, settled display-change actions,
and window recovery/performance fixes. See [configuration and comparison notes](docs/DINKY_019_ADOPTION.md).

Dinky 0.20 adaptations add optional master layout / `swap-with-master`,
app-activation exclusions, browser overlay filtering, and original-frame restoration
on disable/quit. See [options and behavior](docs/DINKY_020_ADOPTION.md). In master
mode, `layout tiles accordion` toggles only the stack from any tiled window;
`workspace-layout dwindle` returns the workspace to its splitting tree.

Dinky 0.21 command separation uses `workspace-layout dwindle master` to toggle
workspace modes; `layout` only changes containers or floating/tiling. Existing
`layout dwindle` and `layout master` bindings must be migrated. Three-option
container cycles now visit every option, and `%{workspace-layout}` reports the
workspace mode. See [migration and behavior](docs/DINKY_021_ADOPTION.md).

Run `winmuxx doctor` to inspect the loaded config path, file validation, effective default layout,
permissions, monitors, potentially conflicting window managers and per-app accessibility latency.
The report uses the same diagnostics generator as the app.
Checks do not change macOS preferences or stop other apps. Review local paths and app names before
sharing a report. Upcoming improvements are tracked in [the roadmap](docs/ROADMAP.md).

After an interrupted session, the menu can offer **Recover N Windows from Previous Session…**.
Recovery pauses tiling and restores the original positions and sizes recorded before WinMux moved
the windows. It validates the owning app's process and launch identity, skips disconnected displays
and native fullscreen/minimized windows, and retains failed entries for another attempt. Turn
**Enabled** back on to resume tiling. The recovery journal is separate from the saved managed layout.

Workspace assignments are also saved during use (with a one-second delay) and on
normal quit. Routine saves use a bounded background writer and skip unchanged
snapshots; normal quit waits for the final snapshot. Restarting WinMuxX or updating
it preserves workspace names, projects
and automatic display numbers. Existing windows are verified against their app
and process launch; after an app or computer restart, matching prefers the document
URL and AX window identifier exposed by the app. A unique nonempty title is the
fallback. Conflicting documents/identifiers and ambiguous matches are skipped.
Apps may reopen later: pending assignments survive subsequent WinMuxX restarts.
Changed titles can still match by document/identifier. Apps with delayed metadata
are retried for up to 30 seconds, stopping if window placement changes. WinMuxX
does not reopen apps or documents itself. During startup, available windows recover their saved layout;
Tiled sizes follow saved layout proportions on the current monitor. Floating sizes
and the manual width of a single tiled window are saved too; oversized floating
windows fit the available screen, and fullscreen/minimized windows are not resized.
For 30 seconds after startup, delayed windows from the same app process also
recover their saved tree slots and split ratios, provided no layout-changing command,
mouse edit, or unrelated new window has intervened. Later arrivals recover their
workspace without replaying old layouts over current user changes. State lives in `window-state.json` in the fork's Application Support
directory, with a previous valid snapshot as backup. Monitor matching uses display
UUIDs when available, with coordinates as fallback for older snapshots. Deleted
workspaces discard pending assignments, and late arrivals respect current project
assignments. Diagnostics reports the number of windows still awaiting a unique
match. Old ID-only snapshots cannot
safely match reopened windows; this build starts recording verified identities.

### Workspaces to keep

Workspace names use a custom label from `[workspace-sidebar.workspace-labels]`
when configured. Persistent numeric names display `Workspace N` using the configured
number; persistent text names display literally. Other workspaces use a dynamic
`Workspace N` fallback. With persistent slots, automatic numbers use the lowest
available number, skipping configured numeric names. Without persistent slots,
the fallback follows the current position in the project's presented list.
Renaming in the sidebar saves the custom label to TOML. Internal workspace IDs
remain unchanged.

Settings → Workspaces → Persistent workspaces saves the names to keep, in array
order. Other empty workspaces are collected when no longer needed. Each project
and active display retains a usable workspace, and a temporary blank can stay
visible while you open a window there.

```toml
persistent-workspaces = ["1", "3", "5", "7"]
```

The sidebar lists Workspace 1, Workspace 3, Workspace 5 and Workspace 7 in that
order. A newly created automatic workspace uses the first unreserved number,
Workspace 2. Numeric workspace commands match those displayed numbers. Named
entries such as `"Code"` keep their name; use `workspace --name Code` to select the
internal name explicitly. Custom labels override display names without changing
internal names or shortcut targets.

`minimum-workspace-count` is removed. Startup converts an older count to explicit
persistent names and saves a backup. Existing names and their order are preserved;
missing slots receive the first unused positive numeric names. There is no ongoing
count-based creation or retention. See [migration details](docs/CONFIGURATION.md).

Saved restart assignments protect workspaces while startup is rebuilding their
windows. After startup, stale assignments alone cannot retain an empty workspace.
Live minimized and hidden windows still protect their owning workspaces.
After you explicitly select a workspace, apps launched afterward open there
instead of returning to an old saved destination. Windows of apps already running
remain eligible for restart restoration.

### Projects

A project groups its own workspaces. Switch projects in the sidebar to keep
different sets of windows together.

### Sidebar
The sidebar shows your workspaces beside your windows. You can use it as an
alternative to [Sketchybar](https://github.com/felixkratz/sketchybar) or a workspace
menu in the menu bar.

Drag windows or tab groups through the sidebar to move them between workspaces.
You can also drag a window back onto the current workspace.

When the expanded sidebar is open, **Up/Down** moves the highlighted selection
through workspace headers and window rows, **Return** activates it, and **Esc**
closes the sidebar. Typing filters the list; arrow navigation also works before
you enter a search query. The selected row scrolls into view.

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
focused window. In tabbed layouts, one border encloses the tab panel and the active
window together, using the group’s outer corner shape. Built-in borders are enabled by default. The settings follow [Dinky's `[borders]` configuration](https://github.com/mikker/Dinky/blob/main/docs/configuration.md#borders):

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
keeps the group as overlapping windows with offsets. Set `window-tabs.double-sided-windows = true` to replace
the strip for two-window groups when enabled; three or more windows continue to
use tabs. Option-click or Option-Tab flips between the two sides. This preference
requires Show tab strips and Screen Recording access, and respects Reduce Motion.
Tab chrome follows the sidebar's glass or solid style.

Flip images are captured off the main thread at a bounded resolution. If capture
is not ready within 80 ms, the window switches without a delayed animation.

<a id="managed-tiling-mode"></a>

### Stacked layouts

Stacked windows have two variants: **Tabbed** keeps the current tab strip and
shows one window at a time; **Accordion** keeps overlapping windows visible with
peeking edges, like AeroSpace. Choose either in Settings → Windows for new roots,
or use `winmuxx layout tabbed accordion` to toggle the focused container.
`layout tab-group` remains supported. `layout horizontal` and `layout vertical`
choose the accordion axis; `tab-group-padding` controls its peeking edges.
Accordion never shows tab strips or uses double-sided windows.

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

Empty workspaces are collected when no longer needed. Explicit persistent names,
a visible temporary blank and active display/project requirements keep the
workspaces that still need to exist. Numeric workspace arguments are display positions; use `workspace --name <name>` to
select an internal workspace name directly.

Workspace activation can target a monitor explicitly:

```shell
winmux workspace 2 --monitor secondary
winmux workspace --name 9
```

Workspace commands resolve navigation and new slots on the focused monitor unless
`--monitor` specifies another display. Existing workspaces retain their owning display.
Selecting a workspace focuses it on its owning display, whether visible or hidden,
without relocating it. Use `move-workspace-to-monitor` or `summon-workspace` explicitly
to move it; subsequent switches remember that display. New, unassigned workspaces
use the focused display or an explicit `--monitor` target.
`workspace next` and `workspace prev` skip workspaces owned by other displays; numbering stays
project-wide. `workspace-back-and-forth` and `--auto-back-and-forth` use each display's own history.
Clicking a workspace assigned to another display in a sidebar offers Override / Cancel,
whether the workspace is visible or hidden. Override brings it to that sidebar’s display;
Cancel changes nothing.
For a workspace on another display, its sidebar context menu offers **Bring Here**:
bring it to the display containing that sidebar. On a secondary display, the previous
workspace returns to main, hidden and reachable by shortcuts or swipes. Main can own
multiple workspaces; each secondary is replaced by the explicitly brought workspace.
Reconciliation also returns hidden secondary assignments to main after restoration
or display changes, keeping only the visible workspace on each secondary.
Forced assignments still apply. The source gets a local fallback or empty workspace;
other displays keep their current workspace.

At launch, display ownership is restored by default. Enable **Settings → General →
Startup → Start workspaces on main display** (`start-workspaces-on-main-monitor = true`)
to start existing workspaces on main instead. Secondary displays receive empty
workspaces. Explicit forced assignments still apply; **Automation → After startup**
can run existing `move-workspace-to-monitor` commands for optional startup placement.
The toggle only affects launch, not configuration reloads or normal switching.

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

### Shortcut modifier sides

Settings → Shortcuts → Modifier keys chooses Both, Left or Right independently
for Option, Command, Control and Shift. The default is Both. For example:

```toml
[modifiers]
alt = 'left'
cmd = 'both'
ctrl = 'both'
shift = 'both'
```

Left Option then runs Option shortcuts; right Option remains available for typing.
Pressing both sides of a restricted modifier passes through too. Modifier-only tap
bindings keep their explicitly configured sides. Accessibility access is required.

Confirmed application minimum sizes persist across restarts. Use **Clear Saved
Minimum Sizes…** in the menu to clear saved and current observations.

### Window search palette

The window search palette lists windows across workspaces and projects. Filter
the list by typing, then select a window to focus it. Open it with a normal
shortcut or a tap-only shortcut:

```toml
[mode.main.binding]
    alt-o = 'palette'

[mode.main.binding-tap]
    right-cmd = 'palette'
```

The right Command tap opens the palette when it is closed and closes it when
it is open. Press `Escape` to close it. A modifier tap does not run when you
use that modifier as part of another shortcut.

Use `winmuxx palette --group-by-workspace` (or bind
`palette --group-by-workspace`) to group matches under workspace headings.
The palette's **Group by workspace** button switches between grouped and flat
results for the current opening. Groups keep the opening workspace order, with
the focused workspace first; matches keep fuzzy ranking within each group.
Headings show workspace display labels and project names. Up/Down, Return and
⌘1–⌘9 count window rows only. Bare `palette` retains the flat list.
Search uses a native macOS search field, including its clear button and standard
text-editing commands. Input-method composition keeps priority over navigation
and quick-select shortcuts. Results use standard selectable rows and adaptive
system colors; glass follows system appearance, while opaque custom chrome
keeps its configured color with a contrasting light or dark appearance.

### Workspace overview

`winmuxx workspace-overview` toggles a spatial overview of the current project.
Each display shows its own workspace cards, preserving saved window positions,
sizes and overlap. Click a card to switch workspaces or a window to focus it.
Arrow keys select cards, Tab selects windows, Return activates, and Escape closes.
Page Up/Down or Previous/Next navigate more than twelve cards on a display.
The `show` and `hide` arguments are idempotent.

```toml
[mode.main.binding]
    alt-shift-o = 'workspace-overview'

[workspace-overview]
    three-finger-up = false # opt in after adjusting macOS Mission Control
```

The optional three-finger upward gesture opens the overview. A three-finger
downward gesture closes it whenever it is open, including when opened by command
with the upward shortcut disabled. The overview follows your fingers while swiping
up or down; reversing a short swipe returns it to its starting state. Release
settles with your swipe velocity. Opening and closing share the workspace-swipe
spring and `workspace-swipe.animation-duration-ms`. The overview uses the expanded
sidebar's translucent frosted material; Reduce Transparency supplies an opaque
background. Reduce Motion and disabled
animations skip motion. Assign macOS Mission Control to four fingers or disable its trackpad
gesture first; WinMuxX does not change macOS settings. Horizontal workspace swipes
and the overview gesture can be enabled independently.

Minimized windows, hidden apps, native full-screen windows and popups are excluded.
Ordinary windows on inactive WinMuxX workspaces remain included. Previews are
captured on demand and stay static. Missing permission or unavailable contents
fall back to app icons and saved outlines. Windows without saved geometry appear
in a menu beneath their card. There is no dragging or continuous live capture.
See [overview implementation and validation](docs/WORKSPACE_OVERVIEW.md).

### Example launch scripts

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

The `winmuxx` command can be linked into your PATH after installation:

```sh
ln -s /Applications/WinMuxX.app/Contents/MacOS/winmuxx-cli /opt/homebrew/bin/winmuxx
```

The link follows future app updates. Choose another existing directory in PATH
if Homebrew is not installed.

## Migrating

The fork owns `${XDG_CONFIG_HOME:-~/.config}/winmuxx/winmux.toml`. On first launch
it copies the previous `winmux-gf/winmux.toml`, or an original WinMux config if no
previous fork config exists, without modifying the source. If no original
config is found, AeroSpace import remains available; otherwise it generates a
starter config. `--config-path` selects an explicit file. See
[fork configuration ownership](docs/FORK.md#app-isolation) for details.

## Credits

WinMuxX is based on ZimengXiong/WinMux. Configuration and command support also
build on [Aerospace](https://github.com/nikitabobko/AeroSpace).

The **Windows → Default layout → Default drag stack** setting chooses Accordion or
Tabbed for new groups created by dragging (`drag-stack-layout = 'accordion'` or
`'tab-group'`). Existing groups keep their layout; edge drops still split normally.

### Experimental workspace swipes

**Settings → Windows → Workspace swipes — experimental** enables raw trackpad
recognition. It is off by default:

```toml
[workspace-swipe]
enabled = false
reverse-direction = false
animation-duration-ms = 220
```

Exactly three touching fingers moving horizontally select the next/previous existing
workspace on the display under the pointer. Left means next, right means previous;
reverse direction is optional. Navigation stays within that display and project,
stops at either end, and never creates, moves or swaps workspaces.

Previews follow your three fingers with progressive resistance after a small
horizontal movement. A short quick flick or a longer drag followed by release
commits the switch. Pulling back before release reduces progress and can cancel it. Each gesture selects at most one adjacent
workspace. Partial lifts finish the gesture using its last three-finger position;
extra/replaced contacts and invalid frames cancel it. Window dragging/resizing blocks it.

Only snapshots move during the gesture; real workspace activation waits for release.
The preview is clipped to the target display and leaves its sidebar fixed. Snapshot
images are cached in memory (up to four images / 64 MiB), while fresh incoming
images are prepared off the main thread. Cached content refreshes while dragging
and freezes on release. A cold preview appears only if ready before release;
otherwise navigation proceeds without a delayed animation. Incoming previews use
windows' last visible positions. Perceptual settling defaults to 220 ms and follows
the remaining distance; the spring can take longer to settle completely. Global animations,
Reduce Motion, a zero settle duration or missing Screen Recording access disable the
visual preview while retaining release-to-switch navigation. Keyboard/mouse actions,
disabling, sleep and display changes clear the preview. No screen images are saved.
Ordinary one/two-finger movement is not turned into workspace navigation and does
not dispatch main-thread work on every raw frame.

The backend loads macOS's private MultitouchSupport API dynamically. Missing symbols
or unavailable devices leave gestures unavailable without affecting tiling. Driver
callbacks copy only scalar summaries into a bounded queue; pointer data never escapes
the callback. Wake and device topology changes re-register the devices. Disable the
feature to unregister the callbacks. The binding and recognizer are independently
implemented; OmniWM's raw-touch architecture was reviewed as a reference.

Set **System Settings → Trackpad → More Gestures → Swipe between full-screen apps**
to four fingers or off so the native gesture does not run alongside WinMuxX. This
backend does not change system preferences or suppress macOS gestures. Test in Safari,
Ghostty and another app before keeping it enabled. Settings shows backend registration
and the highest finger count detected; `winmuxx doctor` also reports received frames.
