# WinMuxX handover — 2026-11-06

Build 313 is installed and installer-validated.

## Since build 310

- UI-03: tray separators are normalized after section extraction (77a8270c).
- UI-07: Settings search uses shared descriptors; rendered coverage checks each
  descriptor exists on its declared page (889788c1).
- UI-09: the Window-menu Settings entry goes through requestWindowOpen, like the
  tray (889788c1). Natively validated on build 311: open, close and reopen work.
- UI-08: control results are selectable sidebar rows; an AppKit search field takes
  ⌘F and opens the first result on Return. Keyboard behavior confirmed on build 313.

## Next steps

1. Finish UI-08's remaining checks: VoiceOver announcement, Increase Contrast and
   Reduce Motion. Then tick UI-08 in REVIEW_QUEUE.md.
2. Choosing the already-selected control row by clicking does not re-scroll (List
   selection does not change); Return re-scrolls. Decide whether that matters.

## Verification

make check passed 1,511 Swift tests and all Python checks with the UI-08 fix.
Only the built-in display was connected; multi-display behavior remains untested.

## Limitations

Read REVIEW_QUEUE.md for the open queue, REFACTOR_IMPLEMENTATION.md and
REFACTOR_AGREEMENT.md for refactor scope. Preserve unrelated untracked .claude/
contents. Follow CONTRIBUTING, HACKING, TESTING and FORK for checks, direct main
commits and installation.
