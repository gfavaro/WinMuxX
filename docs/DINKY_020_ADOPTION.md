# Dinky 0.20 adaptations

This document records the 0.20 adoption. Historical command syntax below may
pre-date the 0.21 migration. Current workspace mode choices use
`workspace-layout`; see the [migration guide](DINKY_021_ADOPTION.md) and the
[current layouts guide](LAYOUTS.md).

Reference: [Dinky v0.20](https://github.com/mikker/Dinky/releases/tag/v0.20),
commit `066b531`; source comparison against v0.19. These adaptations keep
WinMuxX's simulated workspaces and existing AppKit/Accessibility model.

## Accessibility and focus

Returned AX child elements use the same one-second messaging timeout as managed
windows, including close/fullscreen controls. Queued focus operations check
cancellation before changing focus and between main-window, raise, and application
activation operations. Disable and termination cancel pending focus jobs.
An AX call already executing still has to return or time out.

Above-normal browser surfaces, including Safari and Helium video overlays, are
classified as popup surfaces rather than tiled document windows. This uses native
window levels, with no title matching or repeated accessibility enumeration.
It deliberately also excludes other above-normal browser utility surfaces.

App activation continues to follow windows across workspaces by default. Opt out
for selected bundle IDs:

```toml
[follow-app-activation]
enabled = true
exclude-apps = ['com.example.utility']
```

`follow-app-activation = false` disables automatic cross-workspace following for
all apps. Focus within the current workspace and explicit WinMuxX navigation
remain available. This setting does not block macOS or other applications from
activating their own windows.

## Disable and quit

Disable restores recorded original frames instead of relaying out every workspace.
Quit uses the same operation. Only windows managed in the current enabled session
participate; a session disabled before management does not move unrelated windows.
Restoration validates process/launch identity, connected-display intersection,
native fullscreen/minimized state, and native geometry across the asynchronous
state read. A position-first AX write is confirmed by readback.

Direct app launches can lack a LaunchServices launch date. Recovery journal ownership
falls back to the kernel process birth time, preserving PID-reuse checks. Staged
original frames are retained if the journal cannot initialize.

Restoration is shared by concurrent disable/quit requests, with independent app
queues and AX failure budgets. A successful restore is not repeated while disabled.
`winmuxx enable off` retries failures; movement since a failed attempt is preserved.
Closed windows release their restore bookkeeping. Failed journal entries survive
quit. If an original frame is unavailable for a parked window, the saved workspace
preview frame, or a bounded visible fallback, keeps recovery possible.

Enabling again discards stale parking/layout caches for windows visible on a
connected display. Configuration reloads while disabled do not migrate layout or
orientation. Automatic layout/frame writes remain suppressed while disabled.

## Master layout

```sh
winmuxx layout master
winmuxx swap-with-master
winmuxx swap-with-master --window-id 123
winmuxx layout dwindle
```

`layout master` makes the focused tiled pane the master. Other panes form a stack.
Tab groups stay atomic. New windows append to the stack unless automatic tab-group
insertion applies. Closing/moving the master promotes the first stack pane; a lone
master fills the available desktop. `swap-with-master` exchanges the target pane
with the master; when the master is selected, it exchanges with the first stack pane.
Focus stays with the selected window.

```toml
[master]
size = 0.6                 # Master share; 0.1 through 0.9
side = 'left'              # left, right, top, bottom
stack-layout = 'tiles'     # tiles or accordion
```

The master root and its stack use ordinary tree nodes, existing minimum-size
fitting, animations, resize previews, and frozen-state persistence. Width/height
resize changes the appropriate split; `balance-sizes` restores the configured
master share. Minimum sizes can override that share. Directional focus, move and
swap use spatial slots, including right/bottom master placement. Within a master
workspace, directional move swaps panes and stops at workspace edges instead of
creating an implicit outer split. Cross-monitor moves retain their existing path.
Configure `master.side` to change master orientation.

In master mode, `layout tiles accordion` toggles only the stack, whether focus is
on the master, a stack window, or a tab in a stack group. `layout tiles` and
`layout accordion` set that stack style directly. The master pane, side, size,
window order and focus stay in place. The choice survives an empty stack and
restart; no empty container is retained just to remember it. An explicit change
to `[master].stack-layout` overrides the manual choice on configuration reload.

`layout dwindle` leaves master mode; `layout master tiles` toggles the workspace
between master and tiles. The root default picker and native Layout menu
include Master. Defaults apply to new workspaces; a workspace policy can opt in:

```toml
[workspace.1]
layout = 'master'
```

These options do not change existing user configuration automatically.

## Efficiency and validation

No timers, polling, screenshot streams or display links were added. Master layout
uses the normal event-driven layout pass. Original-frame recovery runs only on an
explicit disable, recovery or termination path.

Automated regressions cover four-side geometry, stack insertion/promotion,
minimum-size fitting, tab groups, directional navigation, mouse/keyboard resize,
freeze/decode/restore, empty-workspace defaults, released stack containers, and
500 insert/close cycles. Recovery tests cover duplicate requests, retry/manual
movement, unknown geometry, reused identities, and disabled configuration reloads.
Native Safari validation used a local silent video: PiP stayed active when selecting
another workspace, without becoming a managed pane or replacing logical focus.
The disposable tab and PiP window were then closed. Other browser implementations
and hotplug hardware behavior remain separate validation boundaries.

Build 98 passed **1,218 Swift tests and 26 Python checks**, signed installation,
all 48 command help paths with the server stopped, native master/resize checks,
disable/manual-size preservation, and clean quit/restart with five assignments,
original focus and configuration preserved. Evidence is under
`.local/validation/dinky-020-build98/`.

The final 60-second process sample averaged 0.0122% of one CPU core, with a
58.44 MiB final physical footprint (58.55 MiB peak; +0.33 MiB during the sample).
A subsequent native heap scan found zero leaks. These are bounded observations,
not a battery-life estimate or proof against long-session memory growth.
