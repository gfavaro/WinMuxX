# Sidebar

The sidebar lists your projects, workspaces and windows. Appearance is shared with tab groups and the switcher.

## Sidebar
The sidebar shows your workspaces beside your windows. Use it instead of a
workspace menu in the menu bar.

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

## Native sidebar appearance

Settings → Appearance controls the shared visual style; Settings → Sidebar controls
placement, sizing and content. Choose Liquid Glass for native glass,
or Solid color for an opaque preset/custom color. Reduce Transparency forces an
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
The sidebar waits a fixed 400 ms before revealing on hover. Moving away cancels
the pending reveal. A left-button press begun
outside the sidebar keeps a collapsed sidebar from revealing or trapping the
pointer during text selection; releasing starts a fresh hover delay. Sidebar
clicks, recognized window/sidebar drags, and `winmuxx open-sidebar` retain their
existing immediate interactions.

Tiled windows glide into place by default (150 ms). Set `animations.enabled = false`
or `animations.duration-ms = 0` for immediate placement. Reduce Motion disables
the glide.

```toml
[workspace-sidebar]
    chrome-style = 'liquid-glass' # or 'solid'
    menu-bar-background = false
    position = 'left'            # or 'right'
    height-mode = 'standard'     # or 'centered', 'full'
```

`appearance`, `background` and `frosted-tint` remain accepted for older configs;
`chrome-style` is the appearance selector used at runtime. Legacy
Standard height keeps a fixed 28-point minimum menu-bar reservation; other modes
use the measured menu bar.
