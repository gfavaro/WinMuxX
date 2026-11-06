# Window motion

Tiled windows glide to their layout positions, including when a newly opened
window makes the existing windows reflow. The default duration is 150 ms.

New windows use the workspace focused at detection time. Their glide starts
inside that workspace's destination monitor, rather than crossing from the
display chosen by the application. Window rules may change the destination.
Existing windows and interrupted animations retain their current departure frame.

```toml
[animations]
enabled = true
duration-ms = 150
```

Set `enabled = false` or `duration-ms = 0` for immediate placement. Durations
from 0 to 2000 ms are accepted. macOS Reduce Motion also disables the effect.

An interrupted layout retargets from the last requested intermediate frame.
Direct frame changes and window destruction cancel pending motion. Entering
Mission Control settles the current tiles before hiding borders. Intermediate
frames do not participate in minimum-size learning. No motion task remains
running after arrival.

Each display with moving windows uses its own display-refresh clock (macOS 14+),
with a finite 60 Hz compatibility clock on macOS 13. Windows follow their
monitor's display UUID while the clock is active. Intermediate writes use whole
points and skip duplicate frames. A stalled refresh advances by at most 1/30
second. Each window has a finite safety deadline; it lands even if its display
stops delivering frames, and new motion cannot postpone an older window's deadline.

Display topology changes cancel in-flight motion. Each existing window snaps on
its first layout after displays settle, including windows on hidden workspaces
when those are next visited. Subsequent layouts glide normally.

This implements the Dinky-style glide behavior using a finite smoothstep curve,
not Dinky's spring simulation. Live AX event ordering, visual smoothness, and
border tracking require runtime validation in addition to unit tests.

Intermediate AX writes avoid frame readback; only the final frame uses the
normal settling/minimum-size path. Geometry notifications from those writes do
not launch a full model refresh unless the mouse is being used. Native geometry
notifications update the moving window's border directly, and notifications from
our own border windows are ignored to avoid refresh feedback.

## Workspace restoration

Windows returning from a parking corner move directly to their destination.
They remain marked as hidden until the destination position is confirmed through
Accessibility. Borders and native focus stay suppressed during that interval.
A failed or cancelled restore retains its saved position for the next refresh.
New parking or restoration requests invalidate older completion callbacks.

Restoration moves the window before resizing it, then reasserts the position once
if the app adjusted it. Display-change snaps retain the normal frame-write order.
This reduces intermediate geometry but does not make Accessibility writes atomic.
Visual improvement must be checked on the running app.

For a short diagnostic run, launch the app executable with
`WINMUXX_TRACE_WORKSPACE_TRANSITIONS=1` in its environment. Logs use subsystem
`com.gfavaro.winmuxx` and category `workspace-transition`. They contain monotonic
timestamps, per-window generation numbers, window/workspace/monitor identities,
and requested and observed frames. They do not record keyboard text or window
titles. Tracing is off by default and adds frame observations only at transition
events; it does not install a polling timer. Quit and launch normally to disable it.

The same flag enables category `workspace-frame-write` for blocking frame writes.
It records each position/size write and any reassertion, the AX acceptance result,
AX geometry and WindowServer geometry before and after each operation. These
additional synchronous observations can affect timing, so a traced recording
locates intermediate geometry but is not a smoothness benchmark.


## Workspace swipe capture timing

`winmuxx doctor` reports cache hits, initial main-thread preparation, time from
request to overlay submission, and background render duration separately. These
operations overlap: do not add their durations or interpret submission as the time
a pixel reaches the display. It also reports p50/p95 warm submission times over the
last 32 gestures. All samples contain scalar timings only, with no polling or disk
images.

Incoming images are composed on a serial actor using immutable IDs and frames.
The pipeline holds one active job and only the newest pending request. Cancellation
is checked between native captures; results from obsolete requests cannot update
the cache or UI. The cache is bounded to four images and 64 MiB of bitmap storage.
Display geometry forms part of its key; configuration/display/sleep resets clear it.

For live validation, warm up by visiting neighboring workspaces, then measure at
least 30 warm swipes, cold first visits and rapid releases. Target warm submission
p95 at or below 16.7 ms on the reference Mac. Verify secondary displays without a
local neighbor remain unchanged. Physical motion/frame pacing still needs manual
inspection; automated rendering tests establish trajectories, not trackpad feel.
