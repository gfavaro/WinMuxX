# Native Spaces: comparison with Dinky 0.22

Reviewed 2026-10-26 against Dinky commit
[`cd1d3ca5c09c9e5599d22a64fc5aebbde4cd483d`](https://github.com/mikker/Dinky/tree/cd1d3ca5c09c9e5599d22a64fc5aebbde4cd483d),
also the remote HEAD when checked. Source was inspected, not executed. Dinky is
MIT-licensed, copyright Mikkel Malmberg; any implementation adapted from it must
retain the [existing license notice](licenses/Dinky-MIT.txt).

The recommendation is to use Dinky as the primary native runtime reference while
retaining WinMuxX's layout engine and optional virtual backend. Our branch currently
has verified native **observation**, not a native tiling MVP. Its stricter identity
checks do not substitute for Dinky's implemented window lifecycle and native writes.

Follow-up implementation now adds scoped discovery, incoming-Space targeting,
WindowServer lifecycle events, a measured topology-only audit, AX classification
into retained trees and per-write ownership checks. Physical native tiling remains
disabled. The table below records the original comparison that led to these changes;
the [assessment](NATIVE_SPACES_ASSESSMENT.md) records current implementation evidence.

| Area | Dinky implementation | WinMuxX branch and decision |
|---|---|---|
| Space discovery | `DinkyPrivate/query.m`: `dinky_displays`, `dinky_current_space_id`; SkyLight display inventory, current ID, type | `NativeSpaces/SkyLightReadOnlyBridge.swift` resolves read symbols dynamically and validates the complete returned topology. Same API family. Keep the narrow bridge and missing-symbol handling. |
| Window membership | `dinky_window_space_id` selects the first `SLSCopySpacesForWindows` result | Our snapshot retains nil, empty and multiple memberships separately. Keep ambiguity explicit; sticky/shared windows cannot acquire an arbitrary layout owner. |
| Per-Space trees | `dinky/Coordinator.swift`: `workspaces[UInt64]`, `key(of:)`, `track` | Keep existing WinMuxX Workspace trees. `NativeSpaceLayouts` associates them with UUIDs, updating session numeric IDs without rebuilding nested layouts. Our host actually renumbered a desktop without changing its UUID. |
| Window discovery | `query.m`: `dinky_space_window_ids`; `WindowModel.swift`: WindowServer inventory plus owner, tags, order and lifecycle | Our diagnostic uses public normal-level inventory plus individual membership queries. It includes many entries that are not manageable windows. Investigate Dinky's Space-scoped candidate queries, then classify through existing AX code; neither inventory alone authorizes tiling. |
| Space-switch work | `Coordinator.onlySwitchedSpaces`, `spacesShown`, `dirty`, `flush` reconcile incoming Spaces and leave hidden dirty trees pending | Adopt this separation. Our current observation rereads the full inventory. Native tiling must refresh the incoming/changed Space and avoid reapplying unrelated displays' layouts. |
| Notifications | One `EventHub` fans out private WindowServer events; public AppKit notifications supplement them | Our observer currently uses public events, with coalescing/generation checks. WinMuxX already has private window-watch callbacks in `PrivateApi/border.m`; reuse/consolidate those owners rather than introduce competing global event state. Validate payloads and failed registrations. |
| Missed notifications | `DisplayModel.start` also polls topology every 500 ms, because some externally posted swipes deliver neither expected notification | Our event-only observer can miss those switches. Before native tiling, benchmark a topology-only audit/transition watchdog; do not poll our full window inventory twice a second. Compatibility with rcmd is still unverified here. |
| Frame scheduling | `DinkyLayout/FrameScheduler.swift`: one queue per app, newest frame wins, bounded retry, cancellation, delayed readback | WinMuxX already has per-app RunLoop jobs, cancellation, WindowMotion and minimum learning. Reuse that implementation; attach native membership/transition authority at its actual queued-write boundary. A snapshot check on the main actor is insufficient. |
| Group overlap and focus | `FrameApplier.raiseIntoOrder`, `raisingKeepsFocus`, `DinkyLayout/Stacking.swift` minimize raises and preserve the front app's key window | Study/adapt this for native tab/accordion presentation. Our virtual engine hides some inactive group windows by corner parking; copying that behavior into native mode can leave windows inaccessible on quit. Native ordering requires actual overlapping-app validation. |
| Native fullscreen | `Placement.space == nil` outside user Spaces; `key(of:)` rejects non-user Spaces | Our eligibility excludes native fullscreen and unknown types. Keep their prior ordinary-Space tree retained; do not invent another tiling column or infer closure from unavailable AX. |
| Mission Control | `MissionControl.update` recognizes a WindowManager overlay by bundle, level and display-sized frame | WinMuxX already uses the corresponding observation in `WindowBorderController`. Reuse that mechanism, suspend native frame/focus/ordering work during transitions, and test each supported OS; the level/window pattern is a heuristic. |
| Navigation | `SpaceSwitching.swift` coalesces requests per display and confirms landing. `DinkyPrivate/switch.m` posts version-specific synthetic Dock swipes and may temporarily move the pointer | Useful reference, but not a public direct-activation API. Evaluate separately before exposing native CLI/sidebar activation. Native gestures need no interception by WinMuxX. Current branch explicitly reports activation unsupported. |
| Lifecycle and automatic moves | `WorkspaceNumbers` manages numbered native Spaces; `Adoption.swift` can move a new window to the previously focused display; `Recovery.moveBack` can return windows to an earlier Space | Do not import these policies. Our requirement gives macOS lifecycle ownership and forbids silent cross-Space moves. Reconcile where macOS places a window; keep explicit movement as a separately verified capability. |
| Persistence | `Recovery.swift` journals original frame, numeric Space ID, PID and first-seen identity; app minimums have a separate store | That journal is not a replacement for WinMuxX's nested layout recovery. Native layout persistence needs its own namespace, UUID identity, existing window recovery identity and conservative handling of missing Spaces. Never load/save virtual `window-state.json` in native mode. |

## Evidence and compatibility

Dinky's `RESULTS.md` contains several different test environments. The initial
September 24 feasibility results came from a SIP-disabled VM; a September 28
addendum records a SIP-enabled M1 Max host with two unequal/offset external
displays. Later notes also record SIP-enabled Space removal. These are valuable
source-reported results, not tests we executed or a blanket guarantee across macOS
versions. Its changelog records further version-specific fixes after that spike.

One particularly relevant finding: a bridged set-current-Space operation changed
reported IDs without reliably changing the visible desktop. Dinky consequently
uses synthetic swipe navigation. This supports our decision not to declare native
activation supported merely because a symbol exists or the active ID changes.

Our executed evidence remains narrower: read-side queries with SIP enabled on
macOS 27.2, two connected displays, one observed user Space-change notification,
and inactive-window membership preservation. Native frame writes, overlapping
window ordering, fullscreen/Mission Control cycles and third-party posted swipes
have not been validated.

## Implementation order revised by this comparison

1. Separate topology invalidation from window discovery. Compute changed displays,
   incoming Spaces and membership changes; keep unaffected trees and focus intact.
2. Integrate incremental window lifecycle through the existing compatibility layer.
   Preserve windows while inactive AX is unavailable; confirm actual destruction.
3. Carry native owner identity and a cancellable generation into per-app frame jobs.
   Validate live membership and process identity at writes, including delayed jobs,
   retries, motion steps and completion/minimum-learning callbacks.
4. Enable the smallest Dwindle/Master/floating MVP only after active-Space-only
   positioning is validated with an exclusive development-manager session.
5. Add native stacking for tabs/accordion with focus-preserving ordering; then native
   layout persistence, sidebar/palette/overview and evaluated navigation capabilities.

This changes the next implementation steps; it does not enable native writes,
install Dinky, move any windows or change the user's configuration.
