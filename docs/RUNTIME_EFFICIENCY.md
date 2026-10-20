# Runtime efficiency

The runtime manages native application windows through Accessibility and private
WindowServer APIs. Model benchmarks exclude some cross-process and compositor costs.

## Persistence and recovery

Routine restart saves capture immutable model state on MainActor. A utility serial
worker encodes JSON and updates the primary/backup files. It holds one active write
and one replaceable pending snapshot, and skips snapshots equal to the last saved
state. Explicit final saves drain the worker synchronously before returning.

Application termination records one window assignment per departing window. Each
assignment contains one frozen leaf, rather than another full workspace tree.
Complete startup trees remain available during the 30-second late restoration
period. Consumed snapshots are compacted after that period or after a layout edit,
once any in-flight restoration readers have finished.

Crash-recovery originals are staged during discovery and flushed as one journal
batch before the first corresponding frame mutation. Recording a batch still
completes synchronously before native writes. Removal of closed-window entries can
coalesce for 50 ms; a subsequent record or clean quit flushes that pending update.

Master layout adds a two-child root and one ordinary stack container. Geometry,
minimum fitting, animation and resize previews reuse the existing tree paths; it
has no polling, capture stream or additional display link. Closed stacks release
their parent references, verified with weak references and 500 insert/close cycles.

Explicit disable and quit share one active original-frame restoration task, with
independent app queues and failure budgets. Completed tasks and closed-window
bookkeeping are released. Successful restores are skipped until management resumes;
failed retries retain their last known frame to protect off-state manual moves.
Automatic layout/frame writes remain suppressed while disabled. Journal ownership
uses a kernel birth-time fallback when LaunchServices omits a direct launch date.

## Native events and input

Mission Control notifications share one pending 16 ms reconciliation. Border IDs
are checked through a set, owning applications are resolved once per scan, and a
required border reconciliation reuses the same native window snapshot. Managed
geometry updates retain the individual-window fast path. No reconciliation clock
runs when there are no events.

Run-loop cancellation reads and writes use the same lock. Fresh AX window elements
receive their timeout before ID resolution, and ID/attribute reads honor the
session budget and job cancellation. The per-app 1.5-second refresh deadline is
cooperative: an already-started native call must finish or time out before its AX
thread can acknowledge cancellation.

Layout reuse compares whole-point native targets, so fractional weight rounding
does not cause repeated identical AX writes. The six-window, ten-layout hotkey
benchmark now requires six writes instead of accepting sixty. Geometry events
still retain their explicit reassertion behavior.

Pointer focus uses cached geometry on the display under the pointer. Unchanged
pointer/scroll events keep the existing dwell task. After dwell, a worker checks
the frontmost native surface so floating or unmanaged windows are not ignored.

## Queries, subscriptions and captures

Read-only CLI list/config/agent-query commands read the established managed model
without triggering layout, UI reconciliation or restart persistence. Requested
native metadata, such as a window title, can still require an AX query. These
queries do not cancel pending native refreshes.

Each subscription has one ordered sender, with limits of 64 buffered events and
1 MiB, including the in-flight event. A client exceeding either limit disconnects;
other clients continue independently. Initial events use the same sender.

Double-sided window captures run on an actor. Only one capture can remain active,
including after cancellation. Preparation falls back to navigation after 80 ms,
and cancelled/late images cannot present an animation. Each retained image is
limited to 2 million pixels and a 2048-pixel longest edge. Native capture can still
temporarily allocate a full-resolution source image before reduction.

Palette dismissal releases indexed window titles, icon references and the selection
callback, while keeping the reusable native panel. Repeated dismissal of an already
hidden palette does not rebuild its hosting view or publish unchanged search state.

Sidebar panels are retained only for the currently resolved monitor scopes. A scope
that disappears is removed from the registry and retired: pending work, input taps,
event monitors and menu observers are cancelled or removed, and its hosting subtree
is cleared before closing. Deferred callbacks cannot reopen a retired panel. A
returning monitor position creates a fresh panel; active scopes reuse their panels.

The palette uses a native search field and a standard selectable SwiftUI list.
Native text editing and marked-text composition precede palette commands. Result
ranking/grouping is computed once per view update and row selection is keyed by
window ID. The palette uses one system glass/material surface; overview retains a
single full-screen native blur. Neither adds polling, capture streams or animation
clocks. System semantic colors, opaque Reduce Transparency fallbacks and increased
contrast outlines replace palette-specific white opacity layers. Existing opaque
custom chrome remains supported. Overview exposes selected workspace/window traits
and accessibility focus without changing the capture budget or gesture renderer.

## Verification

The current local check passed 1,243 Swift tests and 26 Python tests. Earlier, two focused Thread
Sanitizer tests passed for concurrent cancellation and persistence-worker
coalescing/final-save ordering, with no race reports. The strengthened six-window,
ten-layout hotkey benchmark records six frame writes; the geometry-event scenario
continues to record sixty explicit reassertions.

Regression tests cover 500 terminated-window assignments, recovery-reader lifetime,
unchanged-file suppression, worker coalescing and final-save ordering, cancellation,
throwing-session recovery, query isolation, journal batching, native event bursts,
slow subscribers, pointer targeting, capture deadlines and image resolution.

## Native release measurements

Build 82 was signed with the existing local identity and installed over build 81.
Strict/deep verification passed. Configuration bytes, window/workspace assignments,
populated workspace display/visibility state and restored focus matched across
installation. Doctor reported valid configuration, granted Accessibility/Screen
Capture and a listening raw-touch backend. Only the built-in display was connected.

An uninstrumented run of 100 serial `list-windows --all --count` processes measured:

| Metric | Build 81 | Build 82 |
| --- | ---: | ---: |
| CLI p50, including process launch | 41.72 ms | 20.79 ms |
| CLI p95, including process launch | 78.42 ms | 21.58 ms |
| Total elapsed | 4.81 s | 2.09 s |
| WinMux CPU time over all 100 queries | 73.84 ms | 5.31 ms |
| WinMux logical bytes written | 720,896 | 0 |
| WinMux disk bytes written | 557,056 | 0 |

These are single runs on an active desktop, not a controlled latency benchmark.
Counters came from `proc_pid_rusage`; they exclude CLI and WindowServer CPU. The
uninstrumented build-82 run is separate from the run that overlapped Time Profiler.
After queries, a 15-second settling sample wrote zero bytes and its footprint fell
by 0.14 MiB. Both builds were essentially idle when settled: the quiet tail of
build 81 measured 0.00029% of one CPU core; build 82's post-query sample measured
0.00022%. There is no evidence here of a material idle CPU reduction.

Build 82's fresh-process footprint was about 70.6 MiB after the workload versus
81.2 MiB in the longer-lived build 81. Different process lifetimes prevent treating
that difference as a measured memory-growth improvement. Sampling and Time Profiler
captures were collected; the observed desktop workloads were not matched closely
enough for an overall CPU speedup claim.

The live leak scan identified native TOML allocations. The pinned wrapper had no
native-root destruction or temporary-buffer cleanup. The local vendored ownership
patch is covered by seven additional regressions. An isolated optimized fixture
that repeats 1,000 parse/read/format/encode/error cycles reports 173,000 leaks /
10,864,000 bytes with the original pinned sources and zero leaks with the patch.
The same optimized 1,000-cycle fixture passed Address Sanitizer with no reports.
This fixture does not access user configuration or native windows.

Signed build 83 includes the TOML patch and is installed. Its live leak scan no
longer reports native TOML allocations; it reports six allocations / 384 bytes
rooted in an AppKit `_NSDisplayLink` / SwiftUI `ViewGraphDisplayLink` chain.
Allocation stacks are unavailable in this signed process, so their origin remains
unconfirmed. The process is not certified leak-free.

The session locked during installation, so initial AX enumeration was empty.
After unlock, all five window/workspace assignments, populated display ownership,
focus and configuration bytes matched the pre-install snapshot. No corrective
window movement was required for this validation.

## Extended validation

The isolated optimized TOML fixture completed 100,000 parse/read/format/encode/error
cycles with zero detected leaks. The same 100,000 cycles passed Address Sanitizer.
A native offscreen preview regression performs 1,000 begin/update/cancel cycles
across 20 controller lifetimes. Every controller reuses one panel, clears pixels
and animations on cancellation, and releases its panel and controller after
invalidation. It neither captures the desktop nor injects gestures.

The installed build completed 1,000 serial count queries in ten batches, with ten
seconds between batches, over 127 seconds. Settled footprint ranged from 71.24 to
72.00 MiB; the last reading was 0.53 MiB above the first settled reading. Eight
consecutive middle batches recorded zero logical writes. The first and final
batches/settles recorded 638,976 bytes in total, so this mixed desktop run does not
establish zero background I/O. Other diagnostics and offscreen tests overlapped
parts of the run. It is not a controlled query latency or long-duration leak test.

A further 500 count queries succeeded: p50 21.17 ms, p95 21.63 ms, 196,608 logical
bytes written and a 0.17 MiB footprint increase. In a subsequent 30-second settled
observation, footprint stayed at 72.24 MiB, both logical and disk writes were zero,
and app CPU averaged 0.00047% of one core. These short observations distinguish
settled behavior from the mixed workload; they do not establish lifetime bounds.

Before/after unlocked-process leak scans reported the same six allocations / 432
bytes at identical addresses, consisting of three `NSMutableDictionary` roots and
their storage. The earlier locked-process display-link chain was absent. These
reports did not grow during the observed workload; their allocation origin remains
unconfirmed because stack logging was not enabled. The whole app is not certified
leak-free.

Build 83 was compiled before these changes were committed locally and embeds base
hash `5579eaf1`. Its runtime implementation includes the fixes documented here;
subsequent changes add tests, stress-fixture arguments and these measurements.

At the build 83 checkpoint, interactive Mission Control, gesture and occlusion
checks were unverified because computer-use access was denied. Native app access
subsequently worked for overview validation; see the current checklist. Multi-monitor/hotplug tests and
long-running managed-window churn are still pending. `powermetrics` was unavailable
without superuser access; no watts, battery-life or full-system wakeup improvement
is claimed from these process counters or unit tests.

The follow-up [release validation checklist](RELEASE_VALIDATION.md) records the
model lifecycle stress test, fixture isolation fix, two-hour passive observation
and remaining native/energy access limits. The build 83 long observation was
interrupted by an app update after 97.23 minutes; it was not a completed two-hour
result. The checklist also records the overview capture leak attribution and the
ScreenCaptureKit replacement on macOS 14+.


## 2026-10-18: native corner-clamp retry

A brief right-edge flash reported during idle/typing prompted an event-driven
trace of build 87. macOS accepted parking AX requests at `(1709, 1111)` but
kept several native windows at `(1709, 1080)`. Exact-position confirmation and
forced writes after geometry invalidation retried that rejected coordinate.
The 90-second diagnostic recorded 115 parking attempts and accepted AX position
writes, including 85 after excluding the first ten seconds. This is evidence of
redundant writes, not proof that those writes caused the reported flash.

Build 88 accepts a native-confirmed correction of at most 64 points only when
intersection with every connected display remains no more than the existing
one-point parking strip in at least one dimension. Unknown/invalid bounds,
meaningful onscreen drift, large corrections, and visibility on another display
remain unconfirmed and trigger re-parking. Geometry invalidation now uses that
native confirmation instead of forcing a write; startup and wake retain forced
reassertion. No polling or permanent timer was added.

Regression tests cover the observed clamp, actual onscreen drift, excessive
correction, negative display origins, adjacent-display exposure and invalid bounds.
The full suite passes 1,165 Swift tests and 26 Python checks. Installed build 88
reported zero parking attempts and zero AX position writes during twenty no-op
`enable on` refresh commands followed by twenty quiet seconds. This is a different
workload from the original 90-second observation, not a percentage improvement or
battery measurement. All window assignments and config contents were preserved;
the final process runs without tracing. Private reports are in
`.local/validation/parking-clamp-build88` and `.local/validation/flash-investigation`.

The first diagnostic helper failed to reap its child before its relaunch step;
the normal app was restored manually. The final validation restored its normal
runtime successfully. The flash itself was not visually reproduced or conclusively
attributed; continued user observation is still needed.

## Overview gesture and drift recovery follow-up (build 91)

Overview animation shares the horizontal swipe spring/duration and uses finite
Core Animation animations. Capture and session observers stop when dismissal
begins; one frozen image group remains until completion. Reopening first retires
that group. The native raw-touch source is demanded while overview is open even
when the upward shortcut is disabled, and stops when no enabled gesture needs it.
Recognition, routing, delivery, lifecycle and presentation live in dedicated files.

Parked-window geometry events are coalesced before native-bound checks. Only
completed parking on an inactive workspace with known normal native state is
eligible. Actual drift requests a placement-only refresh without native-focus
adoption; already safe parking requests no repair. A 1,000-event regression test
checks coalescing. This path adds no periodic polling or timer.

The full suite passes 1,177 Swift tests and 26 Python checks. Build 90 completed
20 animated plus 10 rapid native overview cycles with zero detected leaks before
and after. Build 91 preserves configuration and all six current assignments,
and native Close restores the sidebar after animation. These bounded checks do
not prove battery improvement or resolution of the intermittent Safari flash.

## Empty-cache recovery correction (build 93)

A subsequent Safari flash prompted a finite build 92 event trace. It captured 18
Safari geometry notifications with absent native-state flags; the prior fast
repair silently excluded empty caches. Controlled workspace switching was part
of this trace, so it does not reproduce or attribute the spontaneous flash.

Native bounds now gate the expensive work: confirmed safe parking never queries
AX. Drifted candidates receive one native fullscreen/minimized observation with
generation and window-identity checks. Failed, stale or unsafe observations do
not repair. Visibility and geometry are checked again after awaiting. Events
during a read are retained in a set and drain in a follow-up batch, with one batch
performing observations at a time. No periodic source was added. Three additional
regression tests cover these paths; 1,180 Swift and 26 Python checks pass.
The finite trace was disabled before the final normal runtime. Resolution of
the intermittent visual flash remains unconfirmed.

## Recurring flash correlated with external display hotplug

A user-timed flash was captured in build 93. WindowServer repeatedly disconnected
and reconnected external display 2 roughly every 70.91 seconds, with each outage
lasting about 1.2 seconds. Native Safari and other inactive-window frames returned
onscreen before WinMuxX's repair writes, while the focused Ghostty/workspace stayed
unchanged. The user reported the external monitor was connected but switched off.
This demonstrates actual geometry changes during native display reconfiguration,
rather than confirming a border or gesture-preview artifact. The reason the
connection cycles is not established. A cable-disconnection check is pending.
The finite trace was disabled and assignments preserved; no battery improvement
or additional software fix is claimed from this observation.

The follow-up 120.45-second check with the powered-off monitor cable disconnected
recorded zero display hotplug events and zero parked-window repairs; the user
reported no flashes. This isolates the observed trigger without adding idle work
or another hiding mechanism. The physical link-cycling cause remains unknown.

## Interactive overview presentation (build 94)

Vertical gesture progress now updates existing panel-layer opacity, scale and
translation directly. It does not mutate SwiftUI models, lay out real windows or
capture new snapshots per touch frame. A committed release carries bounded
velocity into the common spring; reversal/reset cancel provisional opening or
restore an existing closing session. Disabled motion retains release-only actions.
No permanent timer or display-refresh callback was added.

The full suite passes 1,187 Swift and 26 Python checks, including 1,000 progress
updates sharing one controller model/image budget. Installed build 94 completed
ten ordinary and ten rapid native CLI cycles, with zero detected leaks before
and after. Configuration and assignments were preserved. Physical swipe feel
remains separate from these fixtures and command-animation measurements.

### Sidebar hover intent

Hover reveal uses one cancelable, weakly captured dispatch item per panel, with
`workspace-sidebar.hover-open-delay-ms` (400 ms by default, 0–5000 ms). The cue and
expansion wait for dwell. Pointer exit, retirement, explicit opening, and delay
reload cancel pending work; generation checks reject stale completions. Pointer
button transitions reuse the existing observer event path. A press begun outside
a collapsed sidebar suppresses hover, mouse interception and edge cursor trapping
until release, except for recognized window/sidebar drags. Mouse-up permits a new
dwell even with a stationary cursor. No repeating timer or new idle polling source
was added. Tests cover delay parsing, deferred reveal/cancellation and pointer-press
policy; those do not certify physical pointer feel in every application.

Auto-hide uses a two-point opening strip independent of collapsed rail width.
The exit tolerance applies only after content is revealed; a collapse reaching
zero width returns to the two-point strip even if the expanded flag has not yet
cleared. Compact rails retain their full visible hit area and depth threshold.
Idle hidden panel backing also shrinks to the edge strip. External window-drag
rail previews retain the configured rail width. Geometry tests cover both edges,
offset/negative display origins and the distinction between opening and exit.
