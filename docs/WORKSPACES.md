# Workspaces and displays

Persistent workspaces, projects, navigation, multiple monitors and swipes.

## Workspaces to keep

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
count-based creation or retention. See [migration details](CONFIGURATION.md).

Saved restart assignments protect workspaces while startup is rebuilding their
windows. After startup, stale assignments alone cannot retain an empty workspace.
Live minimized and hidden windows still protect their owning workspaces.
After you explicitly select a workspace, apps launched afterward open there
instead of returning to an old saved destination. Windows of apps already running
remain eligible for restart restoration.

## Projects

A project groups its own workspaces. Switch projects in the sidebar to keep
different sets of windows together.

## Workspace navigation

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
The source gets a local fallback or empty workspace; other displays keep their current
workspace. Forced assignments (`workspace-to-monitor-force-assignment`) work as in
AeroSpace: while its display is connected, an assigned workspace shows only there,
selecting it from any display shows it there, and moving it elsewhere is refused.

At launch, display ownership is restored by default, and assignments do not override it. Enable **Settings → General →
Startup → Start workspaces on main display** (`start-workspaces-on-main-monitor = true`)
to start existing workspaces on main instead. Secondary displays receive empty
workspaces. Each secondary display then shows its assigned workspace, if any;
**Automation → After startup**
can run existing `move-workspace-to-monitor` commands for optional startup placement.
The toggle only affects launch, not configuration reloads or normal switching.

## Multiple monitors

All monitors share the project and workspace list. Each display has its own
sidebar and selects its own workspace. Two displays can use the same project,
but each must show a different workspace.

## Workspace swipes

**Settings → Windows → Workspace swipes** enables three-finger
workspace swipes. Workspaces stack like the sidebar: swiping up brings the workspace
below into view and swiping down the one above, sliding vertically. It is off by default:

```toml
[workspace-swipe]
enabled = false
```

When **System Settings → Trackpad → More Gestures → Mission Control** uses three
fingers, macOS recognizes the swipe and WinMuxX acts on it,
so starting, resting thumbs and palms, flicks and taking a swipe back behave exactly
as in macOS. WinMuxX keeps the swipe from the Dock;
past the first or last workspace the swipe does nothing. Over a native full-screen
app, while Mission Control is open or while WinMuxX is not taking swipes, macOS gets
the swipe as usual. Mission Control stays on its keyboard shortcut. In a Scrolling
workspace, three-finger left/right scrolls its strip: the columns follow your fingers,
and on release focus goes to the column nearest the middle (with Swipe between
full-screen apps on three fingers). Elsewhere left/right still switches macOS Spaces. While a
window drag is in progress, the swipe does nothing, so
macOS does not open Mission Control underneath. macOS's own release speed decides a flick: a
quick flick switches after a little travel, and flicking back cancels even past
halfway. Quick swipes chain: a swipe begun while the previous switch is still landing
waits for it, then continues from the workspace it reached. Natural
scrolling sets the direction as it does for scrolling: the content follows your
fingers. An event tap reads macOS's
private Dock swipe events (the approach of InstantSpaceSwitcher and iss); it needs
the Accessibility permission WinMuxX already has.

A short quick flick or a longer drag followed by release switches to the adjacent
workspace; pulling back before release cancels it. Nothing moves during the gesture:
the switch happens on release. Window dragging/resizing blocks it. With Mission
Control on four fingers or off, WinMuxX does not take the swipe.
