# Dinky adaptations: execution checklist

Status: in progress; completed work and remaining manual checks are recorded below.
Read [the evaluation](DINKY_FIT_PLAN.md) for rationale and upstream evidence.
This is a Swift/macOS project; this plan does not introduce Lua scripting.

## Instructions for the executing model

1. Read `HACKING.md`, `docs/TESTING.md`, this file and applicable `AGENTS.md`
   instructions. Run `git status --short` and `git rev-parse HEAD`. Preserve
   pre-existing changes. The evaluation baseline is historical; inspect current
   code before assuming a task is still missing.
2. Execute tasks in the order below, one coherent task at a time. Do not implement
   all deliveries in one patch. Continue to the next independent task after
   verification; do not request confirmation between ordinary reversible edits.
3. Paths below are relative to the repository root. A path marked **new** is a
   proposed output. All other paths are starting points to inspect. If a file
   moved, locate its symbol with `rg` before creating a replacement.
4. Keep projects, persistent names, tabs, nested containers and explicit display
   moves intact. Do not add scrolling, reserved grids, native Space management,
   an automatic updater, new default hotkeys or a second configuration parser.
5. Use WinMuxX source as the behavioral authority. Dinky examples are references,
   not compatible configuration to paste. Do not change runtime behavior to make
   a documentation example true.
6. Work in the repository and temporary test fixtures. Installation, publishing,
   live config replacement and changing system permissions are separate work;
   the plan alone does not request those operations. Native checks that need
   them remain explicitly pending until the session authorizes them.
7. On a failed check, fix the task or record the precise blocker. Do not weaken
   tests, replace the lockfile, broaden a refactor or mark a skipped check passed.
   If blocked by a product decision, document the alternatives and continue
   unrelated tasks. A path rename or routine implementation choice is not a blocker.

## Task order and status

Update status to `in progress`, `implemented; manual pending`, `done`, or
`blocked: <reason>`. An audit can finish as `done: already covered` with evidence.

| ID | Task | Depends on | Status |
| --- | --- | --- | --- |
| P0 | Record current baseline and coverage | — | done |
| D1 | Quick start and concepts | P0 | done |
| D2 | Layout guide and diagrams | D1 | done; five SVGs rendered and inspected at 360px and 1,000px |
| D3 | Recipes and command guide | D2 | done; parser examples tested |
| D4 | Navigation, changelog and migration cleanup | D3 | done |
| S1 | Configuration inventory | P0 | done |
| S2 | Schema and parity checks | S1 | done; Draft 2020-12 validator, shared parser/schema fixtures and static-key coverage check pass |
| S3 | Editor setup instructions | S2 | implemented; local setup and VS Code association documented, extension UI verification pending |
| H1 | Shortcut backend inventory and health model | P0 | partial; side-filtered backend failure is reported; Carbon registration health is unobservable here |
| H2 | Recovery lifecycle | H1 | implemented; four bounded retries cancel on config reset and app termination; injected retry policy tests pass |
| H3 | Menu and doctor integration | H2 | implemented; warning/report tests pass, VoiceOver/native review pending |
| R1 | Dangling config symlink bootstrap | P0 | done; regression passes |
| R2 | Drag continuity under layout changes | P0 | pending; current drag tests cover sample gating and resize calibration, not a layout mutation during a live drag; no model seam for that scenario |
| R3 | Crowded resize after flatten | P0 | 11-sibling resize regression passes; native visual check pending |
| R4 | Quoted and combining Unicode arguments | P0 | done; regression passes |
| R5 | Multi-display topology and navigation | P0 | existing tests pass; physical dock/undock check pending |
| V1 | Final checks and evidence | all applicable tasks | implemented; local `make check` passed with 1,353 Swift tests and Python checks; native/editor/remote checks pending |

Default execution order: P0 → D1–D4 → S1–S3 → H1–H3 → R1–R5 → V1.
A reproduced input-blocking or data-loss issue takes precedence over that order.

## P0 — baseline

Read the existing 0.19–0.21 adoption records and `docs/RELEASE_VALIDATION.md`.
Create **new** `docs/DINKY_EXECUTION_RESULTS.md` containing the actual starting
commit, dirty-file summary, toolchain version and task evidence sections.
Record existing relevant test names; do not copy historic pass counts as fresh
results. No full test run is needed before prose-only work.

Done when the results file distinguishes existing behavior, proposed changes and
checks performed during this execution. Record any scope already implemented so
later tasks extend it instead of duplicating it.

## D1 — quick start and concepts

Read `README.md`, `docs/CONFIGURATION.md`, `docs/FORK.md`,
`Sources/AppBundle/tree/WorkspaceMonitorAssignment.swift` and
`Sources/AppBundle/tree/WorkspaceMonitorViewportOrdering.swift`.

Create **new** `docs/QUICK_START.md` and `docs/CONCEPTS.md`.

- Quick start: link installation, grant Accessibility, open two ordinary app
  windows, select a workspace through the sidebar, change a setting, run doctor.
  Describe optional Screen Recording for previews. Link detailed recovery help.
- Concepts: explain projects, internal workspace names, labels, display ownership,
  containers, tiled/floating/fullscreen windows and restart persistence.
- Include one concrete two-display example: selecting the visible workspace
  focuses its owner; an explicit move changes its owner. Include an example
  distinguishing a custom label from an internal workspace name.

Check each factual claim against current docs/source. Use `--help` only for CLI
verification here; do not execute window-moving examples on the user's desktop.
Done when a newcomer has an ordered path and every advanced topic links onward.

## D2 — layouts

Read `Sources/AppBundle/command/impl/WorkspaceLayoutCommand.swift`,
`LayoutCommand.swift`, `SwapWithMasterCommand.swift`, `BalanceSizesCommand.swift`
and `FlattenWorkspaceTreeCommand.swift` in that same directory. Read
`Sources/AppBundleTests/command/MasterLayoutTest.swift` and
`WorkspaceLayoutCommandTest.swift`.

Create **new** `docs/LAYOUTS.md` and original SVGs under **new**
`docs/assets/layouts/`: `dwindle.svg`, `master-tiles.svg`,
`master-accordion.svg`, `tabs.svg`, `ultrawide.svg`.

- Explain window insertion and closing, focus, command scope and prerequisites.
- Show the workspace/container distinction and master stack toggling.
- Explain how balance differs from flatten; derive reset behavior from source.
- Explain why query output `fixed` does not advertise reserved grid support.
- SVGs use numbered windows, readable labels, accessible titles/descriptions,
  viewBox sizing and no external assets. Do not generate raster substitutes.

Verify help for `workspace-layout`, `layout`, `swap-with-master`, `resize`,
`balance-sizes` and `flatten-workspace-tree`. Render and inspect the figures at
approximately 360px and 1000px widths. If rendering is unavailable, record that
specific visual check as pending. Done when text and diagrams agree with the
existing command tests; no runtime change belongs in this task.

## D3 — recipes and command reference

Read `resources/default-config.toml`, `Sources/AppBundle/config/parseConfig.swift`,
`WorkspaceLayoutConfig.swift`, `FollowAppActivationConfig.swift`,
`ModifierSides.swift`, `Sources/Common/cmdArgs/cmdArgsManifest.swift`, and
`docs/DINKY_019_ADOPTION.md`.

Create **new** `docs/RECIPES.md` and `docs/COMMANDS.md`.
Write six recipes: ultrawide coding; laptop/docked layouts; floating utility;
activation exclusion; one-sided modifier; display-change hook with bundled CLI.
Each has a goal, exact TOML placement, complete snippet, observable result and
undo instructions. Use a generic bundle ID only if clearly marked for replacement.

Commands guide groups tasks by window, container, workspace, project, display and
diagnostics. Link actual help for flags; avoid duplicating every help paragraph.
Mark configuration-only commands as such. Never execute hook examples to validate
them: parse their configuration and command strings.

Add **new** `Sources/AppBundleTests/config/DocumentationExamplesTest.swift` only
for executable examples. Extract explicitly marked TOML examples from the guide,
wrap fragments as documented, and call the existing `parseConfig`. Check command
examples through existing argument parsing APIs; follow existing test conventions.
Ensure new marked examples cannot silently escape validation. This tests public
examples, not Markdown wording. Run the focused test and correct examples when
they fail. Do not relax the parser.

## D4 — navigation and release information

Edit `README.md` and `docs/README.md` to link the new guides in learning order.
Keep existing content until its replacement is linked; retain valid anchors when
moving sections, or replace them with short forwarding sections.

In `docs/DINKY_020_ADOPTION.md`, replace executable obsolete workspace-layout
examples with current syntax and label historical prose explicitly. Link 0.21.
Create **new** `CHANGELOG.md` with an Unreleased section for this work. Add past
release entries only when tags/release evidence establishes their contents.

Done when local links/anchors resolve, a search finds no unlabelled executable
`winmuxx layout master` or `winmuxx layout dwindle` example in current guides,
and no unreleased runtime feature is described as shipped.

## S1 — configuration inventory

Read `Sources/AppBundle/config/Config.swift`, `parseConfig.swift`, related parse
helpers and `Sources/AppBundle/ui/settings/ConfigurationReference.swift`.
Create **new** `docs/CONFIGURATION_SCHEMA_INVENTORY.md` with columns:
key/path, accepted types, enum/range, default source, legacy aliases, dynamic-key
rules, parser source symbol and checks that only the parser can perform.

Cover all currently accepted sections, including modes, rules, monitor selectors,
workspace/display overrides and scalar-or-table alternatives. Do not assume the
default file enumerates all accepted keys. Done when every parser-recognized
field is accounted for, or a specific unresolved field blocks S2 completion.

## S2 — schema and contract checks

Create **new** `docs/schemas/winmuxx.schema.json`. Choose and declare a JSON Schema
dialect supported by the intended TOML editor; verify current editor documentation
when implementing. Use descriptions and reusable definitions. Dynamic workspace,
mode and display keys must remain valid. Reject extra keys only where WinMuxX's
parser does. Do not invent defaults or duplicate semantic command validation.

Create shared valid/invalid TOML fixtures under **new**
`resources/test-fixtures/config-schema/`. Add a Swift parser test in **new**
`Sources/AppBundleTests/config/ConfigurationSchemaFixturesTest.swift` and a schema
check in **new** `script/test_config_schema.py` consuming those same fixtures.
Choose an explicit reproducible TOML/JSON Schema validation dependency setup;
record versions and setup instructions, integrate with `make check` and CI using
the repository's existing dependency conventions. Do not silently skip a missing
validator or use a handwritten partial validator.

Fixtures must cover defaults, quoted names, regexes, monitor arrays, both activation
forms, legacy aliases, wrong types/enums and unknown keys. Mark runtime-only
semantic failures separately: schema acceptance does not imply parser acceptance
for command strings or cross-field constraints. Add an inventory/schema coverage
check for static keys. Done when all fixtures have explicit expected outcomes,
the schema validates itself, and focused parser/schema checks pass.

## S3 — editor use

Extend `docs/CONFIGURATION.md` with local schema setup and a supported editor
example. Show completion for workspace layout and an intentional wrong-enum error.
Document the parser as authoritative. Keep remote publication outside this task;
do not insert a hypothetical schema URL into generated user configurations.

Done when local setup is documented and the editor check is recorded as passed
or pending with its exact reason. Add publication as a separate optional follow-up.

## H1 — backend inventory and health state

Read `Sources/AppBundle/config/HotkeyBinding.swift`, `HotkeyBindingModel.swift`,
`SideFilteredHotkeys.swift`, `SequenceBinding.swift`, plus callers found with
`rg -n 'tapCreate|SideFilteredHotkeys|registerHotKey' Sources`.
Trace the actual owner and teardown path of each shortcut mechanism.

Record a table in the results: backend, required-by modes/bindings, installation
failure signal, disable/recovery signal, owner and cleanup. Do not treat inability
to observe Carbon registration health as proven success or failure.

Add a small value-type health snapshot within the existing hotkey ownership:
required backends, observed availability, affected features and reason. Derive
healthy/partial/unavailable status only from observed required backends; represent
unknown status explicitly where necessary. No second hotkey registry or global
singleton. Add focused policy tests for no requirements, all healthy, partial
failure, total failure and recovery. Done when the state has an actual producer,
not just UI hardcoded to healthy.

## H2 — bounded recovery

Extend the existing install path, not the key callback's responsibilities.
Prefer existing activation/config-reload/permission lifecycle triggers. Inspect
available permission observation rather than inventing a notification name.
As a fallback, retry failed required installation after 0.5s, 1s, 2s and 4s,
then stop until a relevant lifecycle event starts a new recovery attempt.
Inject scheduling/installation into tests so they do not sleep or require AX.

Use an ownership generation to reject stale completions. Cancel recovery when
disabled, terminating, or when the current mode no longer requires the backend.
At most one retry task and one tap/source may exist. Preserve consumed-key and
unbound-key exit behavior and existing disabled-tap re-enablement. Successful
recovery publishes health without re-registering unaffected Carbon bindings.

Done when tests cover fail→success, retry exhaustion, duplicate triggers,
mode/config change, disable/termination, stale completion and key-release cleanup.
No permanently running timer is allowed. If lifecycle ownership is unclear, resolve
it before wiring retry callbacks into multiple unrelated entry points.

## H3 — native menu and doctor

Edit `Sources/AppBundle/ui/menubar/TrayMenuModel.swift`, `NativeActionMenu.swift`
and `DiagnosticsReport.swift` to consume the same health snapshot. Publish only
changed values. Show affected features and a recovery action/instruction while
degraded; remove the warning after recovery. Preserve workspace/mode labels and
provide accessibility text. Do not scan AX or retry installation while rendering
the menu or printing diagnostics.

Extend `Sources/AppBundleTests/ui/ActionMenuTest.swift` where applicable and add
focused diagnostic assertions. Record manual checks separately: permission grant,
typing and key-up, modifier sides, mode exit, warning clearance and VoiceOver.
Done when automated rendering/reporting checks pass; mark native checks pending
if they require unauthorized system changes or unavailable interaction.

## R1–R5 — reproduce first, fix only demonstrated defects

For each audit, record `already covered`, `new regression passes`, `reproduced and
fixed`, or `manual check pending`. A missing test is not proof of a runtime defect.

| ID | Exact reproduction to cover | Read/extend |
| --- | --- | --- |
| R1 | Temporary dangling config link; bootstrap; create target later; retarget link; atomically replace target; delete target while running | `config/ConfigFileStore.swift`, `ConfigFileWatcher.swift`; tests `config/ConfigBootstrapTest.swift`, `ConfigFileWatcherTest.swift` |
| R2 | Begin tiled drag; insert/remove sibling before release; drop in original slot; repeat with usable-screen-area change | `Sources/AppBundleTests/mouse/MouseDragSubjectTest.swift` and actual drag/frame-write callers |
| R3 | Flatten 11 tiled windows; grow/shrink each relevant axis; repeat with app minima preventing growth | `Sources/AppBundleTests/command/ResizeCommandTest.swift`, `DwindleResizeCommandTest.swift` |
| R4 | One argument containing both quote types; leading combining Unicode scalar; following flag and its value | `Sources/Common/cmdArgs/splitArgs.swift`, CLI serialization and server decoding discovered from callers |
| R5 | Queue selections on two displays; change usable geometry; disconnect/reconnect one display | `Sources/AppBundle/ui/core/MonitorConfigurationObserver.swift`, `tree/WorkspaceMonitorAssignment.swift`, `Sources/AppBundleTests/command/MonitorWorkspaceNavigationTest.swift` |

Paths abbreviated `config/` in R1 refer to AppBundle code and AppBundleTests tests
respectively. Use temporary filesystem fixtures and fake AX/model adapters.
R4 must assert the decoded argument array, not just the formatting function's
output. R3 must assert finite positive frames and retained windows/tree shares.
R5 must assert ownership and intended focus separately. For R2/R5, model tests
do not replace physical mouse/display validation. Use the evaluation's acceptance
table for the remaining invariants. If a defect is found, first show the regression
fails, make the smallest subsystem fix, then show it passes.

## V1 — verification and completion report

Use the pinned toolchain from `script/setup.sh`. For focused Swift checks use:

```sh
bash -lc 'source ./script/setup.sh && swift test --force-resolved-versions --no-parallel --filter DocumentationExamplesTest'
```

Replace the filter with the test class actually changed (including new classes
above); verify that tests ran rather than accepting a zero-test result. Existing
tests use process-wide adapters, so do not enable parallel suite execution.
For runtime/schema changes, finish with `make check` after focused checks pass.
For prose-only tasks, validate examples, links and figures; no full app suite is
needed. Run `git diff --check` and review `git diff --stat` for unrelated changes.

In `docs/DINKY_EXECUTION_RESULTS.md`, record per task:

```text
Task ID / status:
Behavior or documentation delivered:
Files changed:
Checks run, actual result, and evidence location:
Manual/remote checks still pending:
Remaining limitation or blocker:
Next task:
```

Update this checklist and the roadmap without erasing older historical evidence.
Do not declare the whole plan complete while required manual checks remain pending.
The final user report should state delivered work, tests, remaining native checks
and whether anything was installed or published. Do not infer a release from a
successful local build.
