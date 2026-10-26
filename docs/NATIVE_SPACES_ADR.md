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
lifecycle events and audits topology every 500 ms. Unchanged audits perform no
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

Native creation/deletion, activation, cross-Space moves, whole-Space relocation and
project mapping remain explicit unsupported capabilities.

See [assessment and measured Phase 0 results](NATIVE_SPACES_ASSESSMENT.md).
