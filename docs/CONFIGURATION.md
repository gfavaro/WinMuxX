# Configuration

`[workspace-backend] type = "virtual"` is the default. This feature branch also
accepts `"native"` for experimental read-only Space observation. An additional
`[native-spaces] tiling-enabled = true` opts into the development Dwindle/Master
implementation; both selections require restart. `restore-layouts = true` is the
default and uses a separate native file when tiling is enabled; `restore-frames-on-quit = true`
puts tiled windows back where they started on quit or `enable off`. Initial single-host
positioning/focus/fullscreen checks passed; the broader native validation matrix
remains pending. See [Native Spaces](NATIVE_SPACES.md)
for opt-in, rollback, unsupported commands and failure handling.

For TOML editor completion, use the checked-in
[WinMuxX JSON Schema](schemas/winmuxx.schema.json) with a TOML editor that
supports JSON Schema. Keep the schema beside your local documentation or use its
raw GitHub URL after publication. It describes common field types and choices;
WinMuxX's parser and runtime remain authoritative for command strings, monitor
selectors and cross-field rules. The parser rejects unknown keys; the schema
adds editor completion and earlier feedback.

The schema is Draft 2020-12. To run the same fixture check used by `make check`,
install the pinned Python dependencies into a local virtual environment:

```sh
python3 -m venv .deps/config-schema
./.deps/config-schema/bin/pip install --requirement requirements-schema.txt
./.deps/config-schema/bin/python script/test_config_schema.py
```

For Visual Studio Code with the [Even Better TOML extension](https://marketplace.visualstudio.com/items?itemName=tamasfe.even-better-toml),
associate the local schema from workspace settings (adjust the path if your config lives elsewhere):

```json
{
  "evenBetterToml.schema.associations": {
    "(^|[/\\\\])winmux\\.toml$": "./docs/schemas/winmuxx.schema.json"
  }
}
```

For example, `default-root-container-layout = "tiles"` receives completion,
while `default-root-container-layout = "grid"` is flagged because `grid` is
not a supported layout. This is editor assistance; `winmuxx doctor` and the
application parser remain authoritative.

The loaded TOML file is the source of behavior and appearance preferences.
Settings edits that file, validates it and reloads the app. Raw edits and Settings
changes use the same configuration fields. `winmuxx doctor` reports the loaded
path; `winmuxx reload-config --dry-run --no-gui` validates without writing or
publishing changes. The default file is `~/.config/winmuxx/winmux.toml`.

## Persistent workspaces

Use names in the order you want to see them:

```toml
config-version = 2
persistent-workspaces = ['1', '3', '5', '7', 'Code']
```

These workspaces remain available when empty. Numeric names retain their number;
text names retain their text. Sidebar labels in
`[workspace-sidebar.workspace-labels]` override the displayed label. Automatic
workspaces use unreserved numbers. Projects and active displays retain a usable
workspace, and a visible temporary blank remains usable until you leave it.
Other unneeded empty workspaces are collected. Hidden/minimized live windows and
startup window restoration have their own lifecycle protection.

There is no configurable minimum count. For compatibility, the old
`minimum-workspace-count` is converted to explicit persistent names. Existing
names and order win; missing entries use the first unused positive numeric names.
For example, a count of 4 with `['3', 'Code']` becomes `['3', 'Code', '1', '2']`.
A zero count adds no names. A smaller count never removes explicit names.
Version-1 shortcut-derived persistent names are preserved if migration needs to
upgrade the file to version 2. Automatic conversion accepts counts from 0 to 4096;
replace larger old counts with an explicit list.

## Menu bar and two-sided tab groups

```toml
[menu-bar]
indicator = 'icon'          # icon or workspace
icon-appearance = 'color'  # color or monochrome

[window-tabs]
enabled = true
height = 36
double-sided-windows = false
```

Menu-bar settings apply on reload. Double-sided windows require enabled tab
strips and exactly two window children. Larger groups keep their tabs. Rotation
uses Screen Recording permission and respects Reduce Motion. These preferences
have no runtime fallback to UserDefaults.

The icon represents the focused workspace arrangement: Dwindle uses four
progressive panes, Master uses a large left pane with two stacked panes on the
right, and Scrolling shows a centered column with neighboring columns. The
symbols stay fixed as windows, nested layouts, or master orientation change.
Color uses the macOS system accent; monochrome is a template icon that follows
the menu bar. An active keyboard mode tints either icon. The workspace text
indicator remains the workspace label or number.

## Migration and backups

At startup, an editable config is migrated before loading. Legacy
`doubleSidedWindows`, `menuBarIndicator` and `iconAppearance` preferences are
imported only when the corresponding TOML key is absent. Explicit TOML values
win. The old preference keys are removed only after a validated write succeeds.
Removing a TOML key later restores its default; an old preference cannot return
on the next launch.

Changed files use the normal atomic config writer. The original is saved as
`winmux.toml.backup.1`; up to five backups are kept. Invalid configuration is not
rewritten and its legacy preferences remain available for retry. Migration is
idempotent. Parsing, diagnostics and dry-run reloads do not modify files.

## Configuration versus session data

TOML holds user-selectable behavior, appearance, shortcuts, automation, workspace
labels and forced monitor assignments. Copying the file reproduces those choices.

Saved window identities/positions, active workspaces, temporary layout overrides,
project/session layout, crash recovery and learned app minimum sizes are runtime
state. The last-opened Settings page is UI state. These remain outside TOML and
do not override its preferences. macOS permissions and login-service registration
are OS state; the TOML `start-at-login` preference controls the desired registration.

## App theme

Set the root-level key before any TOML table:

```toml
appearance = 'system' # system, light, or dark
```

The same value appears in Settings → Appearance → Theme. It applies to WinMuxX
windows, the expanded sidebar, palette, workspace overview, and tab chrome.
System follows macOS Light/Dark appearance and updates when macOS changes it.
Light and Dark override the system for WinMuxX. Wallpaper and decorative tint do
not select the theme of expanded surfaces. The compact rail can still adapt to
its wallpaper to meet the menu bar. Explicit themes override that adaptation.
Custom solid surface colors retain a contrasting foreground. Reduce Transparency
and Increase Contrast continue to apply in every theme.

## Dimming inactive windows

```toml
[dimming]
inactive-windows = 0.25 # 0 (off, the default) to 0.8
```

Everything except the focused window is darkened by this much, on every display.
Clicks still reach the dimmed windows, and dimming steps aside for Mission Control,
native fullscreen and presentation. The `no-peek` command goes further: it darkens
and blurs everything but the focused window until you turn it off.

## Mode leaders and external state

Binding modes support optional `timeout-ms = 1500`, `show-indicator = true`, and
`indicator-color = '#5E9EFF'` in `[mode.<name>]`. Defaults are no timeout and no
indicator. `main` never times out or displays a badge. The timeout starts at entry
and restarts after accepted bindings finish. Unbound keys pass through and do not
reset it. Set `exit-on-unbound-key = true` to return to `main` when an unassigned
key is pressed, passing that key through to the focused app. This is opt-in and
ignored in `main`. Modifier-only taps do not exit the mode. Configure `esc = 'mode main'` explicitly; append `'mode main'` to a
binding's command array for one-shot use. Re-entering a mode starts a fresh session.

The existing icon gains the mode color; the workspace indicator gains ` | L` for
Leader. The tooltip/accessibility label gives its full name. Custom colors are
adjusted for native menu-bar contrast. No extra overlay window or countdown runs.
Shortcut recording suspends the deadline and badge; resuming starts a fresh interval.

Read public state with `winmuxx state --json` or follow changes with
`winmuxx subscribe state-changed`. See [the versioned state contract](STATE_API.md)
for fields and hook variables, plus the optional SketchyBar adapter at
`script/examples/sketchybar_state.py`. Create `winmux.workspace` and `winmux.mode`
items in SketchyBar, then run one adapter instance; stop/restart it with your bar.
No SketchyBar dependency or adapter is started by WinMuxX itself.

### Settings saves and mode controls

Shortcuts → Binding modes exposes each configured mode's inactivity timeout,
indicator toggle and color, and whether an unassigned key exits the mode. Add mode creates a named mode with Escape to return to
main. Add its entry shortcut in Configuration; existing shortcuts are preserved.
The main mode's timeout and mode badge remain disabled.

Ordinary Settings controls save automatically. Text fields save after a short pause
(650 ms) or when leaving the field/page. Numeric fields commit on Return or when
editing ends; toggles, pickers and recorded shortcuts apply directly. Invalid edits stay visible for correction. Failed writes retain
the draft and provide Retry. Opening or reloading a page does not save its values.
Existing rule and display-assignment edits also autosave; creating or deleting
entries remains an explicit action. The complete TOML editor in Configuration
keeps Validate and Save and apply, including stale-file conflict protection.

## Workspace-wide arrangement

Set `layout` in a workspace section to `dwindle`, `master` or `scrolling`. This chooses how the workspace's existing top-level groups are arranged; it does not flatten nested splits or tab groups. Master arranges one selected group beside a stack of the others. Scrolling arranges groups in horizontal columns.

After using Master or Scrolling, switching back to Dwindle retains those group boundaries, including across restarts. Master selection follows the group when other groups are inserted or removed. Keyboard resizing adjusts nested splits first; when there is no matching split inside the focused group, resizing along the Master axis adjusts the workspace divider. Its proportion is saved with the workspace.

```toml
[scrolling]
column-width = 0.49
width-presets = [0.25, 0.3333, 0.5, 0.6667, 0.75, 1.0]
gesture-enabled = true
gesture-sensitivity = 1.0
minimap-enabled = true
center-focused-column = 'never'   # never, on-overflow or always
minimap-hold-modifiers = []       # e.g. ['ctrl', 'alt']

[workspace.'Code']
layout = 'scrolling'
```

Option plus a three-finger horizontal swipe pans a scrolling workspace. Plain three-finger swipes continue to switch workspaces. `scrolling-width next|previous|full` changes the focused column width, and `scrolling-center` centres it. The clickable minimap appears while navigating. Scrolled-out columns leave a 25-point edge preview; previews at display walls stay within their owning display.

A fitting strip is centered. An overflowing strip clamps at both ends; explicit centering respects those bounds. Focus and minimap selection reveal the selected column with the smallest necessary movement. The minimap appears on the workspace's display. Its tiles preserve the column proportions with one scale for both width and height, and show app icons, window titles and tab/split markers. Short strips are centered rather than stretched across the panel. The preview height can grow for narrow columns to retain 32-point click targets without distorting their shapes. A dashed outline tracks the visible area; the accent border marks the focused group. Click a group to focus and reveal it. The map stays visible during panning or while hovered, then fades after 1.5 seconds of inactivity.

`center-focused-column` decides where the strip goes when focus lands on a column: `never` scrolls only as far as needed to show it, `on-overflow` centres it when it would otherwise be partly off screen, and `always` centres it. It applies to keyboard focus, minimap clicks and settling swipes.

`scrolling-focus 1-9|first|last` focuses a column by its place on the strip, with 9 the last column as with browser tabs; `scrolling-move 1-9|first|last` moves the focused column there. A horizontal `move` pops a window out of a stacked column to the left or right, and `stack-with` or `join-with` pulls it into a neighbouring one.

`scrolling-pin left|right` pins the focused column to that screen edge at full height while the rest of the strip scrolls in the space beside it; the same command unpins it. The pinned column keeps its width preset, leaves the strip and the minimap, and blocks edge previews on its side. Pins last until unpinned or the column leaves the workspace, and are saved with the workspace's layout (native desktops included), so they return after a restart.

With `minimap-hold-modifiers` set, holding exactly those keys keeps the minimap up over a focused scrolling workspace, and releasing them lets it fade. Dragging a minimap tile sideways reorders the strip's columns; a click still focuses the column.

Run `scrolling-minimap toggle` (the argument is optional) or choose **Layout → Show Scrolling Minimap** to keep it open without a gesture. Use Left/Right to select, Return to activate, and Escape to dismiss. Narrow columns retain at least 32-point targets; the map scrolls horizontally when needed. Fresh configurations bind Control–Option–M; existing configurations can assign it in Settings → Shortcuts or add a binding:

```toml
[mode.main.binding]
alt-ctrl-m = 'scrolling-minimap'
```

WinMuxX adapts the scrolling-strip geometry described by [Dinky](https://github.com/mikker/Dinky); see [Dinky's MIT license](licenses/Dinky-MIT.txt).
