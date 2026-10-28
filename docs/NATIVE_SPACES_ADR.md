# Native Spaces ownership boundary

Status: experimental observation plus separately opt-in native tiling implementation;
physical tiling validation remains pending.

macOS owns native Space identities, visibility, membership and lifecycle. WinMuxX's
existing Workspace trees own layouts. Those responsibilities must remain separate:
the virtual backend currently couples membership to hiding and recovery, and merely
turning off corner parking would leave creation, pruning and assignment active.

`WorkspaceBackendState` belongs to `WinMuxRuntime`. Its capabilities gate lifecycle,
parking and virtual recovery. Virtual remains the default with its existing trees,
layout algorithms, display policy and commands. Native observation has none of the
virtual mutation capabilities. This deliberately avoids a large asynchronous
protocol imposed on synchronous geometry and command consumers.

`NativeSpacesObservation` serializes event-driven reads with one pending replacement.
An event revokes the current snapshot immediately. Owner-scoped generation tokens
reject superseded results, failures and completions after stopping. Read failure
suspends native observation; it never enables virtual management as a fallback.

Following the Dinky comparison, native observation also subscribes to WindowServer
lifecycle events and audits topology every 500 ms (every 5 s after 10 s without input while
WindowServer events are subscribed). Unchanged audits perform no
window discovery. Reads target incoming Spaces for a Space-only switch; coalesced
window/application work retains its broader current-Space scope. Optional scoped
query failure falls back to the existing read-only inventory, never virtual parking.

AX classification may populate existing trees in observation mode. Its asynchronous
registration leases are revoked by every new observation, independent of timestamps.
Individual removal needs an explicit close notification, not a Space departure or
an unavailable AX/bounds read. Virtual recovery, focus/drag callbacks and detection
commands are bypassed. No runtime frame permits are installed in observation mode.

`NativeSpaceWriteAuthority` supplies revocable per-job permits; queued frame writes
check generation, live display/Space identity, PID/launch identity and on-screen
state. Standard and animated AX paths recheck before each write. Already-dispatched
AX calls cannot be recalled, so this is not an atomic WindowServer/AX transaction.
Actual native positioning and delayed-app races remain separate validation gates.

`NativeWorkspaceInventory` retains stale data for diagnostics separately from the
current observation. Numeric IDs are session data. UUIDs supply namespaced recovery
keys when available; missing or duplicate UUIDs cannot justify guessed restoration.
Shared desktop topology is observable without inventing independent layout owners.
Membership observations are not frame-write permits: native tiling still needs
fresh membership checks at native operations and transition cancellation.

Rejected alternatives: replacing the layout engine with a generic backend graph;
pretending native Spaces are virtual slots; using display order or desktop numbers
as recovery identity; automatically synthesizing keyboard input when activation
is unsupported. These either duplicate behavior or conceal ownership failures.

Backend changes require restart initially. Native observation does not read or write
virtual recovery. The first native tiling milestone must add separate persistence
and protect inactive/unknown/fullscreen windows before any automatic frame writes.
The tiling opt-in reuses shared Dwindle/Master geometry with presentation-only child
filtering. Concealed native windows keep their tree membership and width/share
preferences. Native persistence uses its own versioned UUID-keyed file and the shared
frozen-tree codec, bypassing virtual monitor assignment and recovery. Restoration
requires a complete unique match within the owning Space; incomplete or unsupported
records are retained, never replaced by a partial autosave. Private APIs remain
read-side only; physical positioning uses guarded existing AX operations.

Native creation/deletion, cross-display moves, whole-Space relocation and project
mapping remain explicit unsupported capabilities.

Cross-Space window moves were adopted at the user's request, reversing the earlier
exclusion of symbol-table scanning: `NativeWindowSpaceMover` resolves SkyLight's
unexported bridged-operation dispatcher from its symbol table and dispatches
`SLSBridgedMoveWindowsToManagedSpaceOperation` (Dinky's approach). A synthetic
title-bar drag was rejected as visible, slow and unusable without a standard title
bar. Resolution happens once and fails closed; moves require tiling, are confirmed by
membership reads, and rules never move pre-existing windows at startup. Projects are disabled in native
mode (option B): virtual projects stay untouched instead of gaining a second,
UUID-dependent hierarchy whose reboot stability is unverified.

Activation was revisited after user testing showed the gap: with no navigation, an
unchanged configuration's `workspace` bindings captured keys and then failed. Native
`workspace` now posts a synthetic Dock swipe (Dinky/mimi, macOS 27) behind
`NativeDockSwipe`, chosen over posting Control-number keystrokes, which depend on
optional Mission Control shortcuts and fail silently when those are off. It is the
only synthesized input, used only for explicit commands, confirmed by topology reads
and reported when it does not land. Bindings the backend cannot run are no longer
registered.

WinMuxX's own three-finger workspace swipe and upward overview gesture stay off in
native mode, whatever the config says: they activate workspaces through the virtual
model, and macOS already owns Space gestures. The Option scrolling pan is unaffected.

With native tiling on, WinMuxX adds the desktops `persistent-workspaces` numbers
when macOS has fewer (the highest numeric entry is the count). Each new desktop goes
to the display `workspace-to-monitor-force-assignment` names for its number, else the
main display. It creates one desktop per topology read, after the displays have been
stable for a second, and stops on a failure until the config reloads or the displays
change. It never removes a desktop or moves a window. The creation call is adapted
from Dinky's bridged `SLSBridgedSpaceCreateOperation` and works with SIP enabled.

UI actions that switch workspaces or focus run commands (`runUserCommands`,
`selectWorkspaceFromUi`) so the command layer chooses each backend's path.
`activateWorkspaceForUser` refuses with native Spaces and fails unit tests, so a UI
path that bypasses the command layer shows up in `make check`.

See [assessment and measured Phase 0 results](NATIVE_SPACES_ASSESSMENT.md).
