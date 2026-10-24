# Swipe preview performance

## Current motion changes

Horizontal preview travel now follows normalized gesture progress directly: halfway
progress displays halfway travel. Tracking updates layer transforms without restarting
an easing animation. Release springs use device sample timestamp deltas and start at
the visible position. Recognition and commit thresholds are unchanged.

Overview dismissal clears session images, cards, selection and callbacks while retaining
one native panel and hosting view per display. Reopening refreshes model and geometry;
runtime invalidation and display topology changes release the retained surfaces.
Capture remains asynchronous and does not gate overview panel movement.

`doctor` includes bounded (128 per stage) callback-to-update, overview setup-to-submission,
swipe release-to-layout-ready and ordinary selection-to-layout-ready timings. Callback
receipt uses the app's monotonic clock; private device timestamps are used only for
velocity deltas. Horizontal callback-to-update includes updates during capture preparation,
so it does not imply that a panel was visible. Layout readiness marks successful layout
completion, not WindowServer presentation. No physical latency improvement is claimed
without a new installed-build measurement.

## Historical capture optimization scope and acceptance

This pass addresses main-thread capture stalls, repeated native surface allocation,
and the lack of separate timing for capture and panel preparation. Keep workspace
navigation, short-swipe thresholds, resistance, spring curves and explicit display
ownership unchanged. Do not add background polling or a second capture queue.

1. Record the existing live diagnostics and an offscreen surface-only baseline.
2. Reuse one panel/layer tree across gestures; ordinary cancellation must hide it,
   release image contents and remove animations. Full invalidation closes it.
3. Run outgoing screen capture through the existing actor renderer and bounded
   coordinator (one active job plus one replaceable pending job). Keep immutable
   request values, generation checks and destination/permission revalidation.
4. Record main setup, request preparation, outgoing capture, capture readiness,
   panel preparation, submission and incoming worker timing separately.
5. Verify cancellation before capture, invalid/failed captures, progress accumulated
   during capture, late results, surface cleanup/resizing, and off-main execution.
   Run full checks, build/install signed release and compare live state.
6. Collect at least 30 warm physical gestures in the installed build. Report cold
   and warm separately. Compare time-to-submission, not only main setup. Unit tests
   and offscreen surface timings cannot establish input-to-presentation latency.

## Baselines and interpretation

Build 76 live diagnostics, read before installation of this change:
17 warm submissions, p50 **30.9 ms**, p95 **43.3 ms**; most recent main/submission
**18.1 ms**, incoming worker **71.0 ms**. The sample count is below 30, and these
are historical gestures retained by that running process, not a new controlled run.
The earlier build-67 sample was 24 warm submissions with p95 46.0 ms. Neither is
proof that the <=16.7 ms target has been met.

The surface-only test creates synthetic images and offscreen app-owned windows;
it never captures the desktop or drives native gestures. It excludes the initial
surface and measures 30 subsequent preparations, with no timing pass/fail threshold:

| Local run | Surface creations (31 gestures) | Panel p50 | Panel p95 |
| --- | ---: | ---: | ---: |
| Before reuse | 31 | 0.992 ms | 4.458 ms |
| First run after reuse | 1 | 0.163 ms | 1.055 ms |
| Subsequent targeted run | 1 | 0.089 ms | 0.187 ms |

Timing varies with process warmup and machine load. The robust regression assertion
is one surface creation, with cleared pixels/animations on cancellation. The numeric
samples demonstrate a local surface-path improvement, not an equivalent reduction
in physical swipe latency.

Outgoing capture now runs on the renderer actor, so it no longer synchronously
blocks input handling. Its cost still contributes to submission latency. A warm
incoming image is shown once outgoing capture completes, while fresh incoming
composition proceeds. Releasing before outgoing readiness skips the visual preview
and follows the existing workspace commit/cancel decision. No late overlay may open.

`doctor` initially exposed the latest stage timings and warm submission p50/p95 for
the last 32 gestures. Build 78 expands the bounded history to 128 and reports warm
stage percentiles, cold submissions, and the number of unsubmitted attempts. `captureReady` includes queue wait and scheduling; `capture` is actual
worker capture duration. `panel` is UI preparation and ordering. `mainSetup` excludes
later asynchronous UI preparation. These intervals overlap; do not add them together.
Submission is ordering the panel, not a measurement of pixels presented by the GPU.

## Validation

Five new tests cover repeated surface reuse, cleanup/resizing/invalidation, async
outgoing capture with progress retention, release before capture in both directions,
and failed/invalid capture. The existing native renderer test also verifies it is
not executing on the main thread, without taking a desktop capture.

`make check`: **1,078 Swift + 13 Python tests passed**. Signed release build 77 was
built, installed and strictly verified. Build 76 is archived at
`.release/WinMuxX-before-swipe-build77.zip`. Post-install CLI snapshots matched all
six window associations, populated-workspace display ownership/visibility and the
empty secondary viewport. Focus was restored with the existing command. User config
bytes were unchanged. Diagnostics report valid config, both displays, granted
permissions and a listening raw-touch backend.

The user performed the requested roughly 35 normal three-finger gestures in build
77. The backend recorded 1,536 frames and three fingers. Within the last-32 history,
23 warm previews submitted: **35.9 ms p50, 47.6 ms p95**. The most recent gesture was
released before outgoing capture finished; its main setup was 0.8 ms and no panel
submitted. This does not demonstrate improved total submission latency, and remains
above the target. It also does not establish a controlled regression against the
17-sample build-76 historical baseline. The frame/sample counts are different metrics.

Because an aborted final gesture hides useful per-stage detail in the old report,
build 78 adds aggregate stage percentiles and a larger bounded sample window before
further optimization. Signed build 78 was built, installed and strictly verified;
its settled post-install state matched six window associations, populated viewport
ownership/visibility, empty secondary display and restored focus. The first focus
snapshot preceded native focus settling; the final bounded check matched. User config
bytes were unchanged. Build 77 is archived at
`.release/WinMuxX-before-stage-build78.zip`. The diagnostic-only change passed all
1,078 Swift + 13 Python tests. At least 30 completed warm submissions are still needed.
Do not report the <=16.7 ms target as achieved without that measurement.

Logs: `/private/tmp/winmux-swipe-surface-before.log`,
`/private/tmp/winmux-swipe-surface-after.log`,
`/private/tmp/winmux-swipe-live-baseline76.log`,
`/private/tmp/winmux-swipe-physical77.log`,
`/private/tmp/winmux-swipe-perf-targeted.log`,
`/private/tmp/winmux-swipe-perf-check.log`.
