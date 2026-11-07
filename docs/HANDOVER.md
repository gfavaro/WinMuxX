# WinMuxX handover — 2026-11-06

Build 312 is built from main but not installed: the installer stopped because the
Mac was locked (`.build/install-312.json`, `blocked_locked`). Build 311 is installed.
Install 312 with `python3 script/install_fork.py --install --app .release/WinMuxX.app
--report .build/install-312.json` once the session is unlocked.

## Since build 310

- UI-03: tray separators are normalized after section extraction (77a8270c).
- UI-07: Settings search uses shared descriptors; rendered coverage checks each
  descriptor exists on its declared page (889788c1).
- UI-09: the Window-menu Settings entry goes through requestWindowOpen, like the
  tray (889788c1). Natively validated on build 311: open, close and reopen work.
- UI-08 fix: control results are selectable sidebar rows and Return in the search
  field opens the first result. Unit-tested; the native check is pending (build 312).

## Next steps

1. Install build 312 and check Settings search with the keyboard only: type a
   query, arrow/Tab through control results and pages, Return in the search field,
   and confirm focus lands on the destination control.
2. Finish UI-08's remaining checks: VoiceOver announcement, Increase Contrast and
   Reduce Motion. Then tick UI-08 in REVIEW_QUEUE.md.
3. Choosing the already-selected control row by clicking does not re-scroll (List
   selection does not change); Return re-scrolls. Decide whether that matters.

## Verification

make check passed 1,510 Swift tests and all Python checks with the UI-08 fix.
Only the built-in display was connected; multi-display behavior remains untested.

## Limitations

Read REVIEW_QUEUE.md for the open queue, REFACTOR_IMPLEMENTATION.md and
REFACTOR_AGREEMENT.md for refactor scope. Preserve unrelated untracked .claude/
contents. Follow CONTRIBUTING, HACKING, TESTING and FORK for checks, direct main
commits and installation.
