# State, persistence and recovery

## Plain English overview

Observed: WinMuxX keeps a live model, but other apps own their windows. WinMuxX saves information to try to reconstruct work after restart. It separately records frames for recovery. A saved window may be absent, recreated with a new ID, ambiguous, or unable to accept a move. Restoration is therefore best effort. It cannot force the desktop back to an exact prior state as one transaction.

## Architectural rules

Existing: preferences belong to TOML; state snapshots and recovery data are separate. Existing code rejects ambiguous restart matches and validates a saved Scrolling offset before applying it. Proposed: every new state field SHOULD name its owner, lifetime, reconstruction rule and persistence policy; native failures MUST NOT be described as successfully applied.

## Technical reference

| State | Observed owner and lifetime | Limits |
| --- | --- | --- |
| Workspace/project registry, active viewport | `WinMuxRuntime.workspaces`; `Workspace` tree and arrangement; display viewport keyed by coordinate with UUID recorded for connected/disconnected matching. | Native desktop can diverge; coordinates change on topology changes. |
| Focus | Runtime logical focus/history plus native application focus; Tabbed/Scrolling hold per-mode hints. | Multiple representations have different purposes; exact reconciliation is event-dependent. |
| Geometry | Layout computes desired frames; window keeps last applied/actual values; native app/WindowServer owns actual result. Floating geometry and original frames have separate paths. | Values may be stale or write rejected; not a single authoritative physical frame. |
| Restart | Application Support `window-state.json` versioned `PersistedFrozenWorldEnvelope`, backup and pending snapshots; writer coalesces saves and avoids identical rewrites. | Primary then backup are decoded; unsupported/corrupt data may yield no snapshot. Save errors logged. |
| Window identity | Live WindowServer ID plus restart metadata; same ID is trusted only with verified process launch, otherwise matching must be unique. | Titles change; document/AX ID may be absent; sole relaunched window can match absent contradictions. Ambiguous matches are intentionally not forced. |
| Layout | Tree, arrangement, Tabbed frozen structure and widths saved; Scrolling offset saved only when arrangement is Scrolling. Gesture session, anchors and runtime focus hints have separate lifetimes. | Switching away then restarting does not establish preservation of the prior strip offset. |
| Original frame recovery | `WindowRecoveryController` journal records before native mutation and handles restoration separately from frozen workspace snapshots. | Crash timing and external app behavior constrain recovery. |
| Config/cache | TOML through config owner; some session/cache data and learned minimums use UserDefaults. | Do not equate cache with product preference. |

Sources: [runtime](../../Sources/AppBundle/runtime/WinMuxRuntime.swift), [registry](../../Sources/AppBundle/tree/WinMuxWorkspaceState.swift), [snapshot](../../Sources/AppBundle/tree/frozen/persistedFrozenWorld.swift), [frozen workspace](../../Sources/AppBundle/tree/frozen/closedWindowsCache.swift), [identity](../../Sources/AppBundle/tree/frozen/RestartWindowIdentity.swift), [frame recovery](../../Sources/AppBundle/recovery/WindowRecoveryController.swift), [learned minimums](../../Sources/AppBundle/tree/PersistedAppMinimums.swift). Ownership overlaps appear in live, last-applied and native geometry, and in global and per-layout focus. These are distinct representations and are not automatically defects. Their synchronization and lifetime deserve tests.

### Three recovery paths

At startup, automatic tiling enables snapshot loading. Discovered windows are matched to saved identities and the saved tree is reconstructed as matches become available. Floating restoration applies the saved size, clamped to the display, with no saved position in that operation. A workspace preview frame is separate from that size and from original-frame recovery. See [startup](../../Sources/AppBundle/initAppBundle.swift) and [floating restoration](../../Sources/AppBundle/tree/frozen/closedWindowsCache.swift).

Normal shutdown saves the workspace snapshot and attempts to restore each managed window’s recorded original position and size. If a parked window has no recorded original frame, the controller uses its fallback recovery frame when available. It skips fullscreen and minimized windows. It also refuses a restore if the native frame changes during its check, the display is unavailable, or the application cannot accept the frame. Failed restorations can remain pending. See [termination](../../Sources/AppBundle/util/appBundleUtil.swift) and [controller](../../Sources/AppBundle/recovery/WindowRecoveryController.swift).

After an unexpected termination, original-frame recovery is an explicit menu action. It pauses tiling before attempting matched original positions and sizes. It checks identity, display intersection, Accessibility reachability, fullscreen and minimized state, then reads the result back. An unavailable display, unresponsive application, rejected frame, or changed identity can prevent restoration. The action reports failures. See [menu](../../Sources/AppBundle/ui/menubar/NativeActionMenu.swift) and [crash recovery](../../Sources/AppBundle/recovery/WindowRecoveryController.swift).

### Scenarios

| Scenario | Observed behavior / limitation / regression risk |
| --- | --- |
| Startup | Snapshot load is gated by automatic tiling; startup prepares pending restoration and discovered windows match incrementally. Missing windows can remain pending; startup need not block forever. |
| Normal shutdown | Termination path saves workspace state and invokes window recovery; successful restoration depends on native operations. Do not assume the two stores commit atomically. |
| Unexpected termination | Journal and last completed snapshot provide recovery inputs; a crash between mutations/writes may lose the latest state. Exact guarantees depend on termination mode. |
| App terminates while WinMuxX inactive | No live termination observation while the process is down. On restart only available snapshots and currently discovered windows can be matched; no guarantee of exact placement. |
| Display disconnect | Display viewport reconciliation retains disconnected viewport metadata by UUID and chooses available ownership/fallback; unresolved or duplicate identity can prevent exact recovery. |
| Display reconnect | UUID-based reconciliation can recover an earlier display viewport where identity matches; topology and intervening choices matter. Do not promise all physical sequences without testing. |
| Window/app recreation | Same-process ID match requires same launch; otherwise metadata scoring and uniqueness, or a constrained sole-window fallback, apply. Ambiguous windows may not regain exact placement. |
| Workspace switch | Active viewport changes, hidden windows are parked/revealed; desired geometry and focus are recomputed. Failed native work can delay convergence. |
| Layout switch | Shared tree may be wrapped and Tabbed groups synchronized; state retained in memory is not necessarily all persisted. |
| Sleep/wake | Wake and screen-wake notifications schedule refresh. Power-off notification saves and holds subsequent saves; sleep is not assumed equivalent to power-off. |
| Window created during restore | Registration attempts pending snapshot matching as windows arrive; late arrivals and explicit user actions interact with bounded recovery. |
| Invalid/old state | Envelope loader accepts supported versions, tries backup; individual unknown arrangement and invalid Tabbed structure have lenient fallbacks. Not every malformed field is individually recoverable. |

[Restart tests](../../Sources/AppBundleTests/tree/RestartWorkspaceTest.swift), [journal tests](../../Sources/AppBundleTests/recovery/WindowRecoveryJournalTest.swift) and [topology tests](../../Sources/AppBundleTests/model/MonitorTopologyTest.swift) cover selected paths. They do not prove crash consistency or all real app cases.

## Failure modes

Silent-seeming loss of placement can follow ambiguous metadata, a missing snapshot, expired pending data or a failed native operation. Snapshot save errors are logged. Inspect logs and recovery data before retrying. Never delete a user's state to force a test to pass.

## Open questions

Unknown: end-to-end crash consistency at each write boundary, all combinations of restoration and simultaneous manual moves, and whether conditional Scrolling offset persistence matches product expectations. These are audit items, not established bugs.
