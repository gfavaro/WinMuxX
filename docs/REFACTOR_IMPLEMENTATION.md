# Agreed refactoring implementation — 2026-11-06

This implements the selected sequence in REFACTOR_AGREEMENT.md. Deferred proposals
remain deferred. No release tag, installation or native window manipulation is
part of this implementation.

## Changes and reasons

- Baseline `49415e89`: committed the previously validated UI simplifications,
  review reports and queue fixes separately so later refactors have a reviewable
  starting point. The unrelated `.claude/` directory remains untracked.
- Release setup `61891196`: release now installs the same pinned Python 3.14 action
  and schema environment as CI before `make check`. This addresses a missing
  prerequisite; signing, bundle identity and publishing behavior are unchanged.
- RF-01 `8be66c0f`: removed an unread minimum-size local, a literal `&& true` and
  an obsolete commented description. Real eligibility checks retain their order.
- RF-09 `e0be260c`: extracted `optimalWorkspaceHideCorner` into value-only geometry.
  Named exact-corner weighting replaces the vague local `important`. Original
  expression characterization ran first; fixed layouts and 338 offset/display
  comparisons verify the extraction, including bottom-right tie-breaking.
- RF-02 `782dfe75`: removed the empty conditional whose viewport initialization
  is already performed by the following assignment. Separate characterization
  cases passed before removal. Accepted assignments initialize the viewport;
  refused assignments leave keys, ownership and history unchanged.
- RF-07 `4262e469`: `RestartSnapshotState` pairs each pending snapshot with its
  matched windows. There are no independently stored parallel arrays. The persisted
  envelope remains separate and unchanged. A gated identity-query test appends a
  snapshot and triggers the actual expiry transition while restoration is suspended;
  compaction waits for the in-flight reader. A fixed savedAt fixture verifies exact
  encoded bytes. A narrow test-only identity-query override and shared synchronous
  expiry transition make those existing paths reproducible without 30-second sleeps.
- RF-15 `9dca6d96`: overview stores one presentation entry per display, containing its model,
  panel and display identity. Read-only model/panel arrays are derived for existing
  callers. Cleanup no longer zips independently maintained arrays; display focus
  uses the same entry. Existing rapid-reopen tests remain, and new tests cover no
  displays and reopening after a display disappears.
- RF-25 `22607250`: installer `_observe_startup` returns a named observation record;
  `verify` retains report/restoration/rollback decisions. Constants name the existing
  150-attempt limit, three-ready-sample threshold and 0.2-second polling interval.
  Error messages remain strings and annotations remain compatible with Python 3.9.
  New fake-operation tests cover readiness, reset after changed assignments and
  bounded failure polling. The live app is not replaced to test the installer.

## Verification and corrections

The complete baseline, release prerequisite check, bounded-refactor check and
restart-pairing check passed. Characterization checks ran before parking extraction,
empty-conditional removal and restart pairing. Logs are under `.build/`:

- agreed-baseline-check.log
- release-prerequisites-check.log
- parking-characterization.log
- assignment-characterization.log
- bounded-refactors-check.log
- restart-characterization.log
- restart-pairing-check.log
- agreed-final-check.log
- installer-refactor-tests.log

During development, tests caught a fixture assertion requiring unavailable
MonitorViewport equality; assertions were made explicit over its existing fields.
The first envelope expectation used compact JSON; it was corrected to a fixed
fixture of the original pretty-printed bytes before pairing. The installer refactor
initially used annotations unavailable on local Python 3.9 and retained an exception
object instead of its string message. Both were corrected and the existing tests
were retained. These intermediate failures are not classified as pre-existing.

## Limits

A local full check does not establish hosted release success. No tag was pushed to
exercise publishing. Native checks remain for parking across physical displays,
rapid overview interaction during display changes and physical gestures. Build 310
now includes these refactors and passed real-window restart validation below.

Final full gate passed: 1,504 Swift tests, zero failures, plus Python checks.
The focused installer suite passed 21 tests, including saved-report JSON assertions.
Claude reviewed the overview and installer extraction read-only; its identified
serialization regression was fixed before completion. No hosted release run is claimed.

Claude’s final source review confirmed preserved installer and restart semantics.
Its test-gap feedback was addressed: the fixed encoding fixture now includes a
workspace, container, window and restart identity with single-element sets, and
a separate suspended-restore case covers the matched-window write after the await
without expiry. The identity-query hook is restricted to unit-test execution.

## Installed build 310 and tray cleanup follow-up

Build 310 installed with status validated. Restart retained all four surviving
windows' workspace assignments and identical raw layout trees. Native Settings
checks passed for cold/repeated highlighted jumps and navigation away/back;
Configuration fallback opened its editor. Overview rendered cards and closed.
Only one physical display was available. Keyboard/VoiceOver and accessibility
appearance variants remain pending. The Window-menu Settings entry closes at once;
this separate reproduction is queued as UI-09.

UI-03 now uses one recursive separator cleanup after menu assembly, replacing the
leading-only special case. This handles extraction gaps without changing action
identity, order, binding payloads or shortcuts. Tests cover real main/alternate
menus and synthetic nested/all-separator menus. The real-menu test failed against
the original implementation before the fix.

The first separator-check run exposed an incorrect synthetic fixture: AppKit clears
a key equivalent when that item becomes a submenu owner. The fixture now uses a
separate submenu owner so the command shortcut assertion checks a real action.

Final UI-03 gate: make check passed 1,506 Swift tests with zero failures and all
Python checks. git diff --check passed. Installed build 310 predates UI-03.

## Shared Settings descriptors and explicit opening

UI-07 removes duplicated labels and IDs for the 30 indexed controls. SettingsControl
provides each control's stable ID, title and page; typed control initializers feed
those exact values to the existing primitives. Bindings, save closures and control
order are unchanged. Search still uses case-insensitive all-term matching and the
same catalog order. One page-search operation now builds the reference inventory
once and reuses its grouped sections across destinations, including Configuration
fallbacks. The rendered-page regression verifies actual accessibility identifiers
for all indexed targets on their declared pages without configuration writes.
Its first run expected numeric anchor IDs directly; it was corrected for the
existing .value accessibility child convention.

UI-09 replaces SwiftUI's generated scene command with an explicit Window-menu
command that requests Settings through the same model path as the tray. This fixes
both immediate closing on the first open and a blank window after a tray open/close.
The asynchronous launch-suppression close checks again for an explicit request
before closing. Startup suppression and release of closed Settings pages remain.
Tests cover distinct repeated opening requests without configuration writes;
native opening and keyboard acceptance are recorded separately.
