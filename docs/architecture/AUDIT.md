# Architecture audit and hardening backlog

## Plain English overview

This is an independent critical examination of the reconstructed design by the implementing agent, not an independent agent review. Findings distinguish demonstrated implementation properties from hypothetical failures. No P0 or confirmed P1 defect was established in this documentation review. Priorities describe investigation value; a risk is not proof of a user-visible bug.

## Architectural rules

Existing: preserve working behavior and recovery data. Proposed: prioritize confirmed correctness defects before restructuring; every task SHOULD specify observable acceptance and regression coverage. Significant contract changes require the approval process in [governance](GOVERNANCE.md).

## Technical reference: findings

| ID / severity / confidence | Description and evidence | Impact, affected components and recommended action | Verification / complexity |
| --- | --- | --- | --- |
| AUD-001 / P2 / High | Observed: snapshot saves `scrollingOffset` only when Scrolling is current, although runtime retains Scrolling state while in another arrangement. [FrozenWorkspace](../../Sources/AppBundle/tree/frozen/closedWindowsCache.swift), [state](../../Sources/AppBundle/tree/ScrollingWorkspaceState.swift). | Potential loss of prior strip position after restart in another mode; workspace, snapshots and Scrolling. Confirm desired behavior with PM before changing persistence. This is a documented limitation, not a proven defect. | Test switch away, restart, return with multiple columns and compare offset; Medium. |
| AUD-002 / P2 / High | Observed: matching rejects ambiguous identities and may use sole-window fallback; metadata can be missing. [matcher](../../Sources/AppBundle/tree/frozen/RestartWindowIdentity.swift). | Placement may not return or may depend on available evidence; restart and native discovery. Build representative fixtures and improve diagnostics before considering identity changes. | Matching matrix for same titles, missing metadata, ID reuse and late arrival; Medium. |
| AUD-003 / P2 / High | Observed: arrangement-specific state is separate but tree, commands, focus and transition logic cross modes. [transition](../../Sources/AppBundle/tree/MasterLayout.swift), [focus command](../../Sources/AppBundle/command/impl/FocusCommand.swift). | A change in one mode can affect another; workspace, layouts and commands. Add pairwise transition coverage before proposing boundary changes. | Assert live membership, group boundaries and focus in mixed-mode round trips; Medium. |
| AUD-004 / P2 / Medium | Observed: runtime model, native window state, focus hints and persisted snapshots are distinct representations; AX failure and asynchronous events can delay synchronization. [refresh](../../Sources/AppBundle/layout/refresh.swift), [reliability](../RELIABILITY.md). | Potential stale placement or focus; refresh, AX and recovery. Extend targeted failure/interleaving tests, preserving existing budgets. | Inject timeout, delayed destroy and explicit selection; assert later convergence and unrelated app progress; Medium. |
| AUD-005 / P2 / Medium | Observed: viewport keys use coordinates while connected/disconnected matching also records UUID. [identity](../../Sources/AppBundle/tree/WorkspaceIdentity.swift), [registry](../../Sources/AppBundle/tree/WinMuxWorkspaceState.swift). | Topology churn or absent/ambiguous UUID can complicate restoration; display and workspace state. Test realistic sequences and record unresolved cases. | Automated UUID/coordinate cases plus physical hotplug; Medium. |
| AUD-006 / P3 / High | Observed: private AX/WindowServer symbols and Dock event taps depend on platform behavior. [private header](../../Sources/PrivateApi/include/private.h), [border](../../Sources/PrivateApi/border.m), [Dock](../../Sources/AppBundle/mouse/DockWorkspaceSwipe.swift). | OS updates can affect window identification, borders or gesture input. Maintain capability diagnostics and fallback tests; do not claim private API guarantees. | Test unavailable symbols and gesture tap recovery; real macOS matrix; Medium. |
| AUD-007 / P3 / Medium | Observed: settled-model invariant checker is explicit and read-only, not a global enforcement gate. [checker](../../Sources/AppBundle/runtime/ModelInvariantChecker.swift). | Some corruption may be diagnosed late; model/diagnostics. Use it at selected test boundaries before considering runtime invocation. | Assert no violations after representative commands and restore, including special containers; Small. |

## Backlog

All tasks are **Proposed** and unapproved; no production change is part of this baseline.

| Phase / task | Plain English outcome; contracts and prerequisites | Measurable acceptance, complexity and regression risk |
| --- | --- | --- |
| A — Correctness: investigate reported failures | No confirmed critical defect was found. Triage real reproductions first; INV-001/002/004/007. Prerequisite: reproducible user case. | Reproduce on unchanged revision and add a failing regression test; size depends on defect. Risk: false positives from native timing. |
| B — Boundaries: transition matrix (AUD-003) | Make cross-layout effects visible without redesign; INV-005/006. Prerequisite: agree test fixtures and expected existing behavior. | Cover each pair of Dwindle/Tabbed/Scrolling/Master with nested groups, membership and focus assertions; Medium. Risk: tests accidentally encode unintended behavior. |
| C — Reliability: identity and restore (AUD-002/004) | Detect ambiguous restore safely and demonstrate later convergence; INV-004/007/010. Prerequisite: representative metadata and failure cases. | Matcher cases and delayed creation/timeout tests pass without wrong placement or unrelated-app starvation; Medium. Risk: overly eager matching moves the wrong window. |
| C — Reliability: display lifecycle (AUD-005) | Show workspaces remain reachable across topology changes; INV-002/003/008. Prerequisite: test fixtures and access to two displays for native validation. | Disconnect/reconnect and resolution sequences retain or expose each workspace, with separate physical results; Medium. Risk: policy change could unexpectedly move workspaces. |
| C — Reliability: Scrolling restart policy (AUD-001) | Decide whether the old strip position should survive restart when another arrangement is active; INV-005/010. Prerequisite: PM decision and proposed schema ADR if changed. | Explicit behavior documented and covered by restart/transition test; Medium. Risk: stale offsets and compatibility with older snapshots. |
| D — Maintainability: diagnostics and platform fallbacks (AUD-006/007) | Make unresolved model/platform failures easier to identify; INV-001/007. Prerequisite: failure scenarios. | Tests exercise missing symbols and checker after representative settled operations; Small to Medium. Risk: excessive diagnostics or work on the main thread. |

## Failure modes

Prioritization can overstate hypothetical risk or hide an actual defect. Promote a finding only with reproduction and impact; retain evidence and do not “fix” data loss by deleting user state.

## Open questions

Unknown: independent reviewer availability, physical hotplug behavior and production frequency of ambiguous identities. No architecture-wide automated coverage percentage or performance baseline was measured.
