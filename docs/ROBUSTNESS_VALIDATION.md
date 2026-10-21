# Robustness validation protocol

## Ownership and settled boundaries

Workspace IDs identify model objects inside one runtime. Names are a separate lookup
index. `preferredMonitorPoint` is a placement preference, not permanent display
ownership. An active viewport selects a workspace; explicit moves replace display
slots, ordinary selection preserves current assignment. Secondary displays retain
one visible slot, while hidden workspaces return to the main display preference.

Run `modelInvariantViolations` only after a completed model operation or refresh.
It reads model fields without AX, WindowServer enumeration, scheduling, or repair.
Normal Release refreshes never call it. `debug-windows --check-model` explicitly
requests a scan of the currently settled MainActor model. It checks both registry
indexes, project membership, active references/uniqueness, tree parent links,
repeated object identities and repeated window IDs. Native bound windows must be
reachable. Tests can additionally supply the exact expected live objects.

Fullscreen and hidden-app containers belong to their workspace; minimized and
popup containers are independent roots. Floating windows are workspace children.
Detached closing windows are intentionally excluded. Frozen focus/history may
refer to a removed window: LiveFocus's existing fallback policy resolves it.
The checker does not delete or reject those historical references. An empty
persistent workspace is valid. Disconnected display history is not an active
ownership error; topology reconciliation owns its retirement.

| Rule or overlap | Existing coverage and additions |
| --- | --- |
| IDs, names, projects, viewport uniqueness | WorkspaceNamingTest, WorkspaceNamingTestMonitorAssignment, ModelInvariantCheckerTest |
| Tiled/floating/special-container ownership | RuntimeLifecycleStressTest, ModelInvariantCheckerTest |
| Focus fallback/history | WorkspaceTransitionTest, RefreshFocusSyncTest |
| Switch/explicit move with suspended native result | OverlappingRuntimeEventsTest |
| Disconnect/reconnect, reorder, negative coordinates | OverlappingRuntimeEventsTest, WinMuxRuntimeTest |
| Last tile close with floating survivor; cancelled native result | OverlappingRuntimeEventsTest |
| Valid/invalid reload with queued refresh | OverlappingRuntimeEventsTest, WinMuxRuntimeTest |
| Disable/shutdown invalidation and replacement isolation | OverlappingRuntimeEventsTest, RefreshCoordinatorOwnershipTest |
| Rapid switches and stale observations | OverlappingRuntimeEventsTest (fixed seed `0x574D2026`) |
| Animation target closure/cancellation | WorkspaceSwipeControllerTest, WorkspaceSwipePreviewPhaseTest, WorkspaceSwipeSnapshotsTest |
| Retired overview/tab/palette helpers | WorkspaceOverviewTest, WindowTabsTestTabStrip, RuntimePerformanceScenarioTest |
| Unchanged layout AX-write budget | AxRefreshBenchmarkTest, PostCommandRefreshBenchmarkTest |

The overlap fixtures suspend native readers/refresh overrides with continuations,
then explicitly release them. They use no timing-dependent sleeps. A settled-boundary
failure prints its seed and ordered actions. These fixtures do not establish native
animation smoothness or the absence of visual glitches.

## Explicit event history

`winmuxx debug-windows --events-start` clears and starts runtime-local recording.
`--events-export` writes a private atomic JSON export and prints its path.
`--events-stop` stops recording and releases retained records. Each flag is a separate
command; bare `debug-windows` retains its original AX diagnostic behavior.

The circular buffer retains at most 2,048 events and 1 MiB of event payload,
including per-event separators. Overflow drops oldest events and counts drops.
Events contain monotonic observation time/source, refresh generation, a typed kind,
available window/workspace/viewport IDs, cancellation/stale-result reason, and
already available intended/observed frame snapshots. Export adds a runtime session ID, source build
hash, SHA-256 of config bytes and display rectangles. It contains no configuration
contents, window titles, arbitrary error text, keystrokes, images or native objects.
No additional native observations or recurring tasks are created. Recording is off
by default; disabled calls return before constructing or encoding an event.

This initial vocabulary records refresh request/coalescing/completion/cancellation,
workspace activation, cached native frame observations/authoritative writes and
rejected native cache observations. It does not claim a
complete frame-by-frame AX or drag trace. `debug-windows` remains the tool for AX
attribute detail. Export failures report through CLI and leave the buffer intact.

## Reproducible local native run

Keep artifacts in ignored `.build/robustness/` or `.release/`. Use the existing
`script/profile_runtime.py` and `script/compare_runtime_profiles.py`; do not compare
processes of different topology, configuration, workload or lifetime as equivalent.
The sampler now reports resident memory separately from physical footprint, plus
an all-sample footprint trend in MiB/minute. Neither metric certifies leak freedom.

1. Record build/hash, `sw_vers`, `list-monitors --json`, config SHA-256, managed app
   and window counts, process lifetime, and whether user activity is uncontrolled.
2. Warm up 30 seconds. Sample an idle phase for 30–120 seconds at one-second intervals.
3. On an available desktop, perform 20 workspace switches between two existing
   slots without moving windows, 20 palette open/close cycles, 20 overview show/hide
   cycles, and 20 existing tab selections. Record exact commands and phase times.
4. Take a sample after each group of five cycles, then an idle recovery sample of
   the same duration. Compare trends across groups, not only peak memory. Inventory
   native helper windows with the existing native/window diagnostic workflow.
5. Query assignments and config hash again. Restore only test-owned edits. Do not
   replay old focus if the user has changed it. Report opened/closed windows separately.
6. Repeat an equivalent run three times before establishing environment-specific
   variance and regression limits. Retain raw samples; do not infer battery savings
   or WindowServer costs from WinMuxX counters. Record unavailable AX-write counters.

The existing comparison script's guard bands are screening heuristics, not measured
universal CPU/RSS limits. A single short run cannot establish regression thresholds.
Model CI assertions remain deterministic: write counts, bounded queues/caches,
monitor balance, helper retirement and object release.

## Manual multi-display and helper checklist

- Launch an application after a workspace switch; rapid repeated switches.
- Close the last tiled window while floating windows remain; close an animation target.
- Drag between displays; unplug/replug the secondary; reorder displays with negative coordinates.
- Sleep/wake with native work pending; disable and re-enable management.
- Inspect intent overlay, cursor proxy and resize shells in System/Light/Dark.
- Change Reduce Transparency and Increase Contrast; inspect glass and custom solid color.
- Verify restored assignments/config after each test, recording actual topology and user focus changes.

Physical unplug/replug, sleep/wake, pointer drag and accessibility-setting changes
require a controlled desktop. Mark unperformed checks explicitly; resolver/model
coverage does not substitute for native material inspection.
