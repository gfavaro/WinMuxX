# Scrolling workspaces validation

The implementation is on `feat/scrolling-workspaces` in the separate
`WinMuxX-scrolling` worktree. Master and Scrolling are workspace arrangements;
existing top-level groups remain intact as panes/columns, including nested splits,
tabs and accordion groups. Entering an arrangement wraps an atomic root without
rewriting its descendants. Returning to Dwindle retains the live organization.

Luna implemented the first completion pass. Its session ended at a usage limit;
the parent reviewed and completed the remaining integration and verification.

| Plan area | Implementation and automated evidence | Status |
| --- | --- | --- |
| Geometry | One pure geometry result drives rendering, focus, minimap and scrolling metrics. Fitting strips center; overflowing strips clamp; minimum extents, gaps, 25-point gutters and actual display-wall adjacency feed physical parking. `WorkspaceArrangementRegressionTest`, `MasterLayoutTest`. | Automated checks pass; native containment pending |
| Mode transitions | Central transitions preserve atomic tab/accordion roots, nested groups and manual mode on refresh; empty workspaces accept mode changes. Legacy Master snapshots migrate without losing groups. `WorkspaceLayoutCommandTest`, `MasterLayoutTest`, `ScrollingWorkspaceStateTest`. | Automated checks pass |
| Commands | Horizontal focus uses column MRU; vertical focus/wrap and moves stay in the column. Shared-column extraction works at both strip ends; single columns swap; joins adopt the adjacent width. Width/smart resize uses content geometry and does not accumulate minimum-swallowed requests. Generic column layout preserves width; preset cycling handles closely spaced values. | Automated checks pass |
| Insertion and focus | Existing tab preference precedes adjacent-column insertion; binding does not change background focus or offset. Gesture ownership suppresses focus reveal and pointer focus. Parent-relative attached-sheet geometry is cached and revealed without adding a column. | Binding/focus tests pass; native sheets and pointer behavior pending |
| Gestures | Initial modifiers, pointer workspace/display, offset and owner epoch are latched. Option routes remain separate from plain swipes and overview. Tracking uses incremental clamped displacement, responds immediately to reversal and bypasses per-window easing. Release uses the shared scalar spring and minimum reveal; Reduce Motion settles immediately. Invalid/cancelled streams cannot restart until lift. Old settling callbacks cannot override a newer explicit focus. `ScrollingGestureTest`, `WorkspaceGestureRouterTest`, existing swipe/overview suites. | Automated checks pass; physical feel pending |
| Native adapters | Logical/physical frames stay separate from inactive-workspace parking. Concealed columns suppress chrome and minimum learning. Coalesced tracking writes cancel on ownership changes. Native ordering uses AXRaise without application activation or focused/main attribute writes, and only refreshes when order/visibility changes. `ScrollingWindowOrderingTest` checks the ordering policy. | Adapter compiled; real overlapping-window gate unverified |
| Recovery and movement | Snapshots retain optional widths, viewport offset, stable identity plus the snapshot-to-live anchor mapping and relative placement. Live moves/size changes rebase the viewport. Tests move a populated workspace between unequal simulated displays and back, retaining groups, tabs, floating parentage, project/identity and an unaffected third display. | Automated checks pass; physical display moves pending |
| Configuration and Settings | TOML-backed column width/presets, gesture enable/sensitivity and minimap controls use the existing save queue. Displays settings selects workspace mode. Schema accepts finite positive sensitivity; help, command registry, agent arrangement adapter and current configuration documentation agree. This checkout contains no standalone shell-completion source to regenerate. | Parser/schema and full repository checks pass |
| Minimap | Proportional tiles, app icons/titles, viewport and focused accent; horizontal scrolling maintains at least 32-point nonoverlapping targets. Explicit toggle holds it open, arrows/Return select, Escape dismisses; hover/pan hold and 1.5-second idle dismissal remain. Callbacks check the displayed workspace epoch/topology. Offscreen keyboard/selection, geometry, lifetime and light/dark rendering tests pass. | Automated checks pass; native key-panel/focus behavior pending |

On 2026-10-25 the serial focused command executed **60 tests, zero failures**:

```sh
swift test --force-resolved-versions --no-parallel \
  --filter 'Scrolling|WorkspaceArrangementRegressionTest|WorkspaceGestureRouterTest|WorkspaceLayoutCommandTest|MasterLayoutTest'
```

`make check` passed **1,398 Swift tests**, **51 Python tests**, schema validation
with **13 shared fixtures / 50 static parser keys**, and pinned dependency
resolution. `git diff --check` passed. Local logs are in
`.build/scrolling-validation/` (ignored build artifacts).

`make fork-build BUILD_NUMBER=138` also passed. The signed artifact is
`.release/WinMuxX.app`; strict/deep code-signature verification passed using the
existing `WinMuxX Local Code Signing` identity and `com.gfavaro.winmuxx` bundle ID.
It was not installed.

Native validation is separate and is **not complete for this revision**. The
installed app remains version 0.5.7 build 137; it does not establish the behavior of
these changes. Only the built-in Retina display was connected at the read-only
inventory check. No personal TOML, signing identity, recovery data, or unrelated
original-checkout changes were edited. No commit or push was made.

Remaining native release gates:

- Two real overlapping application windows: ordering, key-window preservation,
  no app activation, edge-preview clicks and containment at adjacent displays.
- Slow/fast Option pans, reversal, repeated settling interruption, stationary
  pointer behavior, unchanged plain workspace swipes and vertical overview.
- Browsers, terminals, Finder, Preview, delayed/restrictive resizing, sheets,
  minimize/restore, native tabs and both fullscreen paths.
- Move a populated workspace between unequal physical displays and back;
  horizontal/vertical/offset arrangements, disconnect/reconnect, sleep/wake.
- Restart recovery with real windows, width/order/tab/anchor retention; minimap
  keyboard/Escape without activation, accessibility appearance and settled idle work.

An application minimum width larger than its owning physical display cannot be
fully contained without violating that minimum. Geometry preserves its minimum
and applies the existing wall/edge parking policy; the OS's actual clamping for
that case remains a native limitation to validate, not a guarantee from tests.

Pinned groups, minimap drag reordering, free-scroll coasting and native Spaces
migration remain deferred. Automated success does not satisfy the native release
gates above; this branch is not yet certified for merge/release.

## Installation after user authorization

Build 138 was subsequently installed and launched at the user's request. The
installer report is `.release/validation-build138/install-report.json` with status
`validated`; a ZIP rollback archive of build 137 and private recovery/state
backups are retained alongside it. Strict/deep signature verification passed.
All eight managed windows retained their workspace assignments; populated
workspace mode/project/container summaries and the personal configuration hash
matched before/after. The installer restored the original focus. Doctor confirmed
valid configuration, existing Accessibility/Screen Recording permissions and a
listening raw-touch source. These are installation/startup checks; the broader
physical gesture and multi-display release gates above remain unverified.

## Minimap presentation correction

After build 138, the user reported that the minimap was worse than build 137.
Visual inspection reproduced a coordinate-system regression in the new scroll
canvas: tiles were shifted below the viewport outline, and the reduced tile
height clipped labels. The canvas now uses the same top-left coordinates as the
map, with the original 58-point tile height. Overflowing maps follow the workspace
viewport during navigation; hover and explicit keyboard navigation retain manual
control. Dismissal resets this presentation state for the next workspace.

Nine focused minimap tests pass, including scroll position, alignment, label
space, dense hit targets and explicit keyboard selection. Light/dark rendering
fixtures now use a plain background host rather than NSBox, whose content layout
was clipping the preview itself; they also assert that tiles actually render.
`make check` passes 1,399 Swift tests, 51 Python tests and schema/dependency checks.
This is a presentation correction; workspace and gesture policy are unchanged.

Signed build 139 was built and installed for the minimap correction. Its installer
report (`.release/validation-build139/install-report.json`) is `validated`;
strict/deep signature verification passed, all nine current windows retained their
assignments, workspace mode/project/container summaries matched, the config hash
was unchanged, and original focus was restored. Light/dark preview images and
recovery/rollback backups are retained in that private validation folder.

## Minimap proportions

The user then reported that window sizes looked wrong. The previous map scaled
horizontal extents to the full panel width while giving every tile a fixed height,
so a lone window appeared as an extremely wide card. Geometry now uses a single
scale for width and height, preserving column and viewport aspect ratios. A short
strip is centered inside the panel. Narrow columns grow the preview row uniformly
to retain 32-point targets; the document scrolls horizontally if necessary. Panel,
canvas, viewport outline and footer use the resulting row height.

Ten focused minimap tests pass, including a lone-window aspect-ratio regression,
relative widths, dense targets, alignment and keyboard selection. Light/dark
renders were inspected. `make check` passes 1,400 Swift tests, 51 Python tests and
schema/dependency checks. This changes only minimap presentation.

Build 140 was signed, installed and validated for the proportion correction.
All ten current windows retained their assignments, populated workspace summaries
matched, the personal configuration hash was unchanged, and focus was restored.
The installer report, rollback/recovery backups and light/dark renders are under
`.release/validation-build140/`. Strict/deep installed-signature verification passed.
