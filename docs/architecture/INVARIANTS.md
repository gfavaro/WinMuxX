# Architectural invariants

## Plain English overview

An invariant is a property worth protecting across implementation changes. “Partially enforced” means guards or tests exist. It does not mean every event ordering is proven. Proposed invariants are targets, not claims about current behavior. Severity describes potential user impact, not evidence of an existing defect.

## Architectural rules

Existing project rules: workspace selection MUST preserve display ownership and explicit moves MUST retain organization. Proposed: changes SHOULD identify affected invariant IDs, add meaningful tests for uncovered paths, and SHOULD NOT claim an invariant fully enforced from a read-only diagnostic alone.

## Technical reference

| ID and invariant | Status / owner / rationale / severity | Evidence and tests / missing test |
| --- | --- | --- |
| INV-001 A managed live window has an explainable context; minimized/popups may use special containers. | Partially enforced by tree operations; detected (not enforced) by the checker, which production runs only through `debug-windows`. Owner: tree and native registry; prevents orphaning. High. | [checker](../../Sources/AppBundle/runtime/ModelInvariantChecker.swift), [test](../../Sources/AppBundleTests/runtime/ModelInvariantCheckerTest.swift); missing: native event interleavings. Checker is an explicit settled-model scan, not a universal enforcement mechanism. |
| INV-002 Selection preserves display ownership; explicit relocation carries workspace organization. | Existing project rule, partially enforced; assignment policy; protects portable work. High. | [policy](../../Sources/AppBundle/tree/WorkspaceMonitorAssignment.swift), [tests](../../Sources/AppBundleTests/command/MonitorWorkspaceNavigationTest.swift); missing: physical hotplug and app-specific effects. |
| INV-003 A live workspace is not active in two display viewports. | Partially enforced by assignment policy (callers of `setActiveWorkspace`, which use `isWorkspaceActive(_:outside:)`); the registry itself does not reject a duplicate; the checker only detects one. Prevents conflicting placement. High. | [registry](../../Sources/AppBundle/tree/WinMuxWorkspaceState.swift), [checker](../../Sources/AppBundle/runtime/ModelInvariantChecker.swift); missing: stress event ordering. |
| INV-004 Restart matching must not rely on transient ordering or blindly trust reused window IDs. | Partially enforced; restart matcher; prevents wrong placement. High. | [matcher](../../Sources/AppBundle/tree/frozen/RestartWindowIdentity.swift), [restart tests](../../Sources/AppBundleTests/tree/RestartWorkspaceTest.swift); missing: wider ambiguous real-app corpus. |
| INV-005 Layout transitions do not duplicate, orphan or silently relocate windows. | Proposed; arrangement transition and tree; preserves membership. High. | [transition](../../Sources/AppBundle/tree/MasterLayout.swift), [Tabbed tests](../../Sources/AppBundleTests/command/WorkspaceTabbedArrangementTest.swift); missing: pairwise mixed-layout and failure matrix. |
| INV-006 Unchanged inputs do not cause unbounded geometry drift. | Proposed; geometry and native writer; prevents visible movement. Medium. | [geometry](../../Sources/AppBundle/layout/DwindleLayoutGeometry.swift), [scroll test](../../Sources/AppBundleTests/layout/ScrollingGeometryTest.swift); missing: repeated native round-trip and rounding across modes. |
| INV-007 Failed AX operations do not permanently corrupt the model or count as successful placement. | Partially enforced; native adapters/refresh; protects recovery. High. | [reliability](../RELIABILITY.md), [failure test](../../Sources/AppBundleTests/model/RefreshFailureRecoveryTest.swift); missing: failure injection across all operations and subsequent convergence. |
| INV-008 Display changes do not make a workspace permanently inaccessible. | Proposed; viewport reconciliation; protects access. High. | [registry](../../Sources/AppBundle/tree/WinMuxWorkspaceState.swift), [topology test](../../Sources/AppBundleTests/model/MonitorTopologyTest.swift); missing: physical disconnect/reconnect and UUID conflicts. |
| INV-009 A gesture does not mutate an unrelated workspace. | Proposed; gesture coordinator and session epoch; protects other work. High. | [state](../../Sources/AppBundle/tree/ScrollingWorkspaceState.swift), [gesture coordinator](../../Sources/AppBundle/mouse/WorkspaceGestureCoordinator.swift); [receiver lifecycle tests](../../Sources/AppBundleTests/ui/ScrollingReceiverLifecycleTest.swift) pin that a callback after a display-ownership change still acts on its own workspace; missing: physical delivery of late callbacks. |
| INV-010 Switching workspaces does not accidentally overwrite recoverable geometry. | Proposed; visibility and frozen recovery; protects organization. High. | [snapshot](../../Sources/AppBundle/tree/frozen/persistedFrozenWorld.swift), [restart test](../../Sources/AppBundleTests/tree/RestartWorkspaceTest.swift); missing: switching while restore is in flight and app exits. |
| INV-011 Switching workspaces does not create invalid references. | Proposed; frozen recovery and registry; protects valid membership. High. | [restore](../../Sources/AppBundle/tree/frozen/closedWindowsCache.swift), [restart tests](../../Sources/AppBundleTests/tree/RestartWorkspaceTest.swift); missing: invalid-reference assertions during concurrent switching and restoration. |

## Failure modes

A failed invariant may appear as a missing window, incorrect display, wrong tab or repeated movement. First distinguish a model error from a native AX refusal. Diagnostics and tests do not repair the model by themselves.

## Open questions

Unknown: which proposed invariants already hold in every path. Severity and candidate tests must be revisited with concrete reproduction and user impact.
