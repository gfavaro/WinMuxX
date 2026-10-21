# WinMuxX robustness implementation plan

Status: implementation and release validation in progress (2026-10-21).

Implementation evidence and the rule-to-test table are in
[ROBUSTNESS_VALIDATION.md](ROBUSTNESS_VALIDATION.md). Baseline `make check`
passed 1,288 Swift and 47 Python tests before runtime edits. A private 30-second
build-120 idle sample is in `.build/robustness/baseline/`: 31 samples, no gaps,
119.032 → 119.064 MiB footprint, 0.00458% of one CPU core, zero logical/disk
writes and zero package-idle wakeups. macOS 27.2 (26B118), built-in Retina only;
9 managed windows were present at the following environment snapshot. The process
was long-lived and user activity was uncontrolled. This is an idle baseline only;
no equivalent active native workload or energy improvement is claimed.

Stages 1–3: read-only structured invariant scan, negative fixtures and controlled
continuation overlaps are implemented. Existing lifecycle/transition/performance
fixtures reuse the scan. First full implementation check passed 1,302 Swift tests;
final checks follow diagnostics/appearance/sampler additions. No demonstrated
runtime management defect required a new transaction architecture.

Stage 4: explicit runtime-local bounded circular event history and private atomic
export are implemented. Original AX `debug-windows` recording remains available.
Stage 5: intent/proxy surfaces and resize layer colors now use shared appearance.
Stage 6: existing profiler adds resident memory and all-sample footprint trend;
the finite native protocol and multi-display checklist are documented. Live physical
hotplug, sleep/wake, pointer helpers and accessibility setting changes are pending,
not passed. Model tests do not certify native rendering or gesture feel.

## Objective

Make existing window management predictable under overlapping native events, easier
to diagnose, and cheaper to validate. Preserve current shortcuts, workspace semantics,
TOML configuration, and idle resource use. This is not a runtime rewrite.

Existing foundations include runtime-scoped state, refresh generations, bounded AX
failure budgets, atomic config writes, model lifecycle stress tests, and native smoke
checks. Extend these instead of introducing parallel systems.

## 1. Establish ownership rules and a baseline

Read `runtime/WinMuxRuntime.swift`, `runtime/RefreshCoordinator.swift`,
`tree/WinMuxWorkspaceState.swift`, `tree/WorkspaceMonitorAssignment.swift`,
`tree/WorkspaceMonitorViewportOrdering.swift`, and their callers under
`Sources/AppBundle`. Read `docs/RELIABILITY.md` and `docs/RUNTIME_EFFICIENCY.md`.

- Map existing tests to each rule before adding coverage.
- Document the distinction between workspace identity, preferred monitor, and active
  viewport. Workspaces remain movable; do not give them permanent monitor ownership.
- Define checks at settled model boundaries: registry/name indexes agree; a managed
  window has exactly one valid owner; active viewport references exist; the same
  workspace is not active on two viewports; each secondary viewport has at most one
  active workspace; focus references are valid under the existing focus policy.
- Account explicitly for minimized, fullscreen, popup, closing, and temporarily
  detached windows. Do not mistake transitional states for corruption or remove
  intentional history references.
- Record the current `make check` result and a reproducible native performance
  baseline before modifying runtime behavior. Record build, macOS, display topology,
  app/window counts, and measurement procedure.

Acceptance: a rule-to-test table and baseline artifact exist. Unknown semantics are
resolved from current code/tests before implementing a checker.

## 2. Add a reusable model invariant checker

Add a runtime-owned, read-only checker returning structured violations. Reuse it in
tests rather than duplicating assertions across suites. Start with
`Sources/AppBundleTests/tree/RuntimeLifecycleStressTest.swift` and
`Sources/AppBundleTests/ui/WorkspaceTransitionTest.swift`.

- The checker must not call AX, enumerate WindowServer, repair state, or schedule work.
- Check both window IDs and object identities, including special containers.
- Validate at documented completed transaction/refresh boundaries, never arbitrary
  suspension points. Keep full scans out of normal Release hot paths; enable them
  explicitly for diagnostics, and use them in tests.
- Add negative tests proving each violation is detected, and valid-state tests for
  minimized/fullscreen windows, empty persistent workspaces, floating windows, and
  monitor reassignment.

Acceptance: all existing scenarios remain valid; deliberately broken fixtures report
specific violations. Disabled checks introduce no scan or recurring task.

## 3. Test overlapping events and fix demonstrated defects

Extend existing scoped-runtime and refresh fixtures. Use controlled continuations or
a deterministic scheduler, not timing-dependent sleeps. Replay fixed seeds and print
the seed plus ordered events on failure.

Cover these sequences with assertions after every settled boundary:

1. Switch workspace while an app launch/native focus observation is pending.
2. Move a window/workspace while an older AX result is pending; deliver that result late.
3. Disconnect/reconnect a secondary display during a transition, including changed
   display order and negative display coordinates.
4. Close the last tiled window while floating windows remain; also close a target
   window during animation and refresh cancellation.
5. Reload valid/invalid config during queued refresh work; preserve the last valid
   runtime configuration on failure.
6. Disable/re-enable management or shut down with pending native work.
7. Repeat rapid switches and tab/overview open-close cycles; verify retired objects
   release and stale completions cannot mutate a replacement runtime/session.

For each discovered bug, first retain a minimal failing regression, then make a
focused fix in the existing owner. Reuse existing generation/identity checks. Do not
introduce a new transaction architecture unless a reproduced failure requires it.

Acceptance: deterministic sequence coverage passes repeatedly, failure output is
replayable, and existing behavior tests pass. Describe model coverage separately from
native behavior; simulated success does not establish absence of visual glitches.

## 4. Add bounded, opt-in event diagnostics

Inspect existing refresh, drag, recovery, and `DebugWindowsCommand.swift` diagnostics
before choosing a shared recorder. Preserve existing `debug-windows` behavior; it
currently captures AX detail, which is a different job from event history.

- Add an explicitly started/stopped in-memory ring buffer owned by the runtime.
  Initial limits: 2,048 events and 1 MiB serialized payload, whichever is reached first.
- Record monotonic time, event kind, runtime/session generation, window/workspace/
  viewport identity, cancellation/stale-result reason, and intended/observed frames
  only where those frames are already available. Include observation time/source.
- Do not add native reads just to log, retain native window objects, capture screen
  images, record keystrokes, or include window titles by default.
- Export only on request, with build/config fingerprint and topology metadata.
  Exclude config contents and redact sensitive text; write private files atomically.
- Disabling or resetting releases retained data. Overflow drops oldest records and
  reports a dropped count. Instrumentation errors must not affect management.

Acceptance: tests cover ordering, bounds, overflow, reset, redaction, cancellation,
and export failures. Disabled recording has no timer, I/O, or payload formatting.

## 5. Complete shared appearance adoption

Audit remaining forced-dark and fixed-white helper visuals, especially
`ui/core/DesignTokens.swift`, `ui/dragproxy/WindowIntentPreviewPalette.swift`,
`WindowDragCursorProxyView.swift`, `WindowDragCursorProxyBackground.swift`, and
`mouse/resize/ResizePreviewPalette.swift` plus its layer consumers.

- Route semantic foreground, background, and contrast decisions through the existing
  `ui/core/ChromeAppearance.swift` resolver. Keep intentional shadows/highlights.
- Preserve the distinction between System/Light/Dark and material/custom color.
- Refresh resolved CGColors when appearance changes; do not freeze dynamic NSColors
  into static layer colors. Reuse the existing config/native appearance lifecycle.
- Test System/Light/Dark, Reduce Transparency, Increase Contrast, and custom color.
  Inspect real drag/resize helpers in both appearances; resolver tests alone cannot
  verify native material rendering.

Acceptance: helper visuals follow shared settings live, remain readable, and add no
per-frame view reconstruction or new observation/polling source.

## 6. Make release validation reproducible

Extend existing benchmarks and scripts rather than adding a second test runner.

- Keep deterministic limits in CI: AX write counts for unchanged layouts, bounded
  queues/caches, retired-object release, and helper-window lifecycle counts.
- Use a finite local native scenario: idle sample, 20 workspace switches, 20
  palette/overview cycles, tab changes, then an idle recovery sample. Track CPU,
  resident memory, owned native windows, and available AX-write counters. Compare
  equivalent topology and app counts with the stage-1 baseline.
- Report memory trends across repeated cycles, not just a single peak. Separate
  WinMuxX memory from WindowServer costs and note unavailable measurements.
- Add a manual multi-display checklist: launch after switching workspace, rapid
  switching, last-window close, drag between displays, unplug/replug, sleep/wake,
  and appearance changes. Restore the user's config and assignments afterward.
- Establish regression thresholds from measured variance; do not invent universal
  CPU/RSS limits or claim battery savings from unit tests.

Acceptance: `make check` passes; native checks have recorded results or explicit
untested limitations; there is no unexplained persistent resource growth or idle
work introduced by this effort.

## Delivery order and completion

Implement stages 1–3 first: this is the highest-value reliability milestone. Then
deliver diagnostics, appearance cleanup, and the completed release checks in that
order. Keep commits reviewable by stage and defect; update this document with actual
results rather than marking planned checks as passed.

At final delivery, run the full checks, build a signed release, install using the
existing installer and rollback/report workflow, verify config and assignments,
and push the work to the repository under the standing delivery instructions.
Distinguish user-driven focus changes from installation failures in reports. Never
replay stale focus merely to satisfy validation. Do not merge without current merge
authorization. Report any remaining native-only uncertainty explicitly.
