# Native Spaces ownership boundary

Status: accepted for experimental read-only integration; native tiling is not enabled.

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
Native creation/deletion, activation, cross-Space moves, whole-Space relocation and
project mapping remain explicit unsupported capabilities.

See [assessment and measured Phase 0 results](NATIVE_SPACES_ASSESSMENT.md).
