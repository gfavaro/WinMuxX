# AeroSpork Settings ideas and cleanup plan

Status: implemented and installed in signed build 73, 2026-10-16. The user
authorized implementation after the proposal. Automated and CLI checks passed;
visual interaction and physical hot-plug checks remain pending. The scope is all
three remaining ideas: display Settings, a window-rule editor and optional hardware
display selectors, plus an evidence-based cleanup pass.

## Boundaries

- Ordinary shortcuts, sidebar selection and swipes focus a workspace on its owning
  display. Only an explicit action moves it. Keep one workspace on each secondary.
- Reuse existing commands, ConfigFileStore, settings drafts/save feedback, monitor
  ownership and native SwiftUI/AppKit controls. Add no dependencies or IPC changes.
- Keep start-on-main behavior and existing config compatible. Separate live
  placement from persistent assignment constraints; do not turn Bring Here into a
  saved pin or silently change startup defaults.
- Avoid automatic hardware fallbacks, fixed layouts, scrolling workspace layouts,
  broad singleton replacement and abstractions introduced solely to remove a library.
- Preserve custom TOML, rule order, command order, comments and unsupported editor
  shapes. If a structured edit cannot safely preserve a shape, explain it and
  offer the raw editor rather than rewriting it lossily.

## 1. Establish the cleanup baseline

Build a fresh index with the selected Swift 6.4 compiler, including app, CLI,
tests, marketing renderer and window-capture products. Run the existing pinned
Periphery tool and compare findings with whole-repository searches and call paths.
Exclude generated/vendor code from proposed edits; inspect ObjC selectors,
delegate/protocol methods, executable entry points and conditional code manually.
Run in a temporary build location if a clean index is needed, preserving existing
artifacts. Do not equate the scanner's finding count with removable code.

Initial source search and a cached-index Periphery scan both flag:

| Candidate | Evidence and follow-up |
| --- | --- |
| OpenShortcutSettingsButton | Declaration-only View; confirm existing menu/window opening paths before removal. |
| WindowIntentPreviewGridLines | Declaration-only Shape; verify active drag overlays use their current renderer. |
| readMainModeBindingEntries | Wrapper has no named callers; retain the used parameterized readModeBindingEntries helper. |
| projectSwipeGesture | Unattached gesture factory; trace the directly called handlers and preserve actual project-swipe behavior. |
| tabChromeGroupDragGesture | No named callers; verify current tab drag entry points and shared helpers before deleting. |
| Marketing preview components | Several private view subtrees have no incoming use; verify the separate marketing executable before pruning entire unreachable subtrees. |

The cached scan reports 250 AppBundle findings, including 109 assign-only
properties and callbacks with possible framework callers. It also includes stale
ANTLR index entries from before build 72. This is triage evidence, not a current
whole-program proof or a deletion list. Reports are in
`/private/tmp/winmux-unused-scan.json` and `winmux-unused-scan.log` for this session.

Remove confirmed dead declarations in small independent changes. For the excluded
shell experiment, remove its source, commented-out tests, generated standalone
package and grammar-only tooling together if the fresh audit confirms there is no
supported development consumer. Git retains history. Retain notices for any code
still distributed; inspect build/docs references before removing tooling or notices.

## 2. Add display Settings using existing behavior

Add a Displays page in the existing Settings navigation. Show connected displays,
main status, resolution, UUID with a copy button, and current workspace ownership.
Use immutable row snapshots updated on actual display/workspace changes and when
the page opens; no polling, capture work or AX reads in SwiftUI body evaluation.

Provide separate actions:

- **Bring Here:** explicit live move to the selected display, through the same
  existing command/session path as sidebar Bring Here. Cancel has no side effects.
- **Configured assignments:** edit existing saved assignment constraints with
  accurate labels explaining their persistence. These are not one-time moves or
  startup-only defaults. Show unavailable displays without retargeting them.
- Link to or reuse the existing start-on-main control; avoid a duplicate setting.

Validate conflicts before applying. Show the displaced secondary workspace and
use the current replacement policy. Preserve raw workspace identity independently
of its sidebar ordinal/label. A pending edit must revalidate display identity after
hot-plug. Opening the page or selecting a display must never move a workspace.

## 3. Add a window-rule editor

Add Window Rules within the existing Automation page, with a selectable rule list
and native detail form. Support app chooser/bundle ID, app/title regex, workspace
matcher, startup/runtime/any, check-further-callbacks and ordered actions.
Expose existing floating, tiling and workspace-move actions as guided choices.

Use typed command parsing to determine whether actions are safely editable by the
guided form. Preserve arbitrary run strings/arrays exactly; do not split commands
on semicolons or normalize their order. Keep custom rules editable in the raw
editor without silently converting them. Rule edits affect future detections;
they must not replay rules on existing windows.

Implement narrow edits to the selected array-of-tables entry, using current disk
text and ConfigFileStore validation/backups. Detect external changes and stale row
identity; fail safely rather than editing a different reordered/deleted rule.
Keep invalid drafts and save errors visible using the existing settings machinery.

## 4. Add optional hardware selectors

Extend the shared MonitorDescription model and existing command/config parser,
without new commands. Proposed canonical explicit selector:
`hardware:<vendor-id>:<model-id>:<serial-number>` with decimal numeric fields.
Read CoreGraphics identity in the monitor snapshot; unavailable/zero serial data
must not be presented as a unique hardware identity.

Keep UUID the default selector copied/generated by the UI. Hardware selection is
an explicit alternative requiring a unique connected match. Missing or duplicate
matches fail with diagnostics; never fall back to name, resolution, first match
or another display. Do not auto-convert existing UUID assignments or auto-move on
reconnection. Show the option only when meaningful identity is available.

## 5. Simplify the code touched by these features

- Use small page-specific models instead of growing ShortcutSettingsModel into a
  universal settings model. Keep shared draft/save handling where it already lives.
- Reuse ConfigFileStore for disk transactions; do not duplicate write, backup,
  validation, reload or conflict handling for either new editor.
- Share monitor selector formatting between UI, command output and config edits.
  Update stale config-reference text, including missing UUID guidance.
- Consolidate duplicated settings controls only where semantics match; retain
  separate runtime movement and persisted-assignment operations.
- Treat unused parameters, assign-only properties and generic helper wrappers as
  candidates requiring call-site review. Do not delete protocol callbacks or
  migrate hotkey libraries merely to lower dependency counts.

## Validation and delivery

Each stage is independently reviewable. Run focused behavior tests, then one full
`make check` after integration and a signed Release build. Tests should cover:

- Display selection causes no move; explicit destination works with three/four
  displays; Cancel changes nothing; secondary replacement preserves other displays.
- Disconnect/reconnect during an edit, UUID/hardware missing or ambiguous matches,
  invalid IDs, configured-assignment conflicts and unchanged legacy selectors.
- Rule creation/edit/delete/reordering, regex errors, startup flags, custom commands,
  multiline TOML and comments, unknown fields, safe refusal and external-edit conflicts.
- Settings page changes preserve drafts, save failure retains edits, and opening a
  page causes no writes. Keep tests serial until shared fixture isolation is solved.

After code checks, use permitted runtime inspection to validate layout and window
behavior; visual checks require approved Computer Use. Do not bypass a denial.
Before installation, retain a rollback archive and snapshot workspace ownership,
visible viewports and focused window IDs. Restore and compare them after restart.
Report remote CI, real hot-plug and visual checks separately when not performed.
No performance improvement is claimed without measurements; swipe latency remains
a separate priority with its existing physical-gesture acceptance criteria.
