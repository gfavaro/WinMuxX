# Configuration

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
