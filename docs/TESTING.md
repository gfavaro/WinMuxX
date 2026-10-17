# Testing

Run `make check` before submitting a change. It runs the Swift suite, Python
release checks, and dependency lockfile validation. It captures the full Swift output in
`.build/test-output.log`; CI uploads that log even when a test fails. The pipeline
preserves Swift's exit status, so logging cannot turn a failure into a pass.

SwiftPM currently [does not produce XCTest xUnit reports in serial mode](https://github.com/swiftlang/swift-package-manager/issues/9961).
Keep the complete log rather than uploading a misleading empty report or enabling
parallel execution solely to obtain XML.

## Choose the appropriate test

- Test pure policy and geometry with deterministic inputs and observable results.
- Test command behavior through parsing and execution when command routing matters.
  Also assert that unrelated displays and workspaces remain unchanged.
- Keep native rendering and filesystem integration tests identifiable. The
  `WorkspaceSwipeRenderingTest` uses offscreen Metal rendering, with no desktop
  capture or interaction. It explicitly skips when Metal is unavailable; rendering
  failures on supported hardware fail the test.
- Use isolated manual validation for physical trackpad feel, native Spaces
  conflicts, real application Accessibility behavior, permission changes, and
  display hot-plugging. Mocked monitors and rendered curves do not prove those
  behaviors work on the desktop.

For a bug fix, reproduce the user's sequence and confirm the regression test fails
against the old behavior before fixing it. Assert the expected result and relevant
invariants, rather than reproducing the implementation's calculations in the test.
Include cancellation, boundaries, and rejection paths where they change behavior.
Avoid assertion-count or coverage-percentage goals that encourage redundant tests.

## Isolation and cleanup

Workspace/configuration state belongs to WinMuxRuntime. New focused tests can
construct independent owners and bind them with `withValue`, including across
suspension. The broader suite still uses process-scoped native registries, UI
singletons and refresh/persistence adapters, so `make check` passes `--no-parallel`
explicitly. Main-actor isolation alone does not isolate tests across suspension.

New tests using the workspace world should inherit `WorkspaceTestCase`, which
pairs `setUpWorkspacesForTests()` in setup and teardown even when a test throws.
Pure helper tests should continue using XCTestCase without a workspace fixture.
The fixture replaces the runtime as a unit (configuration, monitor caches/overrides,
focus/history/holds, hotkey state, recovery and workspace registry), then resets the
remaining process-level test adapters, including scheduled refresh overrides. Tests that install their own fixture must clean it up
in teardown as well. Register cleanup with `defer` or `addTeardownBlock` immediately
after acquiring temporary files, global overrides, windows, watchers or tasks.
Do not rely on the next test to clean up. Never use real user configuration files
as writable fixtures; use unique temporary directories or isolated defaults suites.

## Asynchronous and timing tests

Coordinate callbacks with XCTest expectations and a finite timeout. Do not use
unbounded `Task.yield` loops or checked continuations as the test's only completion
signal. Release continuation gates and cancel tasks during cleanup, including when
an assertion fails. A deliberately cancellable delay that models an in-flight
operation is different from sleeping and assuming an operation has finished.

Prefer injected time, explicit events, and operation counts to wall-clock speed
assertions. Render animations at chosen timestamps. Keep optional latency benchmarks
separate from correctness requirements, and report environment-sensitive timings
as measurements rather than universal pass/fail limits.

## Review and verification

Run focused tests while editing, then the complete `make check`. Investigate failures
instead of retrying until green or broadening tolerances without evidence. Check
test discovery and explicit skips in the output. A zero-test filtered run is not
validation. Run additional isolation/order checks when shared fixtures change.

The current suite does not certify physical gesture feel or all third-party app
behavior. Record manual checks separately from automated results. Changes confined
to tests and CI do not require rebuilding or restarting the installed app.

References: Apple's [test setup and teardown](https://developer.apple.com/documentation/xctest/set-up-and-tear-down-state-in-your-tests)
and [asynchronous tests and expectations](https://developer.apple.com/documentation/xctest/asynchronous-tests-and-expectations).

## Swipe controller regression boundary

`WorkspaceSwipeController` accepts internal `WorkspaceSwipeDependencies`; its live
factory connects native services. Controller tests inject a preview spy, monitor
lookup, pointer, eligibility and direction, and a controlled navigation session.
They feed real recognizer frames and use the actual workspace selection policy.
They do not start the raw input backend, capture the desktop, or require permissions.

Use `WorkspaceNavigationFixture` for the controller and monitor-navigation tests.
Pair construction in setup with `cleanUp()` in teardown. Reset controllers and
release navigation gates before destroying the fixture. Session gates deliberately
allow cancelled native work to return, so stale success and error paths are tested.
All waits have bounded XCTest expectations; no timing sleeps are used.

## Validation snapshot — 2026-10-16

The controller isolation refactor passed `make check`: 992 Swift tests and 11 Python
tests, with no XCTest skips. This local run used Swift 6.4; CI's pinned Swift 6.2.4
was not executed locally. Refresh, layout-write, and title-read operation counts
matched the pre-refactor baseline:

| Scenario | Work performed |
| --- | --- |
| 10 focus changes / 10 app activations | 0 full refreshes, 0 normalizations |
| 10 window creations | 10 full refreshes, 10 normalizations |
| 10 safe / unsafe command iterations | 0 / 10 scheduled refreshes |
| 10 layout iterations, 6 windows | 60 frame writes for each event scenario |
| Cold title read / 10 steady updates, 20 windows | 20 / 20 title reads |

Live build 67 diagnostics before installation reported 24 warm preview submissions,
p50 34.9 ms and p95 46.0 ms. This is below the required sample count of 30 and above
the reference-machine target of p95 <=16.7 ms. The last warm gesture reported main
preparation and submission 54.4 ms, with worker pending/cancelled. Main preparation
includes synchronous outgoing capture and panel setup; these results do not isolate
which operation dominates. The refactor makes no latency improvement claim.

After installation, collect at least 30 warm physical gestures and separate cold
rapid-release cases. Record main preparation, submission, and worker durations
separately. Do not add overlapping durations together or treat submission as
pixel presentation. Physical feel, display hot-plug, permission transitions, and
native Spaces conflicts require separate manual checks; unit tests do not certify
them. Permission changes must use an isolated test setup, not the user's live setup.

Signed build 68 was installed with the persistent local signing identity. CLI
startup diagnostics confirmed the raw backend listening and Accessibility/screen
capture permissions granted. Workspace-to-display assignments, visible workspaces,
and the focused window were restored and compared with the pre-install snapshot.
A rollback archive of build 67 was retained. The 30-swipe run and manual hot-plug,
permission-transition, and gesture-feel checks remain pending.

### Hidden-window drift regression

A live failure on build 68 showed Safari assigned to internal workspace `1` at
native AX position `(48, 43)`, while workspace `6` (sidebar slot 4) was selected.
This was a live window from a hidden workspace, not evidence of a cached overlay.
A workspace round trip re-parked Safari at `(1709, 1060)` and restored the original
workspace and focus.

The parking fast path now confirms the position through the existing WindowServer
bounds API before skipping an AX write. If native geometry is unavailable or no
longer matches the parking point, it falls back to parking the window. For left
parking, the same native observation supplies the width, avoiding an extra AX size
read on the fast path. `WorkspaceWindowRevealTest` covers the observed Safari frame,
confirmed parking, rounding tolerance, and partial position mismatch. `make check`
passed 993 Swift tests and 11 Python tests; nine benchmark operation-count scenarios
matched the preceding baseline. Those benchmarks do not measure the added native
bounds query's latency. Cache expiration changes were left out of this fix.

Signed build 69 was installed and verified. Four live CLI round trips between
workspace 1 and internal workspace 6 (sidebar slot 4) observed Safari at `(46, 40)`
when selected and `(1709, 1060)` after hiding, on every round trip. The main
workspace and focused window were restored; the external display retained its
empty selected slot (whose internal name was regenerated on startup). These are
native-frame checks, not physical-swipe feel validation.

### AeroSpork adaptations

`make check` after the adaptations passed 1,023 Swift tests and 11 Python tests.
Coverage includes controlled registration retries/PID reuse, native-state unknowns
and invalidations, workspace moves during native reads, MRU preservation, owned rule
completion/destruction/coalescing, popup checks, accepted/ignored/clamped/failed AX
writes, config conflicts/backups/symlinks/permissions, bounded framing and real local
Network.framework receive timeout/cancellation. The termination subprocess tests
exercise both ordinary cleanup and a deliberately blocked main queue; they caught
and prevented an actor-inferred background signal callback before installation.

Nine benchmark operation-count scenarios matched the pre-adaptation baseline.
These tests do not establish a desktop speedup or physical gesture feel. The local
toolchain was Swift 6.4; the separate pinned CI toolchain was not executed locally.
See [Reliability](RELIABILITY.md) for the production behavior and interface details.

A controlled nested-detection regression failed before the join guard was added:
a committed callback waited for another committed operation. Nested duplicate
requests now leave work to its existing owner; ordinary refresh callers still join
and await completion. This prevents self-joins and callback wait cycles without
replaying rules.

Signed build 71 is installed with the persistent local signing identity. Runtime
checks confirmed Accessibility and screen-capture grants, raw touch backend startup,
state/backup mode `0600`, case-insensitive UUID focus targeting and rejection of a
missing UUID. Two native CLI workspace round trips revealed Safari at `(46, 40)`
and parked it at `(1709, 1060)`; the external viewport and all six windows' workspace
ownership stayed unchanged, and the original focused window ID was restored. Empty
automatic workspace internal names can regenerate at startup; the selected external
slot was restored using its existing sidebar position. Focus comparisons use IDs,
not Ghostty's changing terminal title. The archived build-69 CLI also successfully
queried the build-71 server, verifying unchanged framing compatibility.

Rollback archives were retained. Physical swipe feel/latency, real display hot-plug,
permission transitions and a deliberately hung real app still require isolated
manual validation; production apps were not paused to simulate those failures.

### Dependency and toolchain simplification

The app dependency graph now contains five external packages. ISSoundAdditions
was replaced with the narrow CoreAudio volume boundary; the unused experimental
shell parser is excluded from AppBundle, removing ANTLR from the app graph without
changing production command parsing. `make check` passed 1,026 Swift tests and
13 Python tests. Volume policy tests cover steps, clamping, mute thresholds,
toggle behavior and best-effort failures without changing system audio.

The repository pin is Swift 6.4.0; local Apple Swift 6.4 is accepted as the same
release number. Version-gate tests cover matching release forms, different minor
and patch versions, unrecognized output and prerelease suffixes. SwiftPM checks
now require the resolved versions before tests. The release build passes the
selected compiler to Xcode explicitly. Remote CI and physical audio-device
compatibility remain separate validation; local checks do not certify either.

Signed build 72 was built and installed with the persistent identity. Release
symbol inspection found no ANTLR or ISSoundAdditions symbols. CLI diagnostics
confirmed valid config, both required permissions and the listening touch backend.
All six windows retained workspace ownership; populated-workspace display
ownership/visibility and focused window ID were restored and compared with the
pre-install snapshot. The external viewport remained empty; its automatic internal
workspace name regenerated from 4 to 5 during restart. A build-71 rollback ZIP
was retained. No system volume was changed as part of validation.

### Displays, rules and cleanup

`make check` passed 1,044 Swift tests and 13 Python tests. Eighteen focused Settings
tests cover explicit moves across four displays, focus after Bring Here, preservation
of unrelated display viewports, stale confirmation rejection, disconnected targets,
hardware selector validation/ambiguity, saved secondary assignment conflicts,
quote-aware rule boundaries, custom commands/comments, external changes, reordering,
invalid regex, retained invalid drafts, unsaved rule creation and string escaping.
No tests changed the user's configuration file.

The unused-code audit rebuilt app/test/executable indexes in
`/private/tmp/winmux-settings-audit-build`. Periphery 3.6.0 scanned that index;
`/private/tmp/winmux-settings-fresh-unused.json` confirmed the candidates selected
for removal, with no stale ANTLR entries. Whole-repository references were also
checked. Framework callbacks and uncertain scanner findings were retained.
The marketing product is included in the build checks after pruning private views.

The shared config transaction path now accepts narrow document transforms as well
as scalar edits. Tests exercise pure transforms and existing store validation;
they do not certify visual layout, NSOpenPanel interaction, physical hot-plug or
remote CI. Those checks remain separate from local automated results.

Signed build 73 was installed after the final changes and full-suite run. The
Release app and CLI built successfully using the same selected Swift compiler;
the installed bundle passed strict signature verification. A build-72 rollback
archive was retained. Native CLI checks confirmed unchanged ownership for all six
windows, populated-workspace monitor assignment/visibility, original focused
window ID and the empty external viewport. The snapshot was captured immediately
before installation, preserving the user's then-current Safari/workspace-1 focus.
The empty external automatic workspace regenerated its internal name on restart.
Live hardware selector checks rejected both zero IDs and a valid but nonexistent
identity without retargeting a display. Diagnostics reported valid config, granted
permissions and a listening raw-touch backend. Visual Settings interaction,
physical hot-plug, actual hardware-identity targeting and remote CI were not tested.

### Settings presentation refinement

`make check` passed 1,055 Swift tests and 13 Python tests. Ten focused refinement
tests cover stable navigation identifiers and fallback, shortcut search and row
identity, raw workspace IDs behind labels, read-only assignment editing, unavailable
selector arrays, external assignment conflicts, advanced validation, rule summaries
and retained drafts. Existing four-display movement and rule-preservation tests
remain in the suite.

An additional AppKit/SwiftUI integration test renders only our own rule-editor
component in isolated offscreen test windows. It verifies that Add, Save, Revert
and Configuration editor buttons have accessible labels and remain inside the
component at compact and wide widths. After the full suite, the same focused test
also passed with a shorter compact viewport: 500×360, 500×650 and 900×650 points.
Native bitmap previews are written to the temporary WinMuxX-settings-previews
directory. They omit some native button-cell painting, so they support geometry
inspection rather than complete appearance certification. No desktop or installed
application screenshots are taken. Live keyboard interaction, full native visual
review and remote CI remain separate checks.

Signed build 74 was built and installed with the persistent signing identity and
passed strict signature verification. A build-73 rollback archive was retained.
Fresh pre/post-install CLI snapshots confirmed all six windows' workspace
ownership, populated-workspace display assignment/visibility, original focus and
the empty external viewport. The empty automatic workspace's internal name changed
on restart. Diagnostics reported a valid configuration, granted Accessibility and
screen-capture permissions, and the listening raw-touch backend. The user's config
was not edited to validate the new UI. Live appearance/keyboard review and remote
CI were not performed.

### Settings ownership and test isolation

`make check` passed 1,061 Swift tests and 13 Python tests after the ownership
refactor. Scalar/document edits, shortcuts and the raw editor now submit to one
model-owned queue. Structured and shortcut saves share progress/failure/retry
handling; raw editing retains its separate baseline and local error behavior.
TOML editing was moved out of the UI orchestration file without changing its
transformations. Unused automation draft state and redundant file helpers were
removed, and guarded document editing no longer force-unwraps header metadata.

Six controlled tests cover queue ordering across a suspended reload, failure
followed by success, isolated model/draft instances, preserving newer drafts on
retry, retrying the latest shortcut assignments, committed saves after submitter
cancellation, and releasing a failed model despite its retry action. They use
injected in-memory edits/reloads and bounded expectations; no user files are
written. The raw-editor ordering is represented by a queue operation, not a claim
that its running UI was exercised.

The recent Settings editor/refinement/rendering tests and configuration-reference
tests now inherit a paired workspace setup/teardown fixture. The rendering test
uses a fresh Settings model instead of the application singleton. This improves
cleanup and local model isolation; it does not isolate the global workspace world
or justify enabling parallel execution. At build 75, broad runtime ownership debt
was unchanged; the following build addresses it. No desktop performance improvement
was claimed.

Signed build 75 was built and installed with strict signature verification. The
build-74 rollback archive was retained. Pre/post-install CLI snapshots matched all
six window assignments, populated-workspace monitor ownership and visibility,
the original focused window ID and the empty secondary viewport. Diagnostics
reported a valid config, granted permissions and a listening touch backend. User
configuration bytes were not changed to exercise saves; production Settings UI
interaction and remote CI remain unverified. After the complete suite, the six
queue tests also passed again following a test-only weak-binding warning cleanup.


## Runtime ownership cleanup (build 76)

The full scope and acceptance criteria are tracked in
[RUNTIME_STATE_CLEANUP_PLAN.md](RUNTIME_STATE_CLEANUP_PLAN.md). Workspace/project /
viewport state, configuration/reload lifecycle, requested focus and history, native
focus holds, hotkeys, monitor caches and recovery state now share one runtime owner.
Legacy fixtures replace that owner; obsolete field-by-field reset functions were
removed. Config reload publishes the value and source URL before dependent observers
run. Reload, watcher, recovery, focus and hotkey deferred work retains its originating
runtime binding. This remains a serial suite because native/UI/refresh adapters
still have process lifetimes.

Twelve new regression tests cover independent registries with overlapping IDs,
nested bindings restored after errors and suspension, a delayed child surviving
replacement of the legacy fixture without writing into it, fresh focus/history/holds,
monitor overrides, notification-driven cache invalidation and observer lifetime,
frame normalization above/below main, mode/sequence isolation, valid/invalid/dry-run
reload isolation, independent reload gates, recovery snapshot isolation and runtime
release. Twenty repeated monitor reads use one provider read per cache; a screen
notification invalidates main/list/sorted caches together. These are operation-count
checks, not desktop latency measurements.

`make check` passed **1,073 Swift tests and 13 Python tests**, including existing
workspace navigation, explicit display movement, restoration, Settings save,
swipe lifecycle and operation-count regressions.

Signed build 76 was built and installed with strict signature verification; build
75 was archived for rollback. Live CLI selection of workspaces 1 and 2 kept the
Samsung viewport unchanged. Final snapshots matched all six window associations,
populated-workspace monitor ownership and visibility, and the empty secondary
viewport. The original focus window was restored using the existing command after
restart/navigation. The empty secondary's generated raw name changed 5 to 4, and
the initial snapshot preceded completed display discovery; final diagnostics reported
both displays. User config bytes were unchanged. Diagnostics reported valid config,
granted permissions and a listening raw-touch backend. No swipe latency improvement,
manual UI/gesture/hotplug validation or remote CI result is inferred.


## Swipe preparation performance (build 77)

See [SWIPE_PERFORMANCE.md](SWIPE_PERFORMANCE.md) for before/after surface timings,
the live build-76 baseline, stage definitions and the outstanding physical run.
Outgoing screen capture now uses the same bounded actor worker as incoming rendering.
Cancellation before capture completes must prevent both cache publication and a late
overlay. Warm incoming previews remain available once the fresh outgoing image is
ready. Input updates received during capture must apply when the panel appears.

The native surface is reused after ordinary cancellation. Cancellation orders it
out, clears layer contents, removes animations and resets transforms. Full
invalidation closes/releases it. Tests inspect only their own offscreen panel and
synthetic images; they neither capture the desktop nor inject system gestures.
The renderer's existing empty-workspace test verifies it runs off the main thread.
No timing threshold gates CI; a 31-gesture operation test asserts one surface
creation and reports 30 subsequent synthetic samples. Separate tests cover geometry
changes, pixel/animation cleanup, capture failures, invalidation, and release during
capture for both commit and cancel. The full check passed 1,078 Swift + 13 Python
tests. Signed build 77 passed signature and live state checks. Physical submission
p95, feel and display hotplug checks are still pending.


Build 77 physical follow-up recorded 23 warm submissions in the last-32 history:
p50 35.9 ms and p95 47.6 ms. The final attempt was unsubmitted (capture pending or
canceled), with main setup 0.8 ms. This is not evidence of meeting the 16.7 ms goal.
Signed build 78 adds aggregate stage percentiles and a bounded 128-attempt history,
with separate cold submission and not-submitted counts. It passed all 1,078 Swift
and 13 Python tests and settled signature/live state checks. A new 30-completed-warm
physical run is still pending; do not silently count attempts as successful previews.


## Empty rule-list editor regression (build 79)

The user config contained `on-window-detected = []`, but the Rules model treated
any existing key without array-table blocks as an unsupported custom shape. A new
regression first reproduced the warning and inability to add a draft on the old
code. Empty arrays now load as an empty list. The first save removes just that
assignment using the existing quote-aware edit helper and appends the new rule.

Five tests cover empty and quoted/multiline arrays, unsaved draft/revert behavior,
comment/unrelated-setting preservation, nonempty inline-rule protection, concurrent
rule additions and the real model/save-queue path with injected in-memory access.
No real user config is written by the tests. The full local check passed **1,083
Swift tests and 20 Python tests**. Signed build 79 was installed and its signature
verified. Before/after snapshots confirmed identical config bytes, window/workspace
assignments, populated workspace display/visibility state and restored focus.
Only the built-in display was connected at this check. Doctor reported valid
configuration, granted Accessibility/Screen Capture permissions and a listening
raw-touch backend. Native Settings interaction remains manually unverified; the
injected model/save-queue regression covers the first-rule save path.


## Dinky 0.19 adoption (build 80)

The final `make check` passed **1,102 Swift tests and 20 Python tests**, including
19 new regressions. The comparison, decisions, configuration examples and limits
are recorded in [DINKY_019_ADOPTION.md](DINKY_019_ADOPTION.md).

The new tests cover Hyper/Meh duplicate detection and modifier-side filtering,
case-insensitive bundle-ID rules and editor round trips, configured and empty
exec environments, settled/coalesced topology hooks with scoped display counts,
layout inheritance and display ownership, retained explicit command failures,
disabled drag cleanup, legacy minimum evidence migration and single-retry AX
recovery. Thirty navigations through the live session boundary schedule zero
redundant post-refreshes; an interrupted native creation refresh still runs.
These are operation-count assertions, not physical gesture latency measurements.

Signed build 80 installed successfully. Strict/deep signature verification,
config byte equality, window/workspace assignments, populated workspace display
ownership/visibility and restored focus all passed. Doctor reported valid config,
granted Accessibility/Screen Capture and a listening raw-touch backend. Only the
built-in display was connected during installation validation. The bundled CLI
alias resolved in a clean shell environment and queried the running server.
Native Settings, Slack reopen, Terminal rounding and physical docking/swipe
validation remain manual checks; no such result is claimed by the automated suite.


## Nonfatal window diagnostics and scoped AX recovery (build 81)

The Helium sign-in capture exposed an AX read failure while recording. Recording
ran inside focus/detection/refresh paths and propagated capture failures, so a
subsequent workspace/CLI command could fail before its body ran. Clearing the
recorder by restarting restored ordinary window queries. The event trace recorded
workspace/focus changes but no valid sign-in window snapshot; its floating state
therefore was not confirmed by this capture.

Diagnostic captures now retain a per-window failure entry without blocking normal
commands or repeatedly retrying on every refresh. Cancellation still propagates
and leaves the entry available for a later capture. Stale AX recovery now matches
the exact target element by non-retaining object identity: a dead child button or
application element no longer invalidates an otherwise valid window. Real target
failures still refetch once. AX errors report their native numeric code.

Four new regressions cover unrelated element failures, target replacement,
recording failure followed by successful workspace navigation, and cancellation
followed by a successful capture. `make check` passed **1,106 Swift + 20 Python
tests**. Signed build 81 was installed and strict/deep verification passed. Config
bytes, window/workspace assignments, populated display/visibility state and focus
matched before/after installation.

A live check successfully started recording, captured Helium window 23773,
switched to its workspace and back, restored original focus and stopped recording.
All commands returned success. Helium's ordinary browser window classified as a
regular window; no sign-in popup was open during this post-fix check. Doctor
reported valid configuration, granted permissions and a listening raw-touch
backend. Post-check window assignments/config were unchanged. A new sign-in
capture is still required to verify that specific popup; no browser classification
change or user configuration rule was added.

## Runtime efficiency and TOML ownership (builds 82–83)

The runtime changes and native measurement limits are recorded in
[RUNTIME_EFFICIENCY.md](RUNTIME_EFFICIENCY.md). The full local check passed **1,131
Swift tests and 20 Python tests**. Two focused Thread Sanitizer regressions passed
for cancellation and persistence-worker ordering. The steady six-window layout
benchmark now requires six frame writes over ten layouts; geometry-triggered
reassertion still requires sixty.

Seven TOML lifetime regressions cover root release, nested document views, literal
and encoded temporaries, independent removed copies, value-array ownership,
repeated parse/release and date-time/error buffers. An isolated optimized fixture
repeated 1,000 parse/read/format/encode/error cycles against the original pinned
TOMLKit sources and the local ownership patch. `leaks --atExit` reported 173,000
leaks / 10,864,000 bytes before and zero leaks after. The patched fixture also
passed Address Sanitizer with no reports. It only uses synthetic documents.

Build 82 preserved configuration bytes, window/workspace assignments, populated
display/visibility state and restored focus across installation. Uninstrumented
100-query runs measured CLI p50 41.72 → 20.79 ms and zero app writes after the
query fast path, versus 720,896 logical bytes in build 81. These are single local
runs including CLI process launch. Both builds were quiet when settled; there is
no measured battery-life claim. Native interaction and external-display/hotplug
checks remain pending because computer-use access was denied and only the built-in
display was connected.

Signed build 83 includes the vendored TOML ownership patch and is installed with
the same designated signing requirement. Strict/deep verification and unchanged
configuration checks passed. The session locked during installation, leaving AX
window enumeration empty. After unlock, the five window/workspace assignments,
populated display ownership, focus and configuration bytes matched the pre-install
snapshot without corrective window moves.

Extended validation includes a 100,000-cycle optimized TOML fixture (zero detected
leaks and a passing Address Sanitizer run), 1,000 live CLI queries over 127 seconds,
and a 1,000-cycle offscreen preview regression that checks panel/controller release
across 20 lifetimes. Before/after live scans reported the same six allocations /
432 bytes at identical addresses, with `NSMutableDictionary` roots. The earlier
locked-process display-link report was absent. Allocation origins remain
unconfirmed. The query workload overlapped other desktop/test activity, so its
modest footprint variation and writes cannot be attributed to queries alone.
Another 500 queries succeeded. A final 30-second settled sample recorded zero
logical/disk writes, unchanged 72.24 MiB footprint and 0.00047% CPU of one core.
