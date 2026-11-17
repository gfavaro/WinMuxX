# Windows

How lone windows, tab groups, stacks and floating windows behave.

## Lone windows and fullscreen width

Choose a share of the available width for a lone tiled window and WinMuxX's
`fullscreen` command, on any display:

```toml
fullscreen-width = 0.70
single-window-alignment = 'center' # center | left | right
```

`fullscreen-width` accepts `0.1` to `1.0`; the default is `1.0`. Width is measured
after the sidebar and outer gaps. Known application minimum widths take priority,
up to the available width. Lone tiled windows and WinMuxX fullscreen are centered.
macOS native fullscreen is unaffected.

A second tiled window restores the usual full-width layout. Floating windows,
minimized windows, hidden apps and popups do not count toward the lone tile.
Settings → Windows exposes the global width percentage and shows
the current workspace's resolved values. Display and workspace overrides use
tables; omitted keys inherit independently:

```toml
[display.'Built-in']
fullscreen-width = 0.70

[workspace.3]
fullscreen-width = 0.80

[workspace.3.display.'Built-in']
fullscreen-width = 0.65
```

Precedence is workspace/display → workspace → display → global. Named display
patterns beat main/secondary; longer names win, then lexical order. Exact UUID,
hardware and display-number selectors take priority over name patterns. Existing
layout/orientation policies retain their existing selector ordering. Width changes
preserve manual layout choices and the workspace tree.

Width-only mouse resizing and `resize width`/`resize smart` keep a lone window
tiled and centered. The manual width lasts for the window's session,
including after another tile opens and closes. A mouse resize that changes height
makes it floating and preserves its size and position. Small native frame rounding
changes are ignored.

The old `single-window-aspect-ratio` setting remains readable for compatibility
when no explicit width applies. New configs use `fullscreen-width`; an explicit
width, including `1.0`, takes priority over the old setting. To migrate, replace the root
`single-window-aspect-ratio` line with `fullscreen-width` and
`single-window-alignment`; 70% is a new preference, not an exact conversion of a
3:2 ratio.

## Layout for the next window

Run `winmuxx layout floating --for-next-detected-window` before opening a window
(or use `tiling` instead of `floating`). This changes only the next newly detected
normal window; existing windows keep their layout. The request applies once,
overrides automatic layout rules, and a second request replaces the first.
Popups, native fullscreen/minimized/hidden windows and windows restored from saved
state do not consume it. The request stays in memory until used or WinMuxX quits.
Only one `floating` or `tiling` argument is allowed, without `--window-id`.

## Tab groups

![Tab groups](../resources/screenshots/tab-groups.png)

Several windows can share one tile, with a tab bar for choosing which window to
view. This works well for reference windows beside an editor or separate browser
profiles. Click a tab to activate it, rearrange the tabs, or use relative and
absolute keybindings to navigate the group.

Drag a tab into another window's [intent zone](#managed-tiling-mode) or move it to
another workspace through the sidebar.

A tab group reserves no space above its windows. Its pills sit in the gap, centred on the
group's top edge, one per tab: the active window's is longest and uses the accent colour,
and in a strip the other columns on screen are lighter. Resting the pointer on that edge
opens the hover bar with a row of tabs (icon and title; click one to switch) above the
window's actions, each with its configured shortcut. The pill rail remains visible
independently of quick actions.

Settings → Windows → Show tab strips controls the visible tab bar. Turning it off
keeps the group as overlapping windows with offsets. Set `window-tabs.double-sided-windows = true` to replace
the strip for two-window groups when enabled; three or more windows continue to
use tabs. Option-click or Option-Tab flips between the two sides. This preference
requires Show tab strips and respects Reduce Motion. The flip turns two cards
showing each window's app icon.
Tab chrome follows the sidebar's glass or solid style.

Flip images are captured off the main thread at a bounded resolution. If capture
is not ready within 80 ms, the window switches without a delayed animation.

<a id="managed-tiling-mode"></a>

Dragging a window onto another creates a tab group. Existing tab groups keep their
layout; edge drops still split normally.

## Stacked layouts

Stacked windows have two variants: **Tabbed** shows one window at a time, with a
pill per window on the group's top edge; **Strip** (`layout strip`) shows them side
by side as columns that scroll within the group, see
[layouts](LAYOUTS.md#container-modes-and-tabs). Choose Tabbed in Settings →
Windows for new roots, or use `winmuxx layout tabbed strip` to toggle the focused
container. `layout tab-group` remains supported. The accordion layout was removed;
`accordion` and `stacked` in configuration and commands now give a tab group.

## Tiling and floating

With `default-root-container-layout = 'dwindle'`, existing tiled windows also use dwindle at startup,
including tiled roots restored from older saved state. Switching the default to dwindle while WinMux
is running updates existing tiled roots on config reload. Floating windows and tab groups are preserved;
manual layout choices made afterward remain active during ordinary refreshes and unrelated config edits.

WinMux tiles newly discovered windows by default. To keep their existing macOS size and position while still using WinMux's sidebar, workspaces, and manual layout commands, disable automatic tiling:

```toml
automatically-tile-new-windows = false
```

This applies to windows discovered when WinMux starts and windows opened later. You can still tile an individual floating window with `winmux layout tiling` or the configured `layout floating tiling` shortcut.

The WinMuxX menu's **Always Float “App”…** (hold Option for **Float Windows by Title…**) saves an ordered `on-window-detected` rule in your configuration. Window rules run in file order; if an earlier stopping rule may match, WinMuxX opens the configuration for review instead of silently changing its behavior. Restored windows keep their saved placement.

While dragging a window by its title bar, shake it horizontally to toggle between floating and tiling. The gesture requires several deliberate direction changes in quick succession, and does not activate during resize, sidebar, tab-strip, or tab-group drags. Disable it with:

```toml
enable-shake-to-toggle-tiling = false
```
