# Shortcuts and launching

Launching apps, modifier sides, the window palette and example scripts.

## Launching apps

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

## Shortcut modifier sides

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

Confirmed application minimum sizes persist across restarts. Settings → Windows
lists each app and its known width and height; unknown axes are shown explicitly.
Forget an app there, or use **Forget All…** to clear saved and current observations. When an explicit resize reaches a
confirmed app minimum, WinMuxX shows a brief nonactivating notice.

## Window search palette

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

## Example launch scripts

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
