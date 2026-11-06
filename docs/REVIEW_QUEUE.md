# UI simplification review queue

Review scope: uncommitted Settings search, tray menu, layout previews and sidebar
movement changes, 2026-11-06. Items below are queued, not fixed. Source inspection
is distinguished from native reproduction; existing passing tests do not establish
scrolling, accessibility or physical-display correctness.

## Confirmed from source

- [x] **UI-01 · P2 · Configuration settings disappear from search.**
  `SettingsSidebarItem.matchesSearch` in
  `Sources/AppBundle/ui/settings/ShortcutSettingsView.swift` filters reference
  sections by `pane == self`. Sections with no pane are excluded everywhere.
  Queries: `on-window-detected`, `inherit-env-vars`.
  Fix: map known destinations (rules to Automation), and route remaining unmapped
  sections to Configuration. Add regression coverage for both queries and ensure
  selecting the result reaches the documented setting/editor.
  Resolved: unmapped sections now match Configuration, which opens its editor by
  default. Regression coverage includes both reported queries and every unmapped
  section title. `make check` passed with 1,493 Swift tests, zero failures.

- [x] **UI-02 · P3 · Search highlight survives unrelated navigation.**
  In `ShortcutSettingsView`, `searchTarget` clears only when the query changes.
  Select Show window borders, navigate to Windows, then return to Appearance
  without editing the query: the old target is retained and its page's task can
  scroll/highlight it again. Decide whether page navigation should cancel a search
  jump, then test navigation and repeated explicit selection separately.

- [ ] **UI-03 · P3 · Reparenting tray items leaves adjacent separators.**
  `NativeActionMenu.menuNeedsUpdate` removes navigation/layout items from the
  temporary Commands menu, but only removes leading separators. Separators before
  the removed navigation groups and before Reload Config remain adjacent.
  Build sections directly in their destination menus, or normalize separators
  after extraction. Assert no leading, trailing or adjacent separators recursively.
  Native AppKit may suppress their visible presentation; the model defect is
  visible from construction, not evidence of a visual failure.

## Risks requiring targeted reproduction

- [x] **UI-04 · P2 · Search scrolling has no layout-readiness guarantee.**
  `SettingsScrollView` calls `scrollTo` in both `onChange` and a task after
  `Task.yield()`. Yielding does not guarantee a newly selected Form has registered
  its anchors. Test a cold page, a target below the fold, rapid result changes,
  repeated selection and a minimum-size Settings window. Verify actual visibility,
  not only search-result IDs. Prefer one cancellation-aware navigation path tied
  to anchor/layout readiness, with bounded work. No missed scroll reproduced yet.

- [x] **UI-05 · P2 · A display target can become stale while its menu is open.**
  The sidebar's Move to Display action captures a scope derived from screen origin.
  If displays disconnect or exchange positions before invocation, resolution can
  fail silently or refer to a different physical display. Reproduce with topology
  changes between menu construction and action execution. Prefer stable display
  identity and explicit failure when the selected display has disappeared. Check
  workspace tree retention and source/destination ownership if reproduced.

## Maintainability and scale

- [x] **UI-06 · P3 · Visible menu titles act as routing identifiers.**
  Menu extraction searches strings such as Window Group, Resize and Join With.
  Renaming/localizing a label can silently change placement. Use dedicated builder
  methods or typed action/section IDs; keep display text out of control flow.
  Resolved in the refactoring pass: typed section keys retain item references;
  display titles no longer determine placement.

- [ ] **UI-07 · P3 · Search metadata duplicates control declarations.**
  The manual 30-control index can drift from actual labels, IDs and destinations.
  Page matching also rebuilds the complete reference inventory for each page on
  repeated filter passes. Use shared setting descriptors and compute matches once
  per query. Add coverage that indexed targets exist on their declared pages.
  Current inventory is small; no measured performance regression is claimed.

- [ ] **UI-08 · P3 · Keyboard and accessibility search behavior lacks UI coverage.**
  Direct results are plain Buttons mixed with NavigationLinks in a selection List.
  Test keyboard-only search, Return activation, focus after jumping, VoiceOver
  announcement of the destination, high contrast and Reduce Motion. Color-only
  highlighting and a successful metadata test do not prove successful navigation.

## Validation status

The latest complete `make check` passed before this review. No new runtime tests
were run for this queue-only update. The earlier external review's focused test
attempt was blocked by a concurrent SwiftPM process; it is not a test failure.
Build 309 completed; installation of that build has not been performed.

## Behavior-preserving refactoring pass

The structural survey inventoried AppBundle, Common, Cli, PrivateApi and scripts
(approximately 62,000 lines, excluding tests, vendors and documentation). Selected
entry points in runtime ownership, refresh, native application management, layout,
recovery, gestures, configuration transactions, CLI and installation were inspected.
This was a structural survey and targeted refactor, not a line-by-line correctness
audit of every file.

Changes made:

1. Tray menu sections now return references keyed by `CommandMenuSection`. Moving
   items no longer depends on matching display titles. Construction order, menu
   contents, shortcut binding registration and remaining separators are preserved.
2. Settings search types, environment state and control catalog moved from
   `SettingsControls.swift` to `SettingsSearch.swift`. Rendering primitives no
   longer own the search catalog. Matching rules and indexed controls are unchanged.
3. Settings computes control matches, page matches and the nonempty-query flag
   once per view update. Sidebar sections reuse those values instead of repeating
   the same scans and reference-string construction.
4. Search aliases use an explicit switch instead of a nested ternary expression.
   The actual aliases and unmapped-reference behavior are unchanged.
5. Layout-preview nesting was indented to match the view hierarchy. Geometry and
   accessibility properties are unchanged.
6. Recovery tracker reset/forget/success methods put each state mutation on its
   own line, exposing updates to both tracking collections. Mutation order is unchanged.
7. Installer state comparison names the before/after assignment maps and surviving
   IDs, and formats the result by moved/closed/opened category. Key conversion,
   comparisons, ordering rules and report structure are unchanged.

Next candidates need dedicated behavior review before refactoring: `MacApp.swift`
(AX calls and thread ownership), `layout/refresh.swift` (scheduling/cancellation),
and sidebar actions (workspace selection versus relocation). Their size alone is
not evidence that splitting them will improve correctness or maintainability.

## Latest queue fixes

UI-02: ordinary page navigation now clears the search target. Selecting a result
sets its fresh request after navigation, so explicit repeated selections still work.

UI-04: the target field emits a bounds-anchor preference during layout. The form
scrolls only when that request matches its current target; the yield-based task
and duplicate immediate scroll were removed. Native scrolling, keyboard navigation
and minimum-window-size checks remain pending under UI-08.

UI-05: Move to Display captures a display UUID, resolves it inside the execution
session and reports missing displays/workspaces. A different display occupying the
old coordinates cannot receive the move. Missing UUIDs are rejected safely.
Tests cover repositioning, replacement at the same origin, disconnection, missing
identity and case-insensitive UUID matching. Existing relocation policy continues
to enforce assignments and preserve the workspace tree. Physical movement and
unplug/reconnect checks remain pending.

## Refactoring priority agreement

See [the Codex–Claude agreement](REFACTOR_AGREEMENT.md) before implementing audit
recommendations. RF-06 is tracked under UI-07; RF-30 references UI-03. Keep one
implementation task per concern and preserve the agreement’s deferred scope.
