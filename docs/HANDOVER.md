# WinMuxX handover — 2026-11-06

Build 310 is installed and installer-validated. Agreed refactors were committed
and pushed through 9b7be36f before that build. The subsequent UI-03 tray separator
cleanup is described below; build 310 does not include that cleanup.

## Implemented work

Tray navigation uses typed section references; Settings hides its icon on macOS 27.
Settings search includes Configuration fallbacks, clears stale navigation targets,
and scrolls when the target's layout anchor is ready. Sidebar Move to Display
resolves a captured display UUID at execution and reports unavailable targets.

The agreed refactors cover release Python/schema setup, unused minimum-observation
code removal, pure parking geometry, redundant viewport initialization removal,
paired restart state, paired overview presentation entries and installer polling
observations separated from validation policy. Read REFACTOR_IMPLEMENTATION.md for
rationale and REFACTOR_AGREEMENT.md for deferred scope. The audit is targeted,
not a completed line-by-line correctness review of every file.

UI-03 normalizes leading, adjacent and trailing separators recursively after menu
assembly. Commands retain their identity, ordering, shortcuts and payloads. The
real-menu regression failed against the old implementation before the fix.

## Verification

Before build 310, make check passed 1,504 Swift tests and Python checks; the focused
installer suite passed 21 tests. Installation report: .build/install-310.json.
Four surviving windows retained workspace assignments and identical raw layout
trees across restart. Native overview open/close, Settings cold/repeated highlighted
jumps, navigation away/back and Configuration fallback passed without config edits.

UI-03 logs: .build/separator-before.log reproduces the original defect;
.build/separator-final-check.log holds the final full gate. The first new synthetic
fixture incorrectly assigned a shortcut to a submenu owner; AppKit clears it, so
that fixture was corrected to keep the command and submenu owner separate.

## Remaining queue and limitations

Read REVIEW_QUEUE.md. UI-07 (shared search metadata) and UI-08 (keyboard/VoiceOver
and accessibility validation) remain open. UI-09 records that the Window-menu
Settings entry closes immediately, while opening Settings from the tray works.
Trace launch suppression/open-request semantics before fixing it.

Only the built-in display was connected. Physical workspace movement, topology
changes and multi-display overview behavior remain untested. No release tag was
pushed. Preserve unrelated untracked .claude/ contents. Follow CONTRIBUTING,
HACKING, TESTING and FORK for checks, direct main commits and installation.

Final UI-03 gate: make check passed 1,506 Swift tests with zero failures and all
Python checks. git diff --check passed. Installed build 310 predates UI-03.
