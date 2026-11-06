# Simplify review — 2026-10-03

## Scope

Repository-wide inventory and searches covered 616 Swift, Python and shell files
under `Sources` and `script`. Manual inspection focused on tree navigation,
layout and resize geometry, command output, settings persistence and shortcut
conflicts, sidebar search, global events, monitor reconciliation, recovery,
shared utilities and release validation. Generated parser code and dependencies
were excluded from edits. This is an initial structural review, not a line-by-line
audit of every file.

## Applied

- Flattened count-only branches in four list commands, preserving filtering,
  title lookup order, formatting and error handling.
- Reused the existing orientation-aware point offset helper in layout and resize
  preview code.
- Used short-circuit collection search for descendant window lookup and grouped
  equivalent monitor-resolution cases.
- Replaced optional transformations with direct optional binding when identifying
  managed workspace shortcuts.
- Removed two shortcut-conflict comparisons whose branches both returned `nil`,
  and removed their unused parameters. Managed shortcut eligibility is unchanged.
- Unified tab-group search result construction while preserving tab-match priority
  and group-title fallback.

## Candidates for deeper review

- `WorkspaceSidebarView.swift` (1125 lines) and `WorkspaceSidebarPanel.swift`
  (998 lines): inspect view composition separately from panel lifecycle, hover,
  expansion and cursor trapping. Extraction should retain state ownership and
  event ordering; file length alone is not a reason to refactor.
- `ConfigSettingsViews.swift` (788 lines): separate setting sections and reusable
  controls if further additions make navigation difficult. Preserve save callbacks
  and settings revision identity.
- `WorkspaceSidebarActions.swift` (725 lines): evaluate extraction by responsibility
  (project operations, workspace operations, window operations) without introducing
  a generic dispatcher or changing session boundaries.
- `WindowMouseInteractionDriver.swift` (614 lines): retain gesture, frame gating and
  cancellation boundaries; consider focused helpers only after tracing each state
  transition with existing drag tests.
- `WinMuxMarketingRenderer.swift` (1340 lines): separate independent preview scenes
  if they need frequent modification. Existing declarative composition does not
  require a behavior-preserving rewrite solely to reduce line count.

No feature changes were included. Potential functional issues belong in separate
changes with explicit behavioral expectations.

## Validation

- Initial targeted Swift run: 92 tests, zero failures.
- Final complete Swift run: 677 tests, zero failures; build succeeded.
- Release appcast and fork identity scripts: 11 tests, zero failures.
- `swift package resolve`: succeeded; `Package.resolved` unchanged.
- `git diff --check`: passed.

## Deeper review

Traced the sidebar's editing lifecycle (search adoption, buffered keys, commit,
cancel, event taps and pointer cancellation), project actions, settings save
serialization and move/resize driver transitions. Refactoring preserves stored
state ownership, main-actor isolation, asynchronous session checks and side-effect
ordering.

Applied changes:

- Moved sidebar search and rename methods into `WorkspaceSidebarViewEditing.swift`
  and panel editing/event monitors into `WorkspaceSidebarPanelEditing.swift`.
  Their state remains in the existing view and panel.
- Unified AppKit and Core Graphics key interpretation, preserving navigation keys,
  Command-over-Option delete priority, shortcut rejection, Unicode input and lazy
  text lookup. Core Graphics retains its original eight-code-unit input buffer.
- Split mouse-driver extensions into move, shake and resize responsibilities;
  shared session state remains in `WindowMouseInteractionDriver`.
- Removed the permanently false move-opacity branch and duplicate tab-strip chrome
  branch. Move still restores opacity before configuring chrome.
- Separated Settings controls from configuration persistence. Reusable controls
  are module-internal; private implementation details remain private. Serial saves,
  validation-before-write, reload and failure feedback are unchanged.
- Removed the unused Settings config reader and replaced a force-unwrapped check
  on a guaranteed nonempty line array with a direct optional comparison.
- Extracted project actions together with their private deletion confirmation.
- Reused monitor-scope resolution instead of duplicating its sentinel checks.

### Functional findings and follow-up fixes

1. `GlobalObserver.scheduleFocusFollowsMouse` checks the config and mouse state but
   not `TrayMenuModel.shared.isEnabled`, both before scheduling and after the delay.
   `EnableCommand` does not cancel that task. With pointer focus configured,
   disabling WinMux can therefore leave pointer-driven focus active. A separate fix
   should gate both stages and cover disabling while a dwell is pending. This is a
   code-path finding; it has not been reproduced interactively.
   **Fixed in follow-up:** scheduling and execution both require WinMux to be
   enabled. Disabling cancels the pending task and clears its candidate immediately,
   so re-enabling cannot resume a previous dwell. A regression test exercises the
   disable command and checks candidate cancellation across re-enable.
2. The Hover delay control uses `SettingsStepper`, whose unit is hard-coded to
   `pt`, although the scheduler interprets the value as milliseconds. A separate
   presentation fix should make the unit configurable and use `ms` for this field.
   **Fixed in follow-up:** the integer stepper accepts a unit with `pt` as its
   default; Hover delay explicitly uses `ms`.
3. Compilation reports existing unused unstructured throwing-task warnings in
   global observers, focus callbacks and legacy Settings code. Those paths were
   not changed here. Deciding how failures should be surfaced needs a separate
   error-handling change, especially with release warnings treated as errors.

### Verification

- Sidebar/drag/resize/Settings targeted run: 151 tests passed.
- Four new keyboard regression tests passed, including parity between AppKit and
  Core Graphics navigation, modifier priority, Unicode/control filtering and lazy
  text reads.
- Final full suite: 681 Swift tests passed; build succeeded.
- Appcast and fork identity: 11 Python tests passed.
- Dependency resolution succeeded and left `Package.resolved` unchanged.
- No interactive visual or Accessibility validation was performed.
