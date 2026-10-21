# Runtime release validation

This checklist tracks evidence rather than assigning a confidence percentage.
Signed build 106 is installed without allocation-stack or transition tracing.
All 48 CLI help paths pass with the server stopped. The full check passes
**1,243 Swift tests and 26 Python checks**.

Build 106 separates the opening strip from exit tolerance. Auto-hide previously
started dwell across collapsed-width plus 20 pt (64 pt with the current config)
and could expand within 11 pt. It now requires the outermost 2 pt, independent of
rail width, with no hidden-state exit tolerance. The whole strip qualifies for
opening. Revealed content retains its exit margin; zero-width collapse returns
to the narrow target even before the expanded flag clears. Compact rails and
external window-drag rail previews retain their configured width/depth behavior.
The 400 ms delay and text-selection guard remain. Narrow-target regressions failed
before the fix; geometry tests cover both edges and offset/negative display origins.
Native command opening/Escape and numeric sidebar order passed. Physical hover
feel/latency was not measured. The known restart display/focus change recurred;
original workspace ownership and focus were restored, with configuration and all
window assignments preserved. Evidence: `.local/validation/sidebar-edge-build106/`.

Build 105 adds `workspace-sidebar.hover-open-delay-ms` (400 ms by default,
0–5000 ms) and the Settings → Sidebar → Hover reveal delay picker. The hover cue
and expansion wait for dwell; exit, delay reload, explicit opening and retirement
cancel pending work. Generation checks reject stale completions. Left-button
presses begun outside a collapsed sidebar suppress reveal, pointer interception
and edge trapping during selection; recognized window/sidebar drags retain their
existing path. Mouse-up starts a fresh dwell through existing event monitors,
including a stationary pointer. No new periodic source was introduced.

The offscreen hover-controller regression fails against the old path and now
passes; config bounds/defaults and selection/click/drop policy are covered.
Native command opening/Escape and numeric sidebar order passed. The live Settings
control was not verified: SystemUIServer access was not approved, and the app's
Window-menu route closes its implicit Settings scene while openRequestId is zero.
Physical text selection/hover timing remains unverified. Configuration and window
assignments were preserved. The known restart-monitor issue recurred; workspace 5
was explicitly returned to its original external display, removing the empty
replacement. Final monitor ownership matches the pre-install snapshot. Model focus
changed during the check; the most recent window was restored instead of forcing
the older pre-install focus. Evidence: `.local/validation/sidebar-hover-build105/`.

Build 104 addresses the live ordering path missed by build 103. Removing an empty
workspace clears restored display indices for the project's surviving automatic
workspaces. Labels then allocate live indices, reserving explicit numeric names,
but the old sorter skipped automatic workspaces without restored indices. The
regression reproduces the reported **1,3,4,2,5** sidebar after that removal.
Presentation now uses the same live allocation as labels. Empty-slot retention
uses restoration order, independently of live numbering, preventing circular
visibility/ordering dependencies. Custom-named slots and window ownership remain
unchanged. The lifecycle regressions (with and without the five-workspace minimum) and
existing minimum-retention tests pass. Native inspection confirmed the old
1,3,4,2,5 order, then 1,2,3,4,5 after an empty replacement was removed in build 104.
Window assignments and configuration were preserved. The separate restart display
ownership issue recurred: workspace 5 moved to main and an empty external slot
appeared. Its original external ownership was explicitly restored; the empty
replacement was pruned. The final monitor ownership matches the pre-install state.
The attempted CLI-created transient slot was reconciled before the following
query, so its intermediate existence was not certified by that script.
Evidence: `.local/validation/sidebar-order-build104/`.

Build 103 fixed explicit numeric names among restored numbered slots. Its native
check showed 1,2,3,4,5,6 immediately after restarting, but the subsequent user report
and build 104 regression disproved that the fix survived workspace removal.
That check also observed an unattributed display ownership/focus change across
restart; no corrective display move was made. Historical evidence:
`.local/validation/sidebar-order-build103/`.

Build 102 replaces the palette's plain text field and custom result stack with a
native search field and standard selectable list. It uses system semantic colors
and a single system glass/material surface, retaining opaque custom chrome.
Overview exposes selected workspace/window accessibility state, adaptive captions
and stronger contrast outlines. Composition/modified shortcuts yield to native
editing. Its static capture budget and gesture renderer are unchanged.
Native checks verified filtering, clear, arrow selection across group headers,
Return activation, flat/grouped reopening, and overview arrow/Tab selection with
selected accessibility rows/buttons. Command-number routing and composition were
covered by tests; desktop activity interrupted the native quick-select attempt.
Physical input-method switching and a full VoiceOver session were not performed.
Configuration, monitor ownership and surviving window assignments were preserved;
one Windows App window closed and user focus changed during the checks. Evidence:
`.local/validation/native-controls-build102/`.

Build 101 releases palette items/icon references on dismissal and retires obsolete
sidebar monitor panels, including their observers, input resources and hosting
subtrees. The new palette/registry regressions failed before the fixes; focused
tests now verify weak-reference release, recreation without replacing active
panels, resource cancellation and rejection of late reopening. Installed native
checks exercised palette filtering/reopening, sidebar search/navigation/collapse,
and overview presentation/dismissal. All eight window assignments, monitor
assignments, original focus, configuration and signing requirement were preserved.
Physical display hot-plugging was not performed for this change. Evidence:
`.local/validation/ui-resource-cleanup-build101/`.

Build 100's native stack-toggle checks passed from the master, stack, and an
explicit target window. Empty-stack recreation preserves both accordion style
and the 60/40 master split. `layout dwindle` still leaves master mode. The check
restored configuration, all current window assignments, monitor assignments and
focus. Evidence: `.local/validation/master-stack-build100/`.

The following broader recovery, PiP and resource observations are from build 98.

Native checks passed for master 60/40 layout, swap preserving focus, keyboard
resize, leaving master mode, original-frame restore on disable, manual Safari
size preservation across repeated disable, native Safari PiP across workspace
selection, and clean quit/restart. All five current assignments, original focus,
configuration SHA-256 and signing requirement were preserved. The disposable
browser tab/PiP session was closed, returning Safari to its original 12 tabs.
Direct-launch journal ownership now uses a stable kernel birth-time fallback.

Build 98’s 60.001-second sample averaged **0.0122% of one CPU core**, with a
**58.44 MiB** final footprint (58.55 MiB peak, +0.33 MiB during the sample),
11 package-idle wakeups and 114 interrupt wakeups. A subsequent native `leaks`
scan found **0 leaks / 0 leaked bytes**. These bounded process observations do
not certify long-session memory growth, battery life or compositor energy use.
Evidence: `.local/validation/dinky-020-build98/`; feature/configuration details:
[Dinky 0.20 adaptations](DINKY_020_ADOPTION.md).

Earlier capture, gesture and parking reports retain their original build numbers.
The feature changes remain local and uncommitted.

| Check | Current evidence | Status |
| --- | --- | --- |
| CLI build 106 | All 48 help paths, registry completeness, successful bare invocation, invalid-command failure, persistent signing and current assignments | Passed installed CLI without server |
| Automated regression suite | 1,243 Swift tests and 26 Python checks pass | Passed locally |
| Overview animation and dismissal | Build 90: 20 animated and 10 rapid native CLI cycles, zero detected leaks before/after. Build 91: Close completes and restores sidebar | Passed bounded native workload; physical swipe feel pending |
| Hidden native window recovery | Coalesced native events, completed-parking eligibility, focus-safe placement pass, and refresh-priority tests | Passed regression tests; reported Safari flash not reproduced |
| Native TOML ownership | 100,000 optimized cycles, zero detected leaks; Address Sanitizer passes | Passed fixture |
| Overview lifetime | 1,000 synthetic controller sessions, weak-reference teardown, 20 native offscreen panel lifetimes | Passed fixture |
| Overview resource bounds | Static capture counts, cancellation holding the shared capture slot, 12-card pages, 32 MiB aggregate image cap, 640 × 360 thumbnails | Passed fixture |
| Restart geometry | Saved unit frames, rejection of parking strips, backward-compatible decoding, current visible geometry | Passed tests and native build 86 restart: all 7 saved frames preserved; floating reveal matches saved position/size |
| Model lifecycle | 32 windows over 40 rounds: 5,120 fullscreen/minimize transitions and 160 close/replacements | Passed fixture |
| Fixture isolation | Reset releases minimized/popup roots that previously survived between cases | Fixed and regression tested |
| Native overview interactions | Build 84: keyboard and exact window selection, minimized/fullscreen exclusion, Escape/Close, sidebar restoration, 50 CLI cycles | Passed on built-in display |
| Parking clamp retry, build 88 | Existing build 87 trace: 115 attempts / AX position writes in 90 seconds (85 after the first 10 seconds). Build 88: 20 no-op refresh commands plus 20 quiet seconds, zero parking attempts or AX position writes. Assignments/config preserved; tracing disabled afterward | Retry fixed; visual flash association unconfirmed |
| Native build 86 navigation/state | Exact floating-window selection and Escape passed; all 7 assignments, original focus/workspace, config and signing requirement preserved | Passed on built-in display |
| Native capture allocations | Build 84: growing CGRect dictionaries traced to the legacy capture proxy. Build 85: zero detected leaks after 5 and 20 additional populated cycles. Build 86: zero before and after 20 cycles held open 2 seconds each | Measured bounded workload |
| Normal build 86 process counters | 30.00-second interval after native validation: 76.67 → 76.56 MiB, peak 76.67 MiB, 0.00074% of one core, no sampling gaps | Short interval; includes final read-only verification at start |
| Two-hour app observation | Build 83 observation interrupted by update after 97.23 minutes; 73.44 → 80.74 MiB, peak 93.81 MiB, 0.0422% of one core | Incomplete |
| Physical three-finger gesture, display hotplug, sleep/wake | Physical down-swipe confirmation pending. Two displays now connected; built-in overview ownership inspected. Hotplug and sleep/wake untested | Pending |
| Matched system energy comparison | `powermetrics` needs administrator access; noninteractive sudo refused; WindowServer rusage returned EPERM | Unmeasured |

## Capture leak attribution

Allocation stacks in build 84 led from the overview's renderer through
`SLWindowListCreateImage` / `SLSWindowListCreateImageProxying` to
`CGRectCreateDictionaryRepresentation` and leaked mutable dictionaries on macOS
27.2. An instrumented fresh process showed zero leaks before the workload and
64 allocations / 5,632 bytes after five cycles. Panel/hosting/render-only probes
did not reproduce these allocations.

On macOS 14+, the overview now uses ScreenCaptureKit single-frame screenshots.
Failed captures retain placeholders without falling back to the legacy API.
Other existing capture consumers and the macOS 13 fallback still use the older
API. Zero detected leaks in the measured builds 85/86 workloads does not certify every
application path. The older build 83 six-allocation / 432-byte report was not
individually attributed.

## Process observations and limits

`script/profile_runtime.py` reads macOS `proc_pid_rusage` without Accessibility
queries, window interaction, configuration changes or a sleep assertion. It checks
process identity and records completion, interruption and sampling gaps. CPU
percentages are fractions of one core. These counters do not establish watts,
WindowServer energy, battery life or long-term leak freedom.

The earlier long run is preserved at
`.local/validation/runtime-soak-20261017T181251Z/summary.json` with interrupted
status and 5,833.62 seconds of coverage. Do not describe it as a completed two-hour
observation. The early footprint rise and later activity were not a controlled
idle workload.

Before broader release, validate physical gestures, multi-display ownership and
hotplug, sleep/wake, rapid native Mission Control interruption, macOS 13 capture,
and matched app/WindowServer energy traces. Passing synthetic tests does not
replace those desktop checks. Native overview implementation and resource policy
are documented in [Workspace overview](WORKSPACE_OVERVIEW.md).

The build 87 installation checksum check observed one concurrently added
`single-window-aspect-ratio` setting. Removing that single added line reproduces
the exact pre-install checksum; the existing configuration content was preserved.
The setting was left intact.

## Gesture and parked-window follow-up (build 91)

Downward three-finger dismissal is available whenever overview is open, including
when opened by command with the upward shortcut disabled. Overview presentation
uses the horizontal workspace swipe spring and configured duration, respecting
animation disabling and Reduce Motion. Dedicated gesture components own routing,
source demand, recognition, and bounded touch delivery. Closing retains at most
one frozen image group until animation completion; reopening retires it first.

Native geometry subscriptions now follow all managed windows. A coalesced,
event-driven repair checks already-parked inactive normal windows against native
bounds and requests placement without adopting native focus or switching the
workspace. Unknown fullscreen/minimized state and incomplete parking defer to
normal reconciliation. No polling timer was added. The initial build 90 startup
repair notices prompted this stricter eligibility in build 91; those notices do
not establish the cause of the user's Safari flash.

Computer-use approval denied access to System Settings, so competing system
trackpad gesture mappings were not verified or changed. Automated native cycles
cannot establish physical gesture feel or certify that the intermittent flash
has disappeared.

The user reported another Safari flash after build 91. A four-minute recovery-log
lookback contained zero repair messages; this does not distinguish absent native
notifications from ineligible cached state or a flash without geometry drift.
The added opt-in transition trace records incoming managed-window geometry events,
repair eligibility, parking/fullscreen/minimized state, focus, and native bounds
alongside existing frame-write diagnostics. It reads no window titles and is
inactive unless `WINMUXX_TRACE_WORKSPACE_TRANSITIONS=1`. No additional flash fix
is claimed from this diagnostic change. System Settings access was retried and
again denied by computer-use approval.

## Empty native-state cache repair (build 93)

A 120-second opt-in build 92 trace recorded 399 diagnostic events, including 116
managed native geometry notifications and 18 Safari geometry events with both
cached native flags absent. The trace includes a controlled workspace switch;
there was no visually confirmed spontaneous flash. The build 91 eligibility
rule silently rejected these empty-cache candidates. The controlled check also
hit a CLI workspace-name mismatch; restoring the original window ID restored
Workspace 4. Tracing was disabled afterward.

Build 93 checks native bounds first, then confirms normal native state over AX
only for drifted candidates. Cache absence no longer permanently disables repair.
The observation must match its cache generation and registered window identity;
visibility and native bounds are checked again before repair. State-read failures,
fullscreen/minimized state and unsafe races decline repair. Only one batch reads
at a time; events during a read coalesce into a follow-up batch. Tests cover safe
parking without state reads, rejected native state, workspace visibility changes,
and a 1,000-event burst during an in-flight read. The full suite passes 1,180
Swift tests and 26 Python checks. This addresses an observed recovery gap, not a
conclusive attribution of the intermittent Safari flash.

Computer use also rejected Ghostty access for safety reasons, preventing direct
visual inspection of its panes. No alternative UI tooling was used to bypass it.

Installed build 93 preserves all seven current window assignments and the exact
configuration checksum. The installed CLI passes all 47 help paths with the
server stopped. Normal runtime has tracing and allocation-stack logging disabled.
The native overview opened with Safari assigned to Workspace 1 and Ghostty to
Workspace 4, then returned to the sidebar. It closed before the automation click,
so that observation does not establish which physical gesture dismissed it.

## Captured recurring flash: powered-off external display reconnects

The user reported another flash during a finite, 150-second build 93 trace, with
no trackpad contact. At 01:57:41.620 on 2026-10-18 (UTC−03), WindowServer processed
external display 2 hotplug-out; hotplug-in followed at 01:57:42.843, 1.223 seconds
later. Safari's native bounds changed from parked to `(8, 46, 1702, 1066)` at
01:57:41.886 while Ghostty 26160 stayed focused on internal workspace 6 (sidebar
Workspace 4). Other inactive windows also returned onscreen. Repair requests and
parking writes followed; a second return occurred during reconnection.

Four consecutive disconnects occurred at roughly 70.91-second intervals, each
followed by reconnection about 1.2 seconds later. The user confirmed that the
external monitor was plugged in but switched off. This establishes a captured
flash associated with native display reconfiguration; it does not identify why
the display link cycles, or prove every earlier flash shares this trigger.
No code change or new fix is claimed for this observation. A physical cable
disconnection test was requested to isolate the trigger and is pending.

Private event logs and the correlated timeline are under
`.local/validation/recurring-flash-build93`. The trace ended, build 93 was restored
to normal runtime without diagnostic instrumentation, and all window assignments
were preserved. The remaining physical test cannot be performed through computer
use. Earlier test totals and leak measurements retain their original workloads.

The controlled cable-disconnected check completed after 120.45 seconds with zero
display hotplug events and zero parked-window repair notices. The user confirmed
no flashes during the interval. This supports the powered-off monitor's recurring
connection cycle as the trigger for the captured occurrence. It is a short
isolation check, not proof of lifetime flash freedom. The underlying reason for
the display link cycling remains unestablished. No settings were changed or
additional code installed for this result; build 93 remains in normal runtime.

## Interactive overview animation (build 94)

Upward and downward overview gestures now present progress while fingers move.
The router sends begin/update/end events, including cancellation and bounded
release velocity. Panel layers directly update opacity, scale and vertical
translation; touch frames do not publish SwiftUI model changes, recapture images,
move real windows or start display-link timers. Release settles with the same
spring and configured duration as horizontal workspace navigation. The shared
spring now normalizes velocity for sub-point properties such as opacity/scale.

Cancelling an opening dismisses its provisional session and releases captures;
cancelling a closing settles the same session back open. Motion disabled, zero
duration and Reduce Motion retain release-only actions. Command opening/closing
uses the same rise/zoom/fade. Interaction lifecycle is separated into
`WorkspaceOverviewInteraction.swift`; presentation remains separate from routing.

The complete suite passes 1,187 Swift tests and 26 Python checks. New tests cover
pre-release presentation, partial lifts committing once, reversal/reset, disabled
motion fallback, bounded geometry and velocity, 1,000 progress updates retaining
one model/image budget, cancelled opening cleanup and closing-session reuse.
Build 94 is signed with the existing requirement and installed without tracing;
all assignments and configuration were preserved, and all 47 CLI help paths
passed with the server stopped. Native interaction reports are under
`.local/validation/interactive-overview-build94`. Physical swipe feel is pending
user confirmation; synthetic tests cannot establish that experience.

Installed build 94 native validation completed ten ordinary and ten rapid CLI
open/close cycles. `leaks --fullStacks` reported zero detected leaks before and
after this bounded workload. The overview rendered populated cards and the
panels retired to the sidebar afterward. Assignments and the configuration
checksum remained unchanged. These command cycles do not synthesize touch input
or establish physical swipe feel, battery use or long-term leak freedom.

## Frosted overview and sidebar keyboard navigation (build 95)

The overview backdrop now uses the expanded sidebar's native frosted HUD material
with a light contrast scrim, rather than a near-opaque system fill. There is one
blur surface per display. Reduce Transparency uses an opaque system background;
no per-card material, polling source, or capture stream was added.

The sidebar's existing keyboard/search handling now highlights unfiltered
selection, includes workspace headers as well as windows, seeds the current
workspace, and scrolls selected rows into view. Up/Down moves the selection,
Return activates it, and Escape closes the command-expanded sidebar. Search
results retain their existing window-filtering policy and native text editing.
There is no new global key monitor. Tests cover row order, boundaries, missing
rows, empty lists and focused-workspace seeding. All 1,190 Swift tests and 26
Python checks pass.

Installed build 95 preserves configuration, all current window assignments and
the signing requirement. All 47 installed CLI help paths passed with the server
stopped. Native computer-use checks observed a highlighted Safari row, Down
selecting Workspace 2's header, Up returning to Safari, Return activating window
20018 and collapsing the sidebar, and Escape collapsing a reopened sidebar.
The overview rendered its new native material. Private reports are under
`.local/validation/glass-sidebar-build95`. This does not establish full-system
GPU energy or every accessibility/material configuration.

Build 95 also completed ten ordinary and ten rapid native overview CLI cycles;
`leaks --fullStacks` reported zero detected leaks before and after. Assignments
and the exact configuration checksum stayed unchanged after keyboard and lifetime
checks. The final runtime has no diagnostic instrumentation. This is a bounded
lifecycle check rather than proof of lifetime leak freedom or energy consumption.

## Optional workspace grouping in palette (build 96)

`palette --group-by-workspace` toggles a workspace-grouped palette. Bare `palette`
retains flat results. A Group by workspace toggle switches presentation for the
current opening and returns keyboard focus to search. Groups use the opening
snapshot's workspace order (focused workspace first), retain fuzzy ranking within
each group, omit empty matches, and show workspace display labels/project names.
Display labels and project names are searchable. A linear grouping pass uses the
existing item snapshot; it adds no window enumeration or AX queries.

The flattened result list drives both drawing and selection: headings do not
consume Up/Down, Return or Command-1…9 indices. Tests cover ordering, filtering,
keyboard selection, display-name search, optional flag parsing and flat fallback.
All 1,194 Swift tests and 26 Python checks pass. Build 96 installation preserved
configuration, window assignments and signing. Every installed CLI help path
passed without the server running. Native UI checks verified grouped headings,
the presentation toggle, typing focus/search, Command-2 selecting window 26160
across the headings, bare-command flat default and Escape dismissal. The original
window focus was restored. Evidence: `.local/validation/palette-groups-build96`.

## Dinky 0.21 command separation (build 109)

Reviewed upstream release `v0.21` at `38a2effdcb9d34f4e402a3f69476f39be660a878`.
Workspace mode choices now use `workspace-layout dwindle|master`; old choices in
`layout` fail parsing. Container cycles advance after the last matching state.
Workspace/window queries expose `%{workspace-layout}`, and menu/Settings actions
use the new grammar. Migration details are in `DINKY_021_ADOPTION.md`.

The cycling regression failed against the original implementation before the fix.
The complete `make check` passed 1,255 Swift tests and 26 Python checks. Focused
coverage includes parser/config rejection, nested and explicit window targets,
other-workspace isolation, tab-group preservation, master stack preservation,
three-option and overlapping-description cycles, JSON formatting, and empty,
floating and invalid targets.

Build 109 was signed with the existing local identity, installed, and launched.
The personal Alt+Space binding was migrated to `workspace-layout dwindle`; the
running app reported that exact binding. Config dry-run and reload succeeded,
diagnostics reported valid configuration and granted permissions, and native CLI
queries returned the new workspace layout field. The installed client rejected
`layout dwindle`. All seven managed window IDs and workspace assignments, plus
the focused window, matched before and after restart. A config backup and a ZIP
of build 108 were retained. These checks do not certify physical gesture behavior.
Evidence: `.local/validation/dinky-021-*.log` and the before/after agent snapshots.

## Verified local installer

Use a fresh increasing build number and the existing persistent signing identity.
The installer never changes the personal TOML or macOS preferences:

```sh
python3 script/install_fork.py --dry-run --app .release/WinMuxX.app
python3 script/install_fork.py --install --app .release/WinMuxX.app \
  --report .release/local-install.json
python3 script/install_fork.py --resume .release/local-install.json
```

Preflight verifies both bundles, signing certificate equality, configuration and
permissions. Installation archives the previous bundle outside Applications,
rechecks desktop state, stops the old process, stages the complete new bundle,
verifies its signature and launches it. Startup compares surviving window IDs
and workspace assignments; opened and closed windows are recorded separately.
A failed replacement/startup attempts rollback only while unlocked with unchanged
display topology. The report records rollback failure instead of hiding it.

A locked session remains pending; resume verifies the installed build and current
state without replaying old focus commands. Changed config, topology or surviving
window assignments require review. Reports contain local window IDs and config
paths and are written with owner-only permissions; keep them out of commits.
Explicit rollback is available with `--rollback .release/local-install.json` and
checks the archived bundle against the recorded previous identity and build.
`rolled_back` describes bundle restoration, not full desktop acceptance.

## Reliability changes — build 117 (2026-10-20)

Installed once with `script/install_fork.py`, using the existing local signing
certificate. Release app source identifies commit `4ece6c5a`; subsequent changes
are installer/comparison tooling, tests and this record. The installed bundle
passes strict deep signature verification. The recoverable build-116 archive and
installation report are under `.release/`; the report is
`install-build117.json`. Configuration hash and all seven surviving window IDs
and workspace assignments matched after restart.

Focus changed during startup. The installer skipped focus restoration, reported
review required and then passed read-only resume validation. This exercised the
non-disruptive resume path on the live desktop. Mock tests separately cover
failure rollback; the live installation did not require rollback.

Native screenshots were inspected for the dark palette on Built-in Retina Display
and overview panels on that display and S34CG50. They opened and closed with no
window assignment changes. Screenshots remain outside tracked files because they
contain application content. This is a visual smoke test, not proof of animation
frame pacing or native outside-click/IME delivery. Live light mode, accessibility
setting changes, both sidebar edges and IME were not retested in this delivery;
synthetic appearance/native-control tests cover their deterministic policy.

After a 30-second warm-up, a 120-second idle process sample completed with 121
samples and no sampling gaps: footprint 79.126 → 79.157 MiB, CPU below 0.01% of
one core and 21 package-idle wakeups. This is one short observation. The earlier
build-116 sample used only the built-in display, so the environment-aware
comparison correctly reports **inconclusive**. It does not establish a memory,
energy or battery-life improvement. Evidence is in the ignored directory
`.build/reliability-review/`, including full suite logs, process samples,
environment metadata, comparison output and native window inventories.

## Canonical TOML configuration — build 118 (2026-10-20)

The full check passes **1,286 Swift tests and 47 Python checks**. New coverage
checks sparse persistent names, removal of count-based retention, temporary blank
lifecycle, version-1 migration, quoted/escaped legacy keys, invalid imports,
backup/idempotence, TOML precedence, preference removal and live reload/dry-run
publication. Tab-group borders also passed geometry, movement/resize target,
switching, nested split, native-fallback and 1×/2× rendering regressions.

Build 118 identifies app source `bfac35b3` and is installed with the existing
persistent local signing identity. Strict deep signature verification, CLI
startup, agent query and dry-run config validation passed. All six managed window
IDs and workspace assignments matched the fresh pre-install snapshot.

The startup migration removed the personal config's zero minimum count and
imported its Workspace menu-bar indicator and monochrome icon appearance.
An exact text comparison verified that these were the only file changes; the
persistent names and other settings were preserved. The original TOML is saved
as `winmux.toml.backup.1`. Private copies of the original file and legacy preference
domain are under `.release/` and are not committed. The migrated preference keys
were removed from UserDefaults after the write succeeded.

The installer correctly reported `config_changed`. After comparing the exact
migration and its backup, the report recorded the reviewed before/after hashes;
read-only resume then returned `validated`. The report is
`.release/install-build118.json`. The build-117 app rollback archive is beside it.
Rolling back to build 117 also requires restoring the backed-up TOML and legacy
preferences, because that older app does not understand the new settings.

No new live light-mode, accessibility-mode, IME or pointer-drag validation is
claimed in this delivery. Automated UI policy and lifecycle coverage is described
above. Current configuration semantics are documented in [configuration](CONFIGURATION.md).
