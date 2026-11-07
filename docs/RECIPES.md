# Recipes

Examples use WinMuxX's TOML names and commands. Back up your config before editing;
Settings → Configuration validates before applying changes.

## Keep one window centered on an ultrawide

In Settings → Windows choose the single-window ratio and alignment, or set:

```toml
single-window-aspect-ratio = 1.5
single-window-alignment = 'center'
```

Set the ratio to `0` to disable this behavior. See the
[full explanation](../README.md#single-window-on-ultrawide).

## Choose a layout for a workspace on a display

Workspace layout policy changes how a workspace is arranged when its display
changes. It does not move the workspace. Add this root-level configuration:

```toml
[workspace.Code]
layout = 'master'

[workspace.Code.display.'Built-in']
layout = 'tab-group'
```

Replace `Code` and `Built-in` with the workspace's internal name and a display
selector that matches your setup. Remove the two tables to undo the policy.
The [display rules guide](SETTINGS_DISPLAYS_AND_RULES.md) explains selectors.

## Stop following one app when it activates

```toml
[follow-app-activation]
enabled = true
exclude-apps = ['com.example.Utility']
```

Replace the example bundle ID with the app's actual ID. Set `enabled = false` to
disable following for every app, or remove its ID to restore the default behavior.
A floating window on a hidden workspace is not followed: activating its app brings
it to the current workspace. One shown on another display is focused there.

## Use one side of a modifier

```toml
[modifiers]
alt = 'left'
```

This lets right Option type characters while WinMuxX bindings use left Option.
Values are `both`, `left` and `right`. Remove the setting to use both sides.

## Run a command after a display change

```toml
on-display-changed = 'exec-and-forget echo "$WINMUX_PREV_DISPLAYS -> $WINMUX_DISPLAYS"'
```

The hook receives display counts after a settled topology change. `exec-and-forget`
puts the bundled `winmuxx` CLI on PATH. Remove the root key to undo the hook.
See [the 0.19 adoption notes](archive/DINKY_019_ADOPTION.md#configuration).

## Send an app to a workspace only when it launches

```toml
[[on-window-detected]]
if.app-id = 'net.imput.helium'
if.app-has-other-windows = false
run = 'move-node-to-workspace 5'
```

The rule moves only the window an app opens when it launches, while WinMuxX manages
no other window of it. Windows the app opens later, such as login or dialog windows,
open on the current workspace, next to the app, instead of following the rule.
Settings › Window rules offers this as **App windows › Only the app's first window**.

