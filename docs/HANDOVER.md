# WinMuxX handover — 2026-11-06

The session simplified the tray menu and Settings, added sidebar display movement,
and completed a targeted behavior-preserving refactor. The latest work fixes queued
search/navigation and stale display-target issues. All changes remain uncommitted;
the installed app is build 308 and does not include the latest source changes.

## Current source

- Tray: Arrange Windows groups Dwindle/Master, grouping, balance, join and resize.
  Retile, Fullscreen and Float / Tile Window remain at root, with navigation menus
  inspired by mikker/Dinky. Settings explicitly hides its image on macOS 27.
- Settings: Everyday/Advanced grouping, page search and 30 direct control results.
  Unmapped reference sections fall back to Configuration, including
  `on-window-detected` and `inherit-env-vars`.
- Ordinary page navigation clears stale search targets. Explicit result clicks
  create unique requests. Fields emit a bounds-anchor preference; forms scroll
  when the requested field is ready instead of guessing with Task.yield(). Native
  scrolling correctness still needs desktop validation.
- Sidebar: display ownership labels and Move to Display context actions. New move
  actions carry display UUIDs and resolve them at execution time; missing identity,
  disconnected displays and deleted workspaces report errors. Existing assignment
  and whole-workspace relocation policies remain in use.
- Refactor: typed menu-section references, separate SettingsSearch.swift, reused
  query results, explicit search aliases, clearer recovery mutations and installer
  comparison names. Detailed explanations are in REVIEW_QUEUE.md.
- Agent CLI was tested against the live app: Rex window 373 was floated, queried,
  restored to tiled mode and queried again; workspace 3 was retained.

## Verification and installation

- Latest `make check`: 1,495 Swift tests, zero failures; Python checks passed.
  Full log: `.build/queue-fixes-check.log`. `git diff --check` passed.
- The first new-test build failed because TestMonitor is a value type declared
  with let; fixtures were corrected to var, then the full gate passed.
- Regression coverage includes unmapped search queries, repeated request identity,
  preference reduction and UUID resolution across repositioning, coordinate reuse,
  disconnection, missing UUID and case-insensitive matching.
- Installed build 308 passed installer validation. Build 309 completed before the
  review/refactor/fixes; it was not installed and is now stale relative to source.
- Native validation remains: search to an offscreen control on a cold page,
  repeated clicks, navigation away/back, keyboard/VoiceOver, high contrast, and
  moving populated workspaces between real displays during topology changes.
- No new release build/install was requested for the final fixes. If installing,
  choose a fresh build number (310 or later after checking existing artifacts),
  preserve signing identity, and use script/install_fork.py with a fresh report.
  Build and installation instructions are in HACKING.md and docs/FORK.md.

## Next steps

1. Read docs/REVIEW_QUEUE.md. UI-01/02/04/05/06 are implemented; UI-03 (separator
   normalization), UI-07 (shared search metadata) and UI-08 (native/accessibility
   validation) remain open. Checked items retain their native-validation caveats.
2. Perform the desktop checks above; do not infer scrolling or physical display
   correctness solely from pure model tests. Consider a rendered navigation test.
3. Review the accumulated diff before committing. Preserve unrelated `.claude/`
   contents and generated gitHashGenerated.swift changes; do not reset the tree.
4. Follow repository CONTRIBUTING/AGENTS guidance. No commits or pushes were made
   this session. User prefers continuing authorized work without repeated approvals.

## Entry points

- Sources/AppBundle/ui/menubar/NativeActionMenu.swift
- Sources/AppBundle/ui/settings/{ShortcutSettingsView,SettingsControls,SettingsSearch}.swift
- Sources/AppBundle/ui/sidebar/{WorkspaceSidebarActions,WorkspaceSidebarActionsAdapter,WorkspaceSidebarSnapshot,WorkspaceSidebarWorkspaceSection}.swift
- Sources/AppBundle/ui/sidebar/models/WorkspaceSidebarMonitorScope.swift
- Sources/AppBundleTests/ui/{ActionMenuTest,SettingsRefinementTest}.swift

Use git status for the complete file list; the tree includes earlier edits to
README, docs, recovery, settings previews/shortcut labels and script/install_fork.py.
