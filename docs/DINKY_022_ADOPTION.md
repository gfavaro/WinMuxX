# Dinky 0.22: width percentages and lone-window placement

Reference: [Dinky v0.22](https://github.com/mikker/Dinky/releases/tag/v0.22),
commit `cd1d3ca`. This adaptation covers `fullscreen-width` and its override
structure. The release's drag splitting and hidden-window listing changes are
separate work.

## Configuration

```toml
fullscreen-width = 0.70
single-window-alignment = 'center' # center | left | right

[display.'Built-in']
fullscreen-width = 0.70

[workspace.3]
fullscreen-width = 0.80

[workspace.3.display.'Built-in']
single-window-alignment = 'right'
```

The simple two-line global configuration is sufficient for one screen. Width
accepts finite numbers from `0.1` through `1.0`; missing width defaults to `1.0`
unless an explicit legacy aspect-ratio setting is present. Alignment defaults to
center. Both keys support display, workspace and workspace/display scopes.

Each omitted key inherits: workspace/display → workspace → display → global.
The most specific matching display table wins at each scope. Named patterns beat
main/secondary; longer patterns win, with lexical order breaking ties. WinMuxX
also supports UUID, hardware and numbered selectors, which take priority over
names. Existing layout/orientation selector precedence is preserved separately.
Workspace identifiers are internal names, not sidebar positions.

## Geometry and behavior

- Percentages use the available width after sidebar and outer gaps, on any
  display, including the built-in screen. There is no ultrawide threshold.
- A lone tiled window uses the width and chosen alignment. A second tile restores
  the workspace's full available area. Floating, minimized, hidden and popup
  windows do not count as tiles. Master and tabbed/accordion roots are supported.
- WinMuxX `fullscreen` uses the configured width and stays centered. Native macOS
  fullscreen is unchanged. `fullscreen --no-outer-gaps` measures the fraction
  against the ungapped visible display area, preserving the command's semantics.
- Application minimum widths can exceed the percentage, bounded by available
  width. Lone-window mouse and keyboard width resizing preserve tiling; changing
  height by mouse floats the window. Manual width is retained for the window's
  session and temporarily bypassed by fullscreen.
- Width/alignment reloads and display changes resolve the new geometry without
  rebuilding the workspace tree or resetting manually selected layouts.

Settings → Windows edits the global width percentage and alignment. It shows the
current workspace's effective values and display. Saving globals preserves
override tables. The editor schema includes all four scopes and valid ranges.

## Migration

Replace the root-level `single-window-aspect-ratio` line with:

```toml
fullscreen-width = 0.70
single-window-alignment = 'center'
```

70% is a new preference, not an exact mathematical conversion of a 3:2 aspect
ratio. An exact conversion would depend on usable display dimensions.

The legacy key and its per-monitor array syntax remain accepted when no width
applies, preserving the original ultrawide-only behavior. Explicit width at any
scope wins over legacy sizing. `fullscreen-width = 1.0` explicitly selects the
new full-width behavior. New reference configs use `1.0`; personal width is 70%.

The personal migration is staged privately at
`.local/validation/dinky-022/pending-winmux.toml`. The installed app and active
configuration are left in place until installation is requested.

## Validation

Regression tests cover input validation at all scopes, inheritance and selector
ordering, laptop geometry and alignment, minimum widths, second-window
transitions, centered fullscreen and gap handling, layout preservation and manual
resizing. Existing aspect-ratio regressions remain as compatibility coverage.
The parser/schema fixtures include valid and out-of-range nested width configs.

`make check` passed: 1,359 Swift tests, 51 Python tests, all 13 shared schema
fixtures, and dependency lockfile resolution. Logs are retained privately at
`.build/width-check.log`. `git diff --check` passed.

Tests exercise model and layout behavior. Live visual validation remains for the
installation step.
