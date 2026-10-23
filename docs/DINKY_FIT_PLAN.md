# Dinky ideas that fit WinMuxX

Evaluation date: 2026-10-22. Status: proposed implementation plan; no runtime
changes are made by this review. WinMuxX baseline:
`44fe40fd1a0e7216868a1f9aef8dd8c818eb48fa`.

Implementation agents: follow [the execution checklist](DINKY_EXECUTION_PLAN.md).
It breaks this evaluation into ordered tasks with file boundaries, verification
commands and completion evidence. This document explains the product decisions;
the checklist defines how to execute them.

## Recommendation

Keep WinMuxX's projects, sidebar, persistent workspace names, tab groups and
explicit display ownership. The most useful next Dinky adaptations are better
feature discovery, editor assistance and visible shortcut health. Most of its
headline tiling features already exist here. Reliability work should start from
a reproduced gap rather than assume every Dinky fix is missing in WinMuxX.

Dinky uses native Spaces; WinMuxX owns simulated workspaces and parks hidden
windows. Ordinary selection must continue to focus an already-visible workspace
on its owning display. Moving it remains explicit. Layout policies must never
silently relocate workspaces or discard nested containers and tab groups.

## Evidence and comparison

Reviewed Dinky's current [README](https://github.com/mikker/Dinky/blob/main/README.md),
[changelog through 0.21](https://github.com/mikker/Dinky/blob/main/CHANGELOG.md),
[concepts](https://github.com/mikker/Dinky/blob/main/docs/concepts.md),
[layouts](https://github.com/mikker/Dinky/blob/main/docs/layouts.md) and
[configuration guide](https://github.com/mikker/Dinky/blob/main/docs/configuration.md).
These main-branch references can change; this is a dated evaluation, not a claim
that later releases have been audited. Earlier source-level adoption records are
[0.19](DINKY_019_ADOPTION.md), [0.20](DINKY_020_ADOPTION.md) and
[0.21](DINKY_021_ADOPTION.md), with pinned upstream references.

| Dinky idea | WinMuxX evidence / fit | Decision |
| --- | --- | --- |
| Dwindle, master and stack toggling | Existing layout engine, `WorkspaceLayoutCommand.swift`, `SwapWithMasterCommand.swift`, master regressions and 0.21 migration | Already available; explain visually |
| Layout policies by display | `WorkspaceLayoutConfig.swift` and 0.19 adoption; retains workspace ownership and nested trees | Already available; add docking recipe |
| Rules, Hyper/Meh, modifier sides, hooks | Existing config parser, `SideFilteredHotkeys.swift`, Automation settings and 0.19 adoption | Already available; add practical recipes |
| Menu actions showing shortcuts | Existing native action catalog | Retain; improve links to relevant help |
| Recovery, app-activation exclusions, PiP filtering, AX timeouts | 0.20 adoption and reliability guides | Retain; validate native edge cases |
| Short concepts guide and illustrated layouts | Current README is long; docs index mixes current guides and historical reviews | High-value documentation work |
| TOML editor completion via JSON Schema | Dinky documents a Taplo schema directive; no WinMuxX configuration schema found in resources/docs | Add a WinMuxX-specific schema after inventory |
| Visible failed-shortcut state and recovery | `HotkeyBinding.swift` reports side-filtered installation failure with a message asking for reload; `SideFilteredHotkeys.swift` re-enables an existing disabled tap | Extend health reporting; distinguish failure to create from tap disable |
| Symlink-safe configuration | `ConfigFileWatcher.swift` watches link/target paths; `ConfigFileStore.swift` resolves targets for edits, but bootstrap uses the supplied URL | Audit dangling-link/bootstrap and retargeting cases; do not label all symlink support missing |
| Drag continuity, crowded resizing, CLI argument preservation | Dinky 0.20 lists fixes; WinMuxX has its own drag, resize and argument implementations/tests | Reproduce against WinMuxX before scheduling fixes |
| Scrolling and reserved fixed-grid layouts | Explicitly excluded by current roadmap; would require separate product and layout decisions | Excluded from this plan |
| Native Space creation/switching and its OS-specific workarounds | Different workspace architecture | Do not port |
| Automatic updates and Dinky installation requirements | Personal fork has its own signing, releases and disabled upstream updates | Retain fork policy |

The `fixed` value reported by WinMuxX's workspace queries describes ordinary
tiles/accordion/tab roots; it does not mean Dinky's reserved-cell grid is supported.

## Delivery 1: make existing capabilities easy to learn

Priority: first. Relative effort: medium; runtime risk: low.

1. Add `QUICK_START.md`: installation link, Accessibility, first two windows,
   selecting a workspace, opening Settings and running `winmuxx doctor`. Explain
   that screen capture is optional for visual previews. Use actual fork commands
   and no assumed default global shortcut.
2. Add `CONCEPTS.md`: project → workspace → container → window, display ownership,
   internal names versus sidebar labels, persistence and app activation. Include
   a two-display example where selecting a workspace focuses its current display,
   and explicitly moving it changes ownership.
3. Add `LAYOUTS.md` with original SVG diagrams for sequential dwindle splits,
   master plus tiles/accordion, tab groups and a lone ultrawide tile. Explain
   `workspace-layout dwindle master`, `layout tiles accordion`, floating/tiling,
   `swap-with-master`, resizing and reset behavior. Include focused-tiled-window
   prerequisites and what each command preserves.
4. Add `RECIPES.md`: coding on an ultrawide, laptop/docked layout policies,
   floating utilities, activation exclusions, modifier sides for typing accented
   characters, and hooks using the bundled CLI. Each example names its TOML
   location, expected result and how to undo it. Do not reuse Dinky's incompatible
   `[hooks]`, `[[rules]]` or workspace-count syntax.
5. Add a task-oriented command guide backed by
   `Sources/Common/cmdArgs/cmdArgsManifest.swift` and actual `--help` output.
   Explain workspace/container/window scope before enumerating flags. Keep the
   CLI parser authoritative; avoid a separately maintained command inventory.
6. Give README a short entry path to these guides. Keep migration and adoption
   reports under reviews/history. Add a user-facing changelog with migration
   notices, distinguishing released versions from unreleased changes.

Acceptance: validate every runnable command/config fragment against WinMuxX's
parser or CLI help, check relative links, inspect SVGs at narrow and wide sizes,
and walk the quick start in the app. Do not claim physical interaction was tested
from parser tests. Update the old 0.20 command examples or label each obsolete
block locally so readers cannot miss the 0.21 migration notice.

## Delivery 2: configuration completion and discoverability

Priority: second. Relative effort: medium; compatibility risk: medium.

Build a field inventory from `config/parseConfig.swift`, the config types,
`resources/default-config.toml` and `ui/settings/ConfigurationReference.swift`.
Add a versioned JSON Schema for TOML editors, with descriptions, enums, defaults,
numeric bounds and dynamic workspace/display/mode keys. Support both accepted
forms of options such as `follow-app-activation`, per-monitor values and legacy
aliases. Treat parser-dependent semantic checks as runtime validation.

Start with a checked-in schema and documented local use. Only add a remote
`#:schema` directive once its published URL exists and is checked. Default-config
updates must not rewrite existing user files solely to insert the directive.

Acceptance: valid fixtures accepted by the parser remain accepted by the schema;
unknown keys, wrong types and invalid enums are rejected where the parser rejects
them. Cover quoted workspace/display names, regex rules, array-of-table rules,
legacy keys and defaults. Verify completion in a real TOML editor. Add drift
checks between the inventory, reference and schema without pretending JSON Schema
can validate arbitrary command strings or every cross-field constraint.

## Delivery 3: actionable shortcut health

Priority: third. Relative effort: medium; input-handling risk: medium/high.

Inventory Carbon hotkeys, modifier taps, sequences and side-filtered handling
before changing recovery. Report healthy, partially unavailable and unavailable
states from their existing owners. Show a persistent, accessible native menu
status and the same detail in `doctor`; specify which bindings are affected.
Keep workspace/mode indicators readable and clear the warning after recovery.

Use permission/app-activation/configuration events to retry installation. If an
event cannot cover the failure, use a bounded retry with backoff only while
unavailable; cancel it on shutdown or when no affected bindings remain. Preserve
existing tap-disabled recovery and mode/key-release state handling. Avoid a
permanent polling loop or replacing the shortcut engine.

Acceptance: injected creation failure followed by success; repeated notifications
create only one tap/source; timeout recovery clears consumed-key state; mode
changes and config reloads cancel obsolete retries; healthy Carbon bindings stay
usable during a partial failure. Confirm native permission-grant recovery,
ordinary typing, modifier-side behavior and menu accessibility separately.

## Delivery 4: close demonstrated reliability gaps

Priority: alongside existing roadmap validation, before any affected release.
Relative effort: small per reproduction; fixes depend on findings.

| Scenario | Starting points | Acceptance |
| --- | --- | --- |
| Dangling config link, target created later, link retargeted, atomic target save | `ConfigFileStore.swift`, `ConfigFileWatcher.swift`, `ConfigBootstrapTest.swift`, `ConfigFileWatcherTest.swift` | Link retained, intended target watched, invalid/missing config retains last valid runtime state, explicit reload errors actionable |
| Window opens/closes or display area changes mid-drag | Mouse drag subject, layout frame-write gates, `MouseDragSubjectTest.swift` | Dragged window stays under pointer; dropping in its original slot does not become an unintended resize |
| Ten or more siblings after flatten, keyboard resize | `ResizeCommand.swift`, `ResizeCommandTest.swift`, minimum-size fitting | No negative/nonfinite frames, disappearance or ratio corruption; impossible resize follows existing no-op semantics |
| Both quote types and leading combining characters in CLI arguments | CLI transport, `Common/cmdArgs/splitArgs.swift`, argument tests | Exact argument boundaries and bytes survive client/server transport |
| Dock/menu-bar geometry changes and rapid navigation on two displays | Monitor observer, workspace assignment, existing topology tests | Tiles fit usable space; each selection preserves display ownership; latest intended focus wins |

For each row: identify existing coverage, add a regression only for a meaningful
uncovered case, reproduce it, then make a separate fix if needed. Native Spaces
workarounds from Dinky do not establish a defect in WinMuxX. Keep physical swipe
latency, dock/undock, recovery and accessibility checks in the existing
[roadmap](ROADMAP.md) and [release validation](RELEASE_VALIDATION.md).

## Execution and completion

Deliver docs first, schema second, shortcut health third. Reliability reproduction
can accompany those deliveries; confirmed data-loss or input failures take
priority. Each delivery should be independently reviewable and reversible. Use
existing Swift/Python checks for code changes and record local automated results,
remote CI and native manual checks separately. No build, installation or runtime
test was performed for this documentation-only evaluation.

Success means users can discover and use the existing layouts without reading
adoption reports, editors help write valid WinMuxX configuration, unavailable
shortcuts explain their state and recover, and regression evidence closes actual
gaps. Projects, tabs, workspace identity and explicit display moves remain the
product constraints throughout.
