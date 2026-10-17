# Dinky 0.19 comparison and adoption

Reference: [release v0.19](https://github.com/mikker/Dinky/releases/tag/v0.19),
commit `a0a8d0be40886d71547278c6f57c44fbe76331c0`; compared with v0.18.

The source was reviewed, rather than applying patches across different window
models: Dinky manages native Spaces; WinMuxX parks hidden windows and owns its
workspace tree. Workspace selection must continue to preserve display ownership.

## Implementation checklist

- [x] Hyper/Meh aliases through the existing chord parser and duplicate detection.
- [x] Case-insensitive bundle-ID regex rules, including the Rules editor.
- [x] Bundled CLI on hook/exec PATH, including Finder launches.
- [x] Minimum evidence across distinct requests; invalidate older persisted evidence.
- [x] Replace stale AX elements on their app thread; retry only once on invalid elements.
- [x] Review workspace/drag refresh overhead and disabled-state cleanup.
- [x] Successful command no-ops, retaining explicit failure options and real errors.
- [x] Optional workspace layout defaults with display-specific overrides.
- [x] Settled display topology hook with old/new display counts.
- [x] Regression tests, full checks, signed build and installation validation.

Fixed-grid templates and scrolling remain outside the requested product scope.
Dinky's arm64-only update-feed restriction does not apply to the personal fork:
its build already rejects an update feed and disables automatic updates. No CPU
architecture restriction should be added without inspecting the distributed binary.

## Validation

The final local check passed **1,102 Swift tests and 20 Python tests**. This adds
19 regressions covering aliases/duplicates, matching/editor round trips, callback
environments and coalescing, display layouts, native-element recovery, disabled
drag cleanup, minimum migration, and swipe refresh counts/interruption. Existing
minimum tests were also updated for the stronger evidence requirement.

Signed build 80 was installed; strict/deep signature verification passed. Fresh
before/after snapshots confirmed unchanged config bytes, window/workspace
assignments, populated workspace display/visibility and restored focus. Only the
built-in display was connected for this check. Doctor reported valid config,
granted Accessibility/Screen Capture and a listening raw-touch backend. A clean
shell with only bundled Helpers and system paths resolved the bundled CLI, printed
matching client/server versions and queried all five workspaces successfully.
The exec environment construction is covered by unit tests; `exec-and-forget`
remains a configuration-only command.

Automated geometry/model tests cannot establish physical gesture latency, native
app reopening behavior or visual smoothness.

## Configuration

Aliases expand through the existing parser: `hyper-1` means
`alt-ctrl-cmd-shift-1`; `meh-1` means `alt-ctrl-shift-1`. Duplicate aliases and
expanded bindings are rejected. Existing left/right modifier filtering still applies.

Bundle-ID regexes use `if.app-id-regex` in `[[on-window-detected]]`, also available
in the Rules editor. Regex matching is case-insensitive; an exact `if.app-id` and
regex on the same rule must both match.

```toml
# Root-level callback. Leave empty unless you want an action on docking/undocking.
on-display-changed = 'exec-and-forget echo "$WINMUX_PREV_DISPLAYS -> $WINMUX_DISPLAYS"'

[[on-window-detected]]
if.app-id-regex = '^com\.jetbrains\.'
run = 'layout tiling'

[workspace.1]
layout = 'dwindle'
orientation = 'horizontal'

[workspace.1.display.'Built-in']
layout = 'accordion'
orientation = 'vertical'
```

Workspace table keys are **internal names**, as used by force assignments, not
sidebar positions. Layouts support dwindle, tiles, accordion and tab-group.
Orientation accepts horizontal, vertical and auto. Display overrides inherit
omitted settings from the workspace, then global defaults. Exact selectors
(UUID, hardware, main/secondary and display numbers) take priority over name
regexes; longer regexes take priority, with lexical ordering breaking ties.
Each name regex matches every matching display. These settings change layout
on a move or docking transition; they never move a workspace by themselves.
Manual layout commands survive refreshes until the resolved policy changes.
Removing the workspace's policy restores global defaults on its next layout.
Nested containers and window order are retained.

The topology callback runs after a successful settled display refresh. Repeated
notifications and geometry-only changes do not trigger it; exchanging displays
can trigger it even if the count stays the same. Startup seeds the baseline
without running the hook. Counts are scoped to that callback's command environment.

The signed personal build bundles `Contents/Helpers/winmuxx`, linked to its CLI.
`exec-and-forget` prepends this private directory to the configured PATH, keeping
all configured components and variables. This works when launched from Finder and
with environment inheritance disabled; a missing PATH gets standard system paths.

## Runtime comparison

| Dinky change | WinMuxX decision |
| --- | --- |
| Read only newly visible Spaces; retain hidden dirty trees; snap on arrival | Our explicit workspace navigation already skips a full post-command AX barrier and caches unchanged applied frames. Incoming parked windows already restore directly to their tile without a glide. Swipes now use that same light path; interrupted native refresh requests are preserved. A full reconciliation remains for native creation, destruction, wake and topology changes. |
| Frame-only drag/border updates; coalesced settle work | Existing display-driven drag gates, event-invalidated native frame caches and frame-only WindowServer border following are retained. No new reconciliation timer or polling loop is added. |
| Disable borders and drag tracking while disabled | Existing drag/preview cancellation is retained; disabling now also cancels motion/frame jobs and clears border windows immediately. |
| Replace stale AX elements | Window operations record invalid-element failures, refetch and retry once on the owning app thread. This covers optional reads, writes and raises without adding a liveness read before every operation. Full enumeration also accepts a changed AX element for an existing native ID. Logical workspace nodes are retained. Timeout/cancellation does not cause this retry. |
| Confirm minima across different asks | Keep our two settled samples, 32-point refusal threshold, position checks, animation/fullscreen/minimize guards and successful-smaller-resize invalidation. Require two distinct requests for each axis as well. App minimum storage moves to evidence version 2; legacy frozen minimum fields are ignored without discarding the tree. |
| Edge command success | Move already succeeds with stop/default boundary behavior; explicit fail remains a failure. Join/resize now report successful no-ops when no tiled neighbor/split can change. Floating operations and missing targets remain errors. |
| Layout settings per display | Reuse existing monitor selectors and layouts. Retain nested tree structure, order and display ownership. No grids or scrolling. |
| Hyper/Meh and app-ID regex | Extend the existing parser/editor; no extra binding or rule engine. |
| Display topology hook and executable PATH | Use settled runtime-owned topology state and the existing command pipeline, including when native refresh events coalesce. Bundle a CLI alias in a separate directory to avoid the app/CLI case collision. |
| Release architecture metadata | Personal releases have no automatic update feed; no applicable metadata change. |

The 30-navigation regression asserts operation counts, not a physical latency
improvement. A new finger-swipe measurement is still needed to assess end-to-end
latency. Slack reopen, Terminal resize, actual dock/undock and native Settings
interaction require manual validation beyond the fake AX/model tests.
