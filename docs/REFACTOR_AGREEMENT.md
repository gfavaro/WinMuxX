# Codex–Claude refactoring agreement — 2026-11-06

Codex discussed the audit with Claude Code in three read-only rounds. Claude
independently checked roughly a dozen findings, challenged the initial priorities,
and explicitly confirmed agreement after the corrections below. This is the
agents' agreed recommendation, not authorization to implement, commit or publish.
The discussion did not change production code or run builds/tests/installations.

## Agreed sequence

0. Review and validate the current uncommitted changes and establish a separate
   baseline commit through the normal repository workflow before layering refactors.
   This is a prerequisite recommendation; no commit was made in this discussion.
1. Fix release prerequisites separately: copy or share CI's pinned Python 3.14 and
   schema-venv setup before release's `make check`. A fresh checkout lacks the
   required interpreter. Source inspection confirms this; no release tag was run.
2. RF-01: remove the unused minimum-observation variable and literal `&& true`,
   preserving every real condition and its evaluation order.
3. RF-09: characterize the current parking-corner expression for side-by-side,
   stacked, offset and tie layouts, then extract the pure function. Preserve exact
   corner-probe weighting, strict `<` comparison and bottom-right tie behavior.
4. RF-02: remove the empty conditional only with separate tests for accepted
   assignment initialization and rejected assignment non-mutation.
5. RF-07: characterize restart restoration before pairing snapshots with matches.
   Cover a restore suspended across AX work while snapshots are appended,
   compaction deferred during in-flight restoration, and expiry during a restore.
   Use a controlled clock or safely bounded fixtures; the expiry task is skipped
   under isUnitTest, so a deliberate test seam may be needed. Compare persisted
   bytes with fixed timestamps and deterministic inputs. Migrate one operation at
   a time and preserve the existing on-disk format.
6. RF-15: pair overview model/panel/display entries after restart pairing has
   settled. Exercise rapid dismiss/reopen, zero panels and display removal.
7. RF-25: split installer observation polling from decisions, using fake operations
   only. Keep restoration, rollback, focus-detection and status-report contracts.
8. RF-18 remains a later option alongside expanded recovery tests.

Each implementation step needs relevant checks and the repository's `make check`.
Native checks must be reported separately: display movement/disconnection,
relaunch with windows open, and rapid overview interaction as applicable.
Do not publish a tag merely to validate workflow YAML without user authorization.

## Corrections established during discussion

- RF-02's empty body still evaluates a mutating lookup:
  `visibleWorkspace(for:)` ensures a viewport exists. The subsequent
  `setActiveWorkspace(_:on:)` ensures the same viewport ID, so deletion may be
  valid, but it is policy-sensitive. The rejection guard runs before both;
  rejection must not create a viewport that was previously absent.
- RF-13's Bring Here target is scope-based and coordinate-derived
  (`monitor:<x>,<y>`), with a focused-display alias. Move to Display resolves UUID.
  Their missing-target behavior also differs: Bring Here returns silently, while
  Move to Display reports an error. Preserve both paths. Share at most the
  assignment-error text; do not introduce a shared relocate-and-focus abstraction.
- RF-24 already has a protocol capability requirement and per-command overrides;
  the conservative default whitelist is not evidence of a missing metadata system.
- RF-09's weighting has a purpose: emphasize the exact-corner probe. Name it rather
  than describe it as unexplained. This remains extraction, not a new algorithm.
- The thirty original findings are candidates, not thirty necessary improvements.
  Higher-risk proposals need characterization before they can be called
  behavior-preserving in practice.

## Deferred or rejected for the present plan

- RF-24: no command-descriptor redesign; keep unknown commands on full refresh.
- RF-13: no shared relocate-and-focus helper; selection remains distinct.
- RF-05: defer the broad Settings dependency-injection change until current UI
  changes are desktop-validated and established as a baseline.
- RF-06 and RF-30: use UI-07 and UI-03 as the implementation trackers; the audit
  entries are cross-references, not additional tasks. Menu building and separator
  concerns are related, but observable separator cleanup must be explicit.
- RF-16, RF-26, RF-27 and RF-21's Result migration: defer low-value churn.
- RF-28: benchmark first; do not optimize based on speculation.
- RF-08: defer scheduler restructuring until restart pairing has settled.
- Keep the removed rectangle preset's parse/error compatibility and main-mode
  validation trigger. RF-04 may rename validation and remove unused parameters.
- Keep DockSwipeTracker's explicit state machine, the bounded subscriber queue,
  native/AppKit border fallbacks, distinct symlink-resolution semantics, refresh
  generations and committed Settings-save lifetime.

## Evidence

- Original findings: [REFACTOR_AUDIT.md](REFACTOR_AUDIT.md).
- Actual review coverage: [REFACTOR_AUDIT_COVERAGE.csv](REFACTOR_AUDIT_COVERAGE.csv).
- Claude's responses: [CLAUDE_AUDIT_DISCUSSION.md](CLAUDE_AUDIT_DISCUSSION.md).
- This agreement does not expand the original coverage claim: 10,838 lines were
  inspected in detail; the whole-tree scan is not a completed human review.
- Claude Code conversation: `5a655cd2-539f-4b65-98c1-42b62a9be0e1`.
