# Borders and spacing

Window borders and the gaps between tiled windows.

## Window borders

WinMux draws click-through borders around visible managed windows, with a different color for the
focused window. In tabbed layouts, one border encloses the tab panel and the active
window together, using the group’s outer corner shape. Built-in borders are enabled by default. The settings follow [Dinky's `[borders]` configuration](https://github.com/mikker/Dinky/blob/main/docs/configuration.md#borders):

```toml
[borders]
    enabled = true
    width = 4                     # Points; fractional values are supported.
    active-color = 'accent'        # 'accent' (accent-color or the system accent), #RRGGBB or #RRGGBBAA.
    inactive-color = '#00000000'   # Transparent: only the focused window has a border.
    order = 'below'               # 'above' draws the ring over the window.
    exclude-apps = []             # Application bundle IDs.
```

Changes apply on config reload. Borders hide with their windows and in fullscreen. If you previously
started JankyBorders in `after-startup-command`, remove that command and stop the external `borders`
process to avoid drawing two sets of borders.

## Window and sidebar spacing

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
