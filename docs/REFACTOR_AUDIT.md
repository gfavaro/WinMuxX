# WinMuxX refactoring audit — 2026-11-06

Reviewed against `7824b457` plus the existing uncommitted working tree. This report
records proposed refactors; no production code was changed by this review.

## Scope and evidence

A line-oriented automated scan inspected 689 tracked first-party production/tooling
files (62,545 lines), 219 test files (29,944 lines), and identified four generated
files separately. The newly added SettingsSearch.swift and root build manifests
were also inspected. Vendor code, generated parser output, binary assets and
historical documents are not refactor targets.

**This is not a completed human line-by-line audit of every file.** Detailed source
inspection concentrated on the paths listed in the coverage ledger. A whole-tree
scan finds candidates; it does not establish correctness or substitute for reading
all implementations. Do not describe the scan count as manually reviewed lines.

Priorities below describe refactoring scope/risk, not proven bug severity. Every
recommendation is pending. Existing behavior fixes remain tracked separately in
[the UI review queue](REVIEW_QUEUE.md).

Coverage details: [file and line-range ledger](REFACTOR_AUDIT_COVERAGE.csv).
Detailed inspection covered 10,838 lines across 53 files;
remaining entries are explicitly marked scan-only or inventory-only. These numbers
include test and build-file ranges and must not be interpreted as production-only.

## Joint disposition after Claude review

The [Codex–Claude agreement](REFACTOR_AGREEMENT.md) supersedes the initial priority
suggestions below. Original findings are retained for traceability; several are
explicitly deferred, narrowed or rejected. RF-06 and RF-30 are cross-references to
UI-07/UI-03, not independent implementation tasks. No implementation was authorized
by the discussion itself.

## Findings

### RF-01 — Remove leftover minimum-observation code

- **Scope:** Low-risk cleanup.
- **Location:** [Sources/AppBundle/tree/MacWindow.swift:474](../Sources/AppBundle/tree/MacWindow.swift).
- **Evidence and cost:** oldMinimum is assigned but never read. canObserveMinimum includes a literal true operand. The same file retains a commented-out description implementation.
- **Suggested improvement:** Remove the unused local, literal operand and obsolete commented implementation. These distract from the actual eligibility checks and produce an avoidable warning.
- **Behavior to preserve:** Keep every remaining eligibility condition, its evaluation order, both confirmation reads and cancellation/generation checks. Do not merge different reset methods simply because their bodies look similar.
- **Verification before accepting a change:** LearnedWindowMinimumTest, LayoutMinimumFitTest and existing motion/parking tests; compiler warnings.

### RF-02 — Remove a conditional with an empty body

- **Scope:** Low-risk cleanup.
- **Location:** [Sources/AppBundle/tree/WorkspaceMonitorAssignment.swift:136](../Sources/AppBundle/tree/WorkspaceMonitorAssignment.swift).
- **Evidence and cost:** CGPoint.setActiveWorkspace performs a monitor lookup and an identity comparison inside an if whose body is empty.
- **Suggested improvement:** Remove the obsolete conditional after confirming the monitor lookup has no required side effect. The real assignment guards and registry write immediately around it should remain explicit.
- **Behavior to preserve:** Keep the refusal checks, setActiveWorkspace call and hierarchy invariant check in their existing order. Retain any required cache initialization if tracing reveals one.
- **Verification before accepting a change:** MonitorWorkspaceNavigationTest and WorkspaceCommandTest, including rejected assignments and both source/destination state.

### RF-03 — Share and name border color decoding

- **Scope:** Low-risk cleanup.
- **Location:** [Sources/AppBundle/ui/borders/WindowBorderController.swift:475](../Sources/AppBundle/ui/borders/WindowBorderController.swift).
- **Evidence and cost:** Appearance.init packs multiple variable declarations, parsing, channel selection and alpha packing into one line. WindowBorderFallbackView.draw repeats essentially the same conversion.
- **Suggested improvement:** Extract a small pure RGBA conversion helper with descriptive channel names, and format the initializer normally. This makes native and fallback color handling easier to compare.
- **Behavior to preserve:** Preserve six/eight-digit inputs, invalid-input fallback, byte order and alpha rounding exactly. Do not introduce a new color library or change accepted config syntax.
- **Verification before accepting a change:** WindowBordersConfigTest and WindowBorderPiecesTest; explicit six/eight-digit, transparent and malformed-value characterization cases.

### RF-04 — Rename removed-preset validation and remove unused inputs

- **Scope:** Low-risk cleanup.
- **Location:** [Sources/AppBundle/config/parseConfig.swift:266](../Sources/AppBundle/config/parseConfig.swift).
- **Evidence and cost:** applyShortcutsPreset no longer applies shortcuts: it only rejects rectangle. It accepts an unused mapping and an inout Config that it does not mutate; its caller resolves the mapping unnecessarily.
- **Suggested improvement:** Name this a validation function and pass the preset value plus the error accumulator. Remove the redundant mapping computation only after confirming resolve has no side effects.
- **Behavior to preserve:** Keep rectangle parseability and the exact existing semantic error, error ordering, default behavior and main-mode validation. Removing the legacy enum case would change compatibility.
- **Verification before accepting a change:** ConfigTest and shortcut-preset/config migration tests.

### RF-05 — Use one injected Settings owner throughout the view tree

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/ui/settings/SettingsControls.swift:48](../Sources/AppBundle/ui/settings/SettingsControls.swift).
- **Evidence and cost:** The window receives a model and its own draft store, but reusable controls write activeSettingTitle to ShortcutSettingsModel.shared and SettingsFieldFeedback observes the singleton. SettingsDraft also binds directly to SettingsDraftStore.shared.
- **Suggested improvement:** Pass the existing model/draft owner through the environment or explicit dependencies, with the current singleton as the production default. Avoid mixing injected model state with singleton field feedback.
- **Behavior to preserve:** Native Settings must keep the same process-lifetime model and drafts, save ordering and retry semantics. Treat any difference for injected models as a separately characterized test-isolation contract.
- **Verification before accepting a change:** SettingsSaveQueueTest plus a rendered control with two injected models, proving title/error/draft ownership does not cross models.

### RF-06 — Share setting identity and destination metadata

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/ui/settings/SettingsSearch.swift:42](../Sources/AppBundle/ui/settings/SettingsSearch.swift).
- **Evidence and cost:** The manual search index duplicates control IDs/titles and destinations. Separate configuration reference text supplies a second search path. Moving declarations into another file did not remove this duplication.
- **Suggested improvement:** Introduce a small shared descriptor for indexed settings and reuse it at the control declaration and search result. Add coverage that every indexed target is emitted by its destination page.
- **Behavior to preserve:** Keep the same 30 direct targets, page fallbacks, query token matching, result order and repeated-request identity. Expanding coverage or ranking differently is a separate feature.
- **Verification before accepting a change:** SettingsRefinementTest, rendered navigation/search tests, duplicate-ID and dangling-target checks.

### RF-07 — Represent a restart snapshot and its matches together

- **Scope:** High-risk staged refactor.
- **Location:** [Sources/AppBundle/tree/frozen/persistedFrozenWorld.swift:10](../Sources/AppBundle/tree/frozen/persistedFrozenWorld.swift).
- **Evidence and cost:** pendingRestartSnapshots and restartMatchedWindows are parallel arrays. Startup, append, compaction and reset code must keep their indices aligned, including across AX suspension points.
- **Suggested improvement:** Use one internal entry type containing a snapshot and its matched windows. Keep persistence encoding separate so the stored envelope remains unchanged. Migrate operations one at a time.
- **Behavior to preserve:** Preserve the in-flight compaction barrier, snapshot ordering, expiry, late-tree window, process identity and exact wire format. Do not compact or reindex while a reader is suspended.
- **Verification before accepting a change:** RestartWorkspaceTest, close/relaunch and late-restoration scenarios; compare saved envelopes before/after and exercise cancellation during awaits.

### RF-08 — Put refresh scheduling behavior next to its state owner

- **Scope:** High-risk staged refactor.
- **Location:** [Sources/AppBundle/layout/refresh.swift:6](../Sources/AppBundle/layout/refresh.swift).
- **Evidence and cost:** RefreshCoordinator owns task/event/generation fields, while refresh.swift forwards many properties and implements scheduling, coalescing and cancellation outside the owner. Test-reset functions repeat most state teardown.
- **Suggested improvement:** Move cohesive scheduler operations onto the existing coordinator, keeping the current global entry points as small adapters. Extract only shared teardown that has identical semantics.
- **Behavior to preserve:** Preserve pending-event merge priorities, activation recording, generation invalidation before cancellation, drain-on-error behavior, TaskLocal runtime binding and all test overrides.
- **Verification before accepting a change:** RefreshCoordinatorOwnershipTest, RefreshFailureRecoveryTest, RefreshFocusSyncTest and event-reassertion tests. No replacement of generations with a simple busy flag.

### RF-09 — Extract parking-corner geometry from layout side effects

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/layout/refresh.swift:610](../Sources/AppBundle/layout/refresh.swift).
- **Evidence and cost:** layoutWorkspaces starts by constructing six probe points per display, applying an unexplained important=10 weighting, then parks and reveals windows with native writes.
- **Suggested improvement:** Extract a value-only corner-selection function taking monitor rectangles, and name the weighting/tolerance constants. Leave asynchronous parking/reveal orchestration in place.
- **Behavior to preserve:** Preserve strict less-than comparison and right-corner tie behavior, two-point offsets, size-relative probes and park-before-reveal ordering.
- **Verification before accepting a change:** Parking geometry cases for adjacent/stacked displays, ties and unequal sizes; existing workspace transition tests and physical display checks.

### RF-10 — Separate native diagnostics from operational AX traffic

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/tree/MacApp.swift:166](../Sources/AppBundle/tree/MacApp.swift).
- **Evidence and cost:** MacApp combines registration, thread lifetime, discovery, writes, focus, recovery identity and doctor diagnostics. Diagnostic helpers have intentionally different timeout/error rules.
- **Suggested improvement:** Extract a narrowly scoped diagnostic helper supplied with the existing AX-thread access; keep MacApp responsible for its live thread and window cache. Avoid exposing all private state just to split files.
- **Behavior to preserve:** Keep diagnostic requests on the app AX thread, preserve short timeouts on fresh copies, stop at the first unanswered lookup, and retain operational element timeouts.
- **Verification before accepting a change:** AX refresh/diagnostic tests and doctor output comparisons; verify bounded work for a nonresponsive app.

### RF-11 — Reuse the AX frame attribute-read expression

- **Scope:** Low-risk cleanup.
- **Location:** [Sources/AppBundle/tree/MacApp.swift:373](../Sources/AppBundle/tree/MacApp.swift).
- **Evidence and cost:** getAxRect and getAxRectForLayoutConfirmation both read position/size and construct Rect. Confirmation additionally checks cancellation immediately before reading.
- **Suggested improvement:** Extract only the identical attribute-to-Rect conversion on the AX thread, retaining the explicit cancellation precheck in the confirmation caller.
- **Behavior to preserve:** Do not merge the public calls, remove cancellation checks, change nil handling or add cached reads where confirmation requires live evidence.
- **Verification before accepting a change:** Learned minimum confirmation tests and AX read cancellation tests.

### RF-12 — Name registration completion and retry phases

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/tree/MacApp.swift:59](../Sources/AppBundle/tree/MacApp.swift).
- **Evidence and cost:** getOrRegister nests a thread body, a TaskLocal context, subscription construction and a MainActor completion task containing termination, retry and latch signaling logic.
- **Suggested improvement:** Extract clearly named completion/retry helpers with explicit registration inputs. Keep AX setup inside its thread boundary and make latch completion visually easy to audit.
- **Behavior to preserve:** Preserve PID/launch identity checks, one shared attempt per PID, retry behavior, reverse-order teardown and signaling to every waiter. Do not move AX objects across threads.
- **Verification before accepting a change:** Existing app registration/retry/retirement tests, concurrent registration waiters and cancellation cases.

### RF-13 — Share the explicit relocation outcome handling

- **Scope:** Low-risk cleanup.
- **Location:** [Sources/AppBundle/ui/sidebar/WorkspaceSidebarActions.swift:63](../Sources/AppBundle/ui/sidebar/WorkspaceSidebarActions.swift).
- **Evidence and cost:** Bring Here and Move to Display independently call activateWorkspaceOnMonitorPreservingSourceViewport, focus the workspace on success and build the same assignment-error text on refusal.
- **Suggested improvement:** Extract the identical relocation-and-report phase after each action resolves its own target. Keep coordinate-based Bring Here and UUID-based Move to Display resolution separate.
- **Behavior to preserve:** Preserve missing-target behavior for each existing entry point, explicit relocation policy, focus timing, assignment refusal and full workspace organization. Ordinary selection must not call this helper.
- **Verification before accepting a change:** MonitorWorkspaceNavigationTest, sidebar override tests and UUID disappearance/repositioning tests.

### RF-14 — Represent drop-preview destinations explicitly

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/ui/sidebar/WorkspaceSidebarActions.swift:387](../Sources/AppBundle/ui/sidebar/WorkspaceSidebarActions.swift).
- **Evidence and cost:** workspaceSidebarDropPreview accepts targetWorkspaceName, targetsNewWorkspace, targetProjectId and targetMonitorScopeId as independent values, allowing contradictory combinations.
- **Suggested improvement:** Convert known caller combinations to a small destination enum with workspace/new-workspace/no-destination cases, then derive the unchanged preview view model.
- **Behavior to preserve:** Keep the current serialized/drag payload and view-model fields, group-vs-window handling, source labels and cursor behavior. Verify every existing caller before making a case impossible.
- **Verification before accepting a change:** WorkspaceSidebarDragTest and drop-preview model tests, including tab groups and creating a workspace.

### RF-15 — Pair overview models and panels in one presentation entry

- **Scope:** High-risk staged refactor.
- **Location:** [Sources/AppBundle/ui/overview/WorkspaceOverviewController.swift:107](../Sources/AppBundle/ui/overview/WorkspaceOverviewController.swift).
- **Evidence and cost:** Overview models and panels are parallel arrays. show indexes panels using displays; finishDismiss zips arrays; display switching indexes both arrays together.
- **Suggested improvement:** Use an internal presentation entry containing the display identity, model and panel. Derive public testing views if necessary instead of storing another parallel copy.
- **Behavior to preserve:** Preserve panel reuse, image budgets, callback cleanup, generation checks and native focus behavior. Do not release capture slots early on cancellation.
- **Verification before accepting a change:** WorkspaceOverviewTest and keyboard/model tests, rapid dismiss/reopen, zero panels and display removal.

### RF-16 — Avoid an unnecessary force unwrap during overview setup

- **Scope:** Low-risk cleanup.
- **Location:** [Sources/AppBundle/ui/overview/WorkspaceOverviewController.swift:155](../Sources/AppBundle/ui/overview/WorkspaceOverviewController.swift).
- **Evidence and cost:** show stores dependencies.project() in an optional property and immediately force-unwraps that property to obtain cards.
- **Suggested improvement:** Hold the returned project in a local nonoptional value, store it for lifecycle use, and pass the local to cards. This makes the setup invariant explicit.
- **Behavior to preserve:** Call the dependency once at the same point and preserve setup ordering and stored project identity.
- **Verification before accepting a change:** Overview show/dismiss/project-change tests; no change to empty-display handling.

### RF-17 — Reuse observer registration mechanics without merging lifetimes

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/ui/overview/WorkspaceOverviewController.swift:412](../Sources/AppBundle/ui/overview/WorkspaceOverviewController.swift).
- **Evidence and cost:** Overview presentation and pending selection register nearly identical desktop invalidation events and separately remove tokens. The lifetimes and reactions differ.
- **Suggested improvement:** Use a tiny observation-token collection or shared registration helper, parameterized by the existing invalidation closure. Retain separate bags for presentation and selection.
- **Behavior to preserve:** Preserve notification centers, main-queue delivery, foreign-app filtering, teardown order and selection cancellation after the overview closes.
- **Verification before accepting a change:** Overview lifecycle/selection invalidation tests and repeated open/close checks.

### RF-18 — Name per-window restoration eligibility and write verification

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/recovery/WindowRecoveryController.swift:124](../Sources/AppBundle/recovery/WindowRecoveryController.swift).
- **Evidence and cost:** restoreAppWindows combines journal lookup, fallback recording, baseline capture, identity checks before/after awaits, native-state validation, writes and readback inside a large closure. Crash recovery repeats related checks.
- **Suggested improvement:** Extract per-window steps with names reflecting eligibility, original-frame selection and confirmed restoration. Share only checks whose ordering and error policy are truly identical.
- **Behavior to preserve:** Preserve baseline/identity rechecks after suspension, not-fullscreen/not-minimized conditions, journal retention on failure and per-app bounded AX scheduling.
- **Verification before accepting a change:** Original restore/recovery journal/termination tests, partial failure and manual movement while disabled. Native recovery checks remain separate.

### RF-19 — Name the native-to-AppKit fallback transition

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/ui/borders/WindowBorderController.swift:380](../Sources/AppBundle/ui/borders/WindowBorderController.swift).
- **Evidence and cost:** WindowBorder.update repeats native-handle destruction, clearing and fallback update in creation, reshape and move failure branches.
- **Suggested improvement:** Extract the identical fallback transition with explicit frame/appearance inputs. Keep individual backend failure decisions visible at their call sites.
- **Behavior to preserve:** Preserve native-handle destruction exactly once, permanent fallback choice, cached geometry/corners/scale behavior, target placement and cleanup.
- **Verification before accepting a change:** WindowBorderPiecesTest, display and fallback tests; actual border inspection on supported macOS versions.

### RF-20 — Name native window event and tag meanings

- **Scope:** Low-risk cleanup.
- **Location:** [Sources/AppBundle/ui/borders/WindowBorderController.swift:56](../Sources/AppBundle/ui/borders/WindowBorderController.swift).
- **Evidence and cost:** The Swift callback repeatedly compares [723,806,807,808]; border.m separately lists event IDs and bit positions with only partial inline explanation.
- **Suggested improvement:** Introduce narrow named constants/event classification helpers at the existing native boundary. Keep unknown raw events available for fallback handling.
- **Behavior to preserve:** Preserve exact raw values, notification subscriptions, callback thread crossing, unknown-event handling and optional-symbol fallbacks. Do not eagerly resolve symbols or change private ABI signatures.
- **Verification before accepting a change:** MissionControlBorderSuppressionTest and border tests; desktop validation of Mission Control remains required.

### RF-21 — Make asynchronous framed-transport contracts readable

- **Scope:** Targeted refactor.
- **Location:** [Sources/Common/util/NWConnectionEx.swift:26](../Sources/Common/util/NWConnectionEx.swift).
- **Evidence and cost:** startBlocking is async, readNonAtomic reads a complete length-framed message, and several helpers return tuples containing an unused Void beside an optional error. IsDone returns another tuple with an unused Void.
- **Suggested improvement:** Introduce accurately named internal operations and simplify the continuation-once helper to a named Boolean result. Consider Result<Void,NWError> only as a separate mechanically verified caller migration; retain compatibility adapters where needed.
- **Behavior to preserve:** Preserve byte framing, length limits, timeout cancellation, receive termination and exactly-once continuation resumption. Naming work must not alter wire format or swallow transport errors.
- **Verification before accepting a change:** IPCFrameTest plus connection start/cancel/failure cases and CLI subscription behavior.

### RF-22 — Resolve relative-workspace stdin policy once

- **Scope:** Low-risk cleanup.
- **Location:** [Sources/Cli/_main.swift:126](../Sources/Cli/_main.swift).
- **Evidence and cost:** Three helpers repeat the same WorkspaceCmdArgs/MoveNodeToWorkspaceCmdArgs type switch to obtain relativity, explicit-flag presence and stdin use.
- **Suggested improvement:** Extract one small policy value and reuse it in main, leaving argument types and CLI parsing unchanged.
- **Behavior to preserve:** Preserve the default for non-workspace commands, explicit --stdin/--no-stdin handling, exact diagnostics and the 1000-line cutoff.
- **Verification before accepting a change:** CLI argument/stdin tests; relative and absolute workspace targets, no input, explicit input and oversized input.

### RF-23 — Separate request transport, dispatch and answer formatting

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/server.swift:36](../Sources/AppBundle/server.swift).
- **Evidence and cost:** newConnection contains the read loop, decode errors, special subscribe parsing, enabled-state gate, help/errors, command execution and response formatting in one function.
- **Suggested improvement:** Extract command dispatch and result formatting into named helpers with explicit request/connection inputs. Keep the outer connection lifecycle and subscription loop visible.
- **Behavior to preserve:** Preserve current enabled/help ordering, exec prohibition, command-session selection, stdout/stderr joining, incomplete-request warnings and connection cleanup.
- **Verification before accepting a change:** IPCFrameTest, public state/subscriber tests and CLI help/error/query/mutation smoke cases.

### RF-24 — Keep command capability metadata coherent

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/command/Command.swift:15](../Sources/AppBundle/command/Command.swift).
- **Evidence and cost:** Command.canSkipPostCommandRefresh contains a long runtime type whitelist. Menu window requirements and focus-only invalidation use other type classifiers, so adding a command requires locating multiple policy lists.
- **Suggested improvement:** Document one capability ownership scheme and move existing values to explicit command metadata or a centralized descriptor, using conservative defaults. Migrate one classifier at a time.
- **Behavior to preserve:** Keep unknown commands on the full-refresh path, existing query/presentation distinctions, closed-cache reset rules and structural invalidation. This is not permission to omit refreshes.
- **Verification before accepting a change:** PostCommandRefreshBenchmarkTest, refresh fast-path tests, command parsing and representative action/query tests.

### RF-25 — Separate installer sampling from verification decisions

- **Scope:** High-risk staged refactor.
- **Location:** [script/install_fork.py:233](../script/install_fork.py).
- **Evidence and cost:** verify tracks readiness samples, initial/current focus, last error, topology/config changes, restoration and status report selection in one long method.
- **Suggested improvement:** Extract a small observation record and polling phase, then keep policy decisions in their current ordered sequence. Name polling interval/count constants.
- **Behavior to preserve:** Preserve three-ready-sample behavior, 150 attempts, lock checks, rollback rules, user-focus detection, resume not replaying old focus and every report status/reason string.
- **Verification before accepting a change:** script/test_install_fork.py with fake operations only; do not test this refactor by repeatedly replacing the live app.

### RF-26 — Replace positional marketing variants with named data

- **Scope:** Low-risk cleanup.
- **Location:** [Sources/MarketingRenderer/WinMuxMarketingRenderer.swift:40](../Sources/MarketingRenderer/WinMuxMarketingRenderer.swift).
- **Evidence and cost:** Appearance proofs use an eight-element tuple. Filename prefixes such as wallpaper-brown and no-background also decide runtime rendering options.
- **Suggested improvement:** Use a named variant descriptor with explicit wallpaper sample/background options and a stable output filename. Separate fixture data from rendering mechanics when that improves navigation.
- **Behavior to preserve:** Keep exported filenames, all existing variant values, deterministic clock/geometry, native compositor rendering and current material/accessibility settings.
- **Verification before accepting a change:** make marketing-images and artifact comparison per docs/MARKETING.md when implementing; this audit does not regenerate images.

### RF-27 — Separate appearance catalogs from root configuration storage

- **Scope:** Low-risk cleanup.
- **Location:** [Sources/AppBundle/config/Config.swift:183](../Sources/AppBundle/config/Config.swift).
- **Evidence and cost:** Config.swift combines root config ownership/default access with sidebar configuration and a large color enum containing labels and RGB values.
- **Suggested improvement:** Move the cohesive color/appearance definitions into a clearly named existing appearance/config file while keeping type visibility and cases unchanged.
- **Behavior to preserve:** Preserve raw values, preset order, numeric samples, default values, imports and initialization behavior. Do not regenerate the palette or remove legacy types.
- **Verification before accepting a change:** ChromeAppearanceTest, config/schema tests and equality checks for preset order and colors.

### RF-28 — Avoid copying recursive layout tails unnecessarily

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/layout/DwindleLayoutGeometry.swift:28](../Sources/AppBundle/layout/DwindleLayoutGeometry.swift).
- **Evidence and cost:** Minimum extent recursion constructs Array(children.dropFirst()) and Array(ratios.dropFirst()); calculate repeats tail construction during up to three fitting passes per split.
- **Suggested improvement:** Explore immutable slices or index ranges for the recursive minimum solver. First benchmark large nested layouts and keep a parity test against current geometry.
- **Behavior to preserve:** Preserve child/ratio indexing, adaptive split orientation, three fitting passes, tolerance, output order and minimum constraints. Do not memoize across mutable runtime state or flatten groups.
- **Verification before accepting a change:** LayoutMinimumFitTest, Dwindle geometry tests and worst-case allocation/runtime measurements; no performance regression is claimed without measurement.

### RF-29 — Share the native rendering-test harness

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundleTests/ui/SettingsRefinementRenderingTest.swift:11](../Sources/AppBundleTests/ui/SettingsRefinementRenderingTest.swift).
- **Evidence and cost:** Rendering tests and WorkspaceSidebarOverrideTest repeat NSHostingView/window creation, offscreen placement, layout flushing and accessibility tree traversal. They wait fixed wall-clock intervals for UI materialization.
- **Suggested improvement:** Extract an owned test fixture with deterministic cleanup and shared accessibility queries. Where possible use an observed readiness predicate with a bounded timeout instead of an unconditional delay.
- **Behavior to preserve:** Keep real AppKit rendering and current assertions. Do not remove deliberate sleeps that simulate slow AX, cancellation or a blocked main thread in other tests.
- **Verification before accepting a change:** Run the affected rendering tests with nonzero test counts and inspect emitted fixtures. Model-only tests cannot replace these checks.

### RF-30 — Build tray sections directly rather than constructing and dismantling a temporary menu

- **Scope:** Targeted refactor.
- **Location:** [Sources/AppBundle/ui/menubar/NativeActionMenu.swift:148](../Sources/AppBundle/ui/menubar/NativeActionMenu.swift).
- **Evidence and cost:** Typed section references removed title coupling, but menu construction still populates a Commands menu, removes items to other parents and flattens grouping items. This leaves separator normalization as a separate queued concern.
- **Suggested improvement:** Introduce section builders that return owned items or append directly to the destination. Keep final grouping and shortcut registration order explicit; handle separator normalization as a separately approved observable cleanup.
- **Behavior to preserve:** Preserve final item hierarchy/order, command payloads, enabled/check states, icons/visibility and binding resolution. Do not mix this with adding/removing actions.
- **Verification before accepting a change:** ActionMenuTest and a serialized full menu-tree comparison in main/alternate mode, paused state, empty workspace and multiple displays.

## Separate correctness follow-up: release prerequisites

The release workflow runs `make check`, but does not create
`.deps/config-schema` or install requirements-schema.txt. The CI workflow explicitly
does both. makefile's check target immediately fails if that interpreter is absent.
On a fresh hosted checkout this appears to block releases before tests run. This is
source-confirmed prerequisite inconsistency, not an observed hosted-run failure.

Locations: `.github/workflows/release.yml` (Test step),
`.github/workflows/ci.yml` (schema setup), `makefile:85` (check target).
Proposed follow-up: share or repeat the existing pinned setup in release, then
validate the workflow on a clean runner. This changes a failing workflow's behavior
and must remain a separate fix from pure refactoring. Do not run signing cleanup
against a personal keychain during verification.

## Keep these existing designs

- ConfigFileStore owns validated writes, backup rotation and conflict checks.
  Do not replace it with independent writes from each Settings page.
- SettingsSaveQueue serializes committed saves independently of submitting views.
  Do not cancel committed work just because a page disappears.
- Native operations distinguish unknown AX state from confirmed absence, use
  process/window identity, revalidate after awaits, and retain cancellation guards.
- Workspace selection and explicit relocation have different ownership semantics.
  Splitting functions must not turn ordinary selection into a display move.
- DockSwipeTracker already has an explicit state enum and documented verdicts.
  Its state machine does not need a generic framework merely to reduce line count.
- SubscriberEventWriter is bounded to 64 events by default. Array.removeFirst has
  a small bounded cost here; a new queue abstraction is not justified by big-O alone.
- Config watcher and writable-file symlink resolution have different purposes.
  Similar-looking code is not automatically interchangeable.
- Private API optional-symbol fallbacks and native/AppKit border paths are required
  compatibility behavior. Do not remove them as apparent duplication.
- Runtime TaskLocal scoping and model-local injection already provide useful
  testing seams. Extend them deliberately rather than introducing another global.

## Suggested implementation order

1. RF-01, RF-03, RF-04, RF-11, RF-13, RF-16: bounded cleanups with direct evidence.
2. RF-05/RF-06 and RF-30: Settings identity/dependency consistency and menu builders.
3. RF-07/RF-08/RF-15/RF-18: separate small changes with characterization tests,
   because asynchronous lifetime and identity errors can lose user organization.
4. Measure RF-28 before optimizing. Address release prerequisites separately.

## Validation of this review

This review modified documentation only. No app build, installation, window
manipulation or new runtime tests were performed. The last implementation check
before the audit passed 1,495 Swift tests plus Python checks; that result is baseline
evidence, not proof that any proposed refactor is correct. Reference paths and
line anchors in this report are checked against the current working tree.

## Implementation status

The selected Codex–Claude sequence is implemented; see
[the implementation report](REFACTOR_IMPLEMENTATION.md) for changes, commits,
characterization evidence and remaining native-validation limits. The other
original candidates are not implicitly approved or implemented.
