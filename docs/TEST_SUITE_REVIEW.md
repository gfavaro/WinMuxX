# Test suite review — 2026-10-06

Reviewed the bodies of all 857 discovered Swift tests, their fixtures and shared assertions, plus the 11 Python release/identity tests. The inventory below records the original suite. This was a source review and execution review, not a line-coverage measurement or proof that every OS behavior is covered.

## Changes

- Removed four weak/redundant tests: ActionMenu's Lateinit equality case (covered by LateinitEqualityTest); detached-tab reentry (covered by the stronger swap/stack reentry test); two rectangle-contains-own-center assertions. The existing window/group geometry tests now check fixed points inside the window body as well as separation from tab zones.
- Assertion helpers now attribute failures to the calling test. Unexpected parser help produces a test failure rather than terminating the process. Successful interpolation cannot silently accept an empty failure.
- Benchmarks retain their operation-count checks without artificial AX/frame latency in ordinary runs. Set AX_REFRESH_BENCHMARK_LABEL, POST_COMMAND_REFRESH_BENCHMARK_LABEL, LAYOUT_FRAME_BENCHMARK_LABEL or WINDOW_TITLE_BENCHMARK_LABEL to enable each latency simulation. Title benchmarks require exactly one title read per window across repeated model updates; frame writes have a useful lower/upper bound instead of merely being positive.
- Added three regression cases: existing user configuration remains byte-for-byte intact during bootstrap; blank titles preserve a known title while blank first sight returns nil; malformed client requests fail decoding.
- Strengthened event decoding to compare all payload fields after round trip and future-request compatibility to verify the decoded request contents.
- Renamed two minimized-window snapshot tests to describe their actual detached-window behavior.

## Retained coverage and remaining gaps

Command parsing and execution tests exercise different contracts. Horizontal/vertical layouts, drag window/tab/group paths, mouse boundaries, monitor identity, snapshot versions, malformed snapshots, backups, delayed discovery and native fullscreen/minimized states remain separate because their failure paths differ. Similar fixture setup alone was not a reason to delete tests. Subprocess isolation in fatal-termination tests and the cancellable in-flight refresh delay remain necessary.

The highest remaining gaps are macOS integration scenarios: real AX window discovery after reboot/app update, recycled native window IDs, application permission changes, and monitor removal/reconnection while restoring. The unit suite uses TestWindow/TestMonitor and cannot establish these behaviors by itself. They need an isolated manual/integration runner, rather than more assertions over the same mocks.

Some asynchronous tests still rely on bounded Task.yield loops, and RefreshFocusSyncTest contains unbounded synchronization waits that should be replaced by timeout-bound coordination in a focused follow-up. Shared global workspace/config state means this suite is not ready for parallel execution. ShellTest.swift is entirely commented-out legacy code and contributes no runnable tests.

## Validation

`make check` passed: 856 Swift tests and 11 Python tests, zero failures. Swift test execution took 6.59 seconds on this run; the prior 857-test run took about 9.3 seconds. These are individual runs, not a controlled performance comparison. No application binary or installed app changed.

## Original Swift inventory

| File | Tests |
| --- | ---: |
| `Sources/AppBundleTests/RefreshFocusSyncTest.swift` | 9 |
| `Sources/AppBundleTests/SwitcherPaletteTest.swift` | 7 |
| `Sources/AppBundleTests/command/AgentCommandTest.swift` | 13 |
| `Sources/AppBundleTests/command/AgentCommandTestLayout.swift` | 7 |
| `Sources/AppBundleTests/command/BalanceSizesCommandTest.swift` | 1 |
| `Sources/AppBundleTests/command/CloseCommandTest.swift` | 2 |
| `Sources/AppBundleTests/command/DwindleParityTest.swift` | 17 |
| `Sources/AppBundleTests/command/DwindleReferenceParityTest.swift` | 6 |
| `Sources/AppBundleTests/command/DwindleResizeCommandTest.swift` | 9 |
| `Sources/AppBundleTests/command/ExecCommandTest.swift` | 1 |
| `Sources/AppBundleTests/command/FlattenWorkspaceTreeCommandTest.swift` | 1 |
| `Sources/AppBundleTests/command/FocusCommandTest.swift` | 17 |
| `Sources/AppBundleTests/command/JoinWithCommandTest.swift` | 1 |
| `Sources/AppBundleTests/command/ListAppsTest.swift` | 1 |
| `Sources/AppBundleTests/command/ListModesTest.swift` | 3 |
| `Sources/AppBundleTests/command/ListMonitorsTest.swift` | 1 |
| `Sources/AppBundleTests/command/ListWindowsTest.swift` | 4 |
| `Sources/AppBundleTests/command/ListWorkspacesTest.swift` | 2 |
| `Sources/AppBundleTests/command/MonitorWorkspaceNavigationTest.swift` | 14 |
| `Sources/AppBundleTests/command/MoveCommandTest.swift` | 17 |
| `Sources/AppBundleTests/command/MoveNodeToMonitorCommandTest.swift` | 1 |
| `Sources/AppBundleTests/command/MoveNodeToWorkspaceCommandTest.swift` | 16 |
| `Sources/AppBundleTests/command/ResizeCommandTest.swift` | 6 |
| `Sources/AppBundleTests/command/SplitCommandTest.swift` | 4 |
| `Sources/AppBundleTests/command/StackWithCommandTest.swift` | 2 |
| `Sources/AppBundleTests/command/SubscribeCmdArgsTest.swift` | 6 |
| `Sources/AppBundleTests/command/SummonWorkspaceCommandTest.swift` | 3 |
| `Sources/AppBundleTests/command/SwapCommandTest.swift` | 5 |
| `Sources/AppBundleTests/command/WorkspaceBackAndForthCommandTest.swift` | 1 |
| `Sources/AppBundleTests/command/WorkspaceCommandTest.swift` | 26 |
| `Sources/AppBundleTests/config/AnimationsConfigTest.swift` | 2 |
| `Sources/AppBundleTests/config/ConfigBootstrapTest.swift` | 4 |
| `Sources/AppBundleTests/config/ConfigTest.swift` | 30 |
| `Sources/AppBundleTests/config/ConfigTestConfigEdits.swift` | 9 |
| `Sources/AppBundleTests/config/ConfigTestWorkspaceSidebarConfig.swift` | 10 |
| `Sources/AppBundleTests/config/ForkIdentityTest.swift` | 3 |
| `Sources/AppBundleTests/config/ParseEnvVariablesTest.swift` | 5 |
| `Sources/AppBundleTests/config/SplitArgsTest.swift` | 1 |
| `Sources/AppBundleTests/config/WindowBordersConfigTest.swift` | 3 |
| `Sources/AppBundleTests/focus/FocusFollowsMouseControllerTest.swift` | 4 |
| `Sources/AppBundleTests/layout/LayoutMinimumFitTest.swift` | 4 |
| `Sources/AppBundleTests/layout/SingleWindowGeometryTest.swift` | 8 |
| `Sources/AppBundleTests/model/ClientServerTest.swift` | 8 |
| `Sources/AppBundleTests/model/LateinitEqualityTest.swift` | 2 |
| `Sources/AppBundleTests/model/MonitorTopologyTest.swift` | 6 |
| `Sources/AppBundleTests/model/RefreshSessionEventReassertionTest.swift` | 1 |
| `Sources/AppBundleTests/model/WindowClassificationTest.swift` | 4 |
| `Sources/AppBundleTests/mouse/MouseDragSubjectTest.swift` | 8 |
| `Sources/AppBundleTests/mouse/WindowDropIntentResolverTest.swift` | 4 |
| `Sources/AppBundleTests/mouse/WindowShakeGestureTest.swift` | 10 |
| `Sources/AppBundleTests/recovery/FatalTerminationTest.swift` | 1 |
| `Sources/AppBundleTests/recovery/WindowRecoveryJournalTest.swift` | 13 |
| `Sources/AppBundleTests/recovery/WindowTerminationTest.swift` | 4 |
| `Sources/AppBundleTests/tree/AxWindowDiscoveryTest.swift` | 6 |
| `Sources/AppBundleTests/tree/ClosedWindowReuseTest.swift` | 3 |
| `Sources/AppBundleTests/tree/DoubleSidedWindowsTest.swift` | 5 |
| `Sources/AppBundleTests/tree/ExistingDwindleWindowsTest.swift` | 6 |
| `Sources/AppBundleTests/tree/LearnedWindowMinimumTest.swift` | 5 |
| `Sources/AppBundleTests/tree/NormalizeLayoutReasonCacheTest.swift` | 4 |
| `Sources/AppBundleTests/tree/RestartWorkspaceTest.swift` | 26 |
| `Sources/AppBundleTests/tree/TreeNodeTest.swift` | 43 |
| `Sources/AppBundleTests/tree/TreeNodeTestFrozenWorld.swift` | 8 |
| `Sources/AppBundleTests/tree/WindowTabsTest.swift` | 17 |
| `Sources/AppBundleTests/tree/WindowTabsTestDragGeometry.swift` | 18 |
| `Sources/AppBundleTests/tree/WindowTabsTestLayout.swift` | 14 |
| `Sources/AppBundleTests/tree/WindowTabsTestStickyIntent.swift` | 20 |
| `Sources/AppBundleTests/tree/WindowTabsTestSwapAndStack.swift` | 19 |
| `Sources/AppBundleTests/tree/WindowTabsTestTabStrip.swift` | 22 |
| `Sources/AppBundleTests/tree/WorkspaceMinimumRetentionTest.swift` | 7 |
| `Sources/AppBundleTests/ui/ActionMenuTest.swift` | 25 |
| `Sources/AppBundleTests/ui/AxRefreshBenchmarkTest.swift` | 1 |
| `Sources/AppBundleTests/ui/AxRefreshFastPathTest.swift` | 5 |
| `Sources/AppBundleTests/ui/DestroyedWindowElementTest.swift` | 3 |
| `Sources/AppBundleTests/ui/LayoutFrameWriteBenchmarkTest.swift` | 1 |
| `Sources/AppBundleTests/ui/MenuBarWorkspaceIndicatorTest.swift` | 2 |
| `Sources/AppBundleTests/ui/MissionControlBorderSuppressionTest.swift` | 7 |
| `Sources/AppBundleTests/ui/PostCommandRefreshBenchmarkTest.swift` | 1 |
| `Sources/AppBundleTests/ui/SessionWindowTitleTest.swift` | 3 |
| `Sources/AppBundleTests/ui/SettingsDraftAndPreviewTest.swift` | 4 |
| `Sources/AppBundleTests/ui/SettingsPersistenceRegressionTest.swift` | 6 |
| `Sources/AppBundleTests/ui/ShortcutSettingsConfigEditsTest.swift` | 9 |
| `Sources/AppBundleTests/ui/SidebarWorkspaceNumberTest.swift` | 3 |
| `Sources/AppBundleTests/ui/TrayMenuModelSetIfChangedTest.swift` | 1 |
| `Sources/AppBundleTests/ui/WindowMotionTest.swift` | 10 |
| `Sources/AppBundleTests/ui/WindowTabChromeAppearanceTest.swift` | 1 |
| `Sources/AppBundleTests/ui/WindowTitleBenchmarkTest.swift` | 1 |
| `Sources/AppBundleTests/ui/WindowTitleCacheTest.swift` | 2 |
| `Sources/AppBundleTests/ui/WorkspaceLifecycleTest.swift` | 13 |
| `Sources/AppBundleTests/ui/WorkspaceNamingTest.swift` | 38 |
| `Sources/AppBundleTests/ui/WorkspaceNamingTestMonitorAssignment.swift` | 10 |
| `Sources/AppBundleTests/ui/WorkspaceSidebarAppearanceTest.swift` | 26 |
| `Sources/AppBundleTests/ui/WorkspaceSidebarClockComponentsTest.swift` | 5 |
| `Sources/AppBundleTests/ui/WorkspaceSidebarDragTest.swift` | 53 |
| `Sources/AppBundleTests/ui/WorkspaceSidebarDragTestTargets.swift` | 16 |
| `Sources/AppBundleTests/ui/WorkspaceSidebarFrostedTintTest.swift` | 7 |
| `Sources/AppBundleTests/ui/WorkspaceSidebarGeometryTest.swift` | 4 |
| `Sources/AppBundleTests/ui/WorkspaceSidebarInlineTextKeyTest.swift` | 4 |
| `Sources/AppBundleTests/ui/WorkspaceSidebarOverrideTest.swift` | 9 |
| `Sources/AppBundleTests/ui/WorkspaceSidebarWallpaperContrastTest.swift` | 15 |
| `Sources/AppBundleTests/util/StringExTest.swift` | 2 |
| **Total** | **857** |
