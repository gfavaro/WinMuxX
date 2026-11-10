# Redundant coverage review — 2026-11-10

This pass removes five tests rather than regrouping their scenarios into fewer
methods. It follows the fixture consolidations in `65960449` and `6acf3f42`.
The review traced the candidates below into production and retained tests; it
is not a line-coverage audit of every test or proof of equivalent fault detection.
No production code changes are included.

## Deletions and retained coverage

Paths below are relative to `Sources/AppBundleTests`.

| Removed test | Retained coverage and reason |
| --- | --- |
| `layout/TileLayoutGeometryTest.testMinimumsFitAndImpossibleFitKeepsRequestedSizes` | `layout/LayoutMinimumFitTest.testRaisesShortWindowsAndTakesSpaceFromRemainingSiblings`, `testPinsMultipleMinimumsProportionally`, and `testOverflowKeepsRequestedDistribution` exercise the same `TileLayoutGeometry.fit` implementation through the one-line `fitLayoutSizes` forwarding function. They check individual allocated sizes, totals, multiple pinned minima, and impossible allocation. The removed two-item examples add no separate production branch. |
| `layout/SingleWindowGeometryTest.testALoneWindowIsCentered` | `testScreenThresholdAndOrientation` calls `singleWindowLimitedRect`, which delegates to `centeredSingleWindowRect`, and checks centered X, width, unchanged Y and height across multiple screen shapes. The removed case only checks centered X and unchanged height, with positive width and no minimum clamp. |
| `ui/WindowMotionTest.testRetargetStartsAtCurrentFrame` | `testCrossDisplayMotionDepartsFromNativeFrameAndGoesDirectlyToTile` checks progress 0 and 1 against supplied start/target frames. `testInterpolationAndExactLanding` checks midpoint interpolation and clamped endpoints. The removed test constructs a second `WindowMotionFrame` from a sampled rectangle; it never exercises the `WindowMotion` playback/retarget path. `testRetargetUsesInFlightPositionAndMissingNativeFrameUsesCache` remains for departure selection. |
| `tree/TreeNodeTest.testWorkspaceDisplayNameUsesSidebarDraftFallback` | `testReconcileWorkspaceStateClearsCollectedDraftWorkspaceLabel` and `testReconcileWorkspaceStateClearsOrphanedDraftWorkspaceLabel` already assert the same numeric draft fallback after stale-label cleanup, through `workspaceDisplayName`. Changing the suffix from 1/7 to 4 adds no formatting boundary. |
| `tree/TreeNodeTest.testReconcileWorkspaceStateKeepsPersistentEmptyWorkspace` | `tree/WorkspaceRetentionTest.testPersistentSlotsAreStableAcrossReconciliation` configures multiple persistent empty slots, checks the workspace count, focused identity and user-facing eligibility, then checks identities across repeated reconciliation. `TreeNodeTest.testReconcileMaterializesConfiguredPersistentWorkspaceWithoutChangingViewport` retains the creation and viewport contract. |

## Cases retained deliberately

The reviewed native-window tests exercise AX operation ordering and failure
handling; pure geometry tests exercise invalid frames and display intersections.
Neither substitutes for the other. Snapshot compatibility versions, delayed
restoration, explicit workspace movement versus selection, and independent command
failure modes also remain. Similar setup does not establish redundant coverage.

The parking-corner extraction test remains: its comparison against the historical
expression covers offset arrangements beyond the fixed expected corner examples.
Removing it merely because it resembles production would discard that evidence.

## Validation

The affected suites passed 79 tests after deletion. Seven temporary production
mutations were detected by retained tests with assertion failures:

- Returning requested sizes instead of fitting minima.
- Returning no sizes for an impossible minimum allocation.
- Shifting the centered rectangle by one point.
- Returning the target at interpolation progress 0.
- Returning the start at interpolation progress 1.
- Rendering an unknown draft workspace as `Draft N` rather than `Workspace N`.
- Pruning configured persistent workspaces that are not visible.

An initial broader persistent-identity mutation crashed the selected test; that
attempt was not counted as assertion evidence. The narrower pruning mutation
above failed the retained reconciliation assertions. These are representative
faults, not an exhaustive mutation score.

All temporary production edits were restored, and `git diff --exit-code --
Sources/AppBundle` passed before the final gate. `make check` passed 1,590
Swift tests with zero failures, Python tooling/schema checks and dependency
validation. No app was built or installed; this change affects tests only.

