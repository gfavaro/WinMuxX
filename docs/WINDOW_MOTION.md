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

All moving windows share a display-refresh clock (macOS 14+), with a finite
60 Hz compatibility clock on macOS 13. Intermediate writes use whole points
and skip duplicate frames. A stalled refresh advances by at most 1/30 second;
a finite safety deadline lands windows if a display stops delivering frames.

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
