# Contributor task map

Choose a starting point below, then trace current callers. Paths are relative to
`Sources/AppBundle` unless stated otherwise. Listed tests are starting coverage,
not evidence that every proposed change is covered.

| Task | Entry point and owner | Starting test filter | Done when |
| --- | --- | --- | --- |
| Sidebar selection or Bring Here | `ui/sidebar/WorkspaceSidebarWorkspaceSection.swift` → `WorkspaceSidebarActionsAdapter.swift` → `WorkspaceSidebarActions.swift`; policy in `tree/WorkspaceMonitorAssignment.swift` | `MonitorWorkspaceNavigationTest`, `WorkspaceSidebarOverrideTest` | Selection and relocation follow the requested semantics; both displays and unrelated workspaces are checked |
| Workspace command | `command/impl/WorkspaceCommand.swift`, `MoveWorkspaceToMonitorCommand.swift`, `SummonWorkspaceCommand.swift`; arguments in `Sources/Common/cmdArgs/impl` | `WorkspaceCommandTest`, `SummonWorkspaceCommandTest` | Parsing, execution, failures and no-ops agree; shared ownership policy is reused |
| Lifecycle or restart | `tree/WorkspaceLifecycle.swift`, `WinMuxWorkspaceState.swift`; trace persistence callers | `WorkspaceRetentionTest`, `RestartWorkspaceTest` | Identity, membership and saved state survive the affected transitions; fixtures never write real user state |
| Settings save | `ui/settings/SettingsConfigPersistence.swift`, `SettingsSaveQueue.swift`, `ShortcutSettingsModel`; `config/ConfigFileStore.swift` | `SettingsSaveQueueTest`, `ShortcutSettingsConfigEditsTest` | Actual Settings destination writes valid TOML, reloads it and retains drafts on failure |
| Shared appearance | `ui/core/ChromeAppearance.swift` and the affected sidebar/tab/overlay consumer | `ChromeAppearanceTest`, `WorkspaceSidebarAppearanceTest`, `WindowTabChromeAppearanceTest` | System appearance/accessibility inputs are covered; native materials receive desktop inspection |
| Shortcut recovery | `config/HotkeyBinding.swift`, `SideFilteredHotkeys.swift`; runtime owns hotkey state | `HotkeyRecoveryTest`, `ModeLeaderTest` | Typing and mode transitions work; stale asynchronous work cannot restore obsolete state |
| New configuration option | `config/parseConfig.swift`, its section parser, `resources/default-config.toml` and schema inventory | `ConfigTest` and relevant section tests; `script/test_config_schema.py` | Parser, defaults, Settings/CLI consumers, schema and current docs agree; existing configurations retain intended meaning |
| Layout geometry | `layout/layoutRecursive.swift`, `TileLayoutGeometry.swift`, `DwindleLayoutGeometry.swift`; workspace tree owns organization | `TileLayoutGeometryTest`, `LayoutMinimumFitTest`, `SingleWindowGeometryTest` | Unequal sizes, application minima and nested layouts work without moving workspace ownership |
| Gesture routing | `mouse/WorkspaceGestureCoordinator.swift` and recognizer/router; `ui/gestures` for presentation | `WorkspaceGestureRouterTest`, `WorkspaceTransitionTest` | Cancellation and stale completion are covered; physical gesture feel is checked separately |
| Native border bridge | `ui/borders/WindowBorderController.swift`, `Sources/PrivateApi/border.m` | `WindowBorderPiecesTest` | Unsupported API behavior has a fallback; native resource cleanup and actual surfaces are checked |
| Build, release or signing | `script/fork-build.sh`, `project.yml`, `makefile`; follow fork maintenance | `make check` and the affected Python release tests | Generated outputs are reviewed separately; identity/config/recovery remain intact; build is not reported as installation |

Run a relevant filter with `swift test --no-parallel --filter <Filter>`. Read
[Testing](TESTING.md) for setup and the full gate. Workspace changes also use
[behavior examples](WORKSPACE_BEHAVIOR.md).

The `resources/`, `script/`, `project.yml` and `makefile` paths are repository-root
paths. For schema work, `parseConfig.swift` is the source of truth; `testSchemaListsExactlyTheParserRootKeys` keeps the schema in step.
For gestures, read [swipe performance](SWIPE_PERFORMANCE.md). For build changes, read
[fork maintenance](FORK.md) and [HACKING](../HACKING.md). The table is a starting map,
not an exhaustive catalog: use `rg --files` and `rg` when a file or symbol has moved.

## When a check fails

Distinguish compiler/setup errors, assertion failures and native behavior failures.
Read the first relevant error and the complete failing test. Compare expectations
with the user's requested behavior and current policy before changing production.
A newly written assertion can be wrong.

Use documented setup for missing dependencies. Reproduce a suspected existing
failure on an unchanged isolated baseline before calling it pre-existing. Do not
weaken assertions, skip failures, rerun until green or change dependency versions
solely to obtain a successful result.

If intended behavior is ambiguous, complete independent investigation and ask a
specific behavior question. Report environment blockers with the command, error,
completed checks and remaining work. Build, test, installation and desktop
validation are separate outcomes.

Stop broadening verification once the required checks pass unless a new change,
failure or unresolved concern justifies more work. Do not turn a small fix into a
general refactor. In a shallow clone, historical example commits may be absent;
use the linked current files or retrieve that commit if history is needed.

## Examples to study

These illustrate specific techniques, not blanket approval of every historical
implementation. Current testing guidance takes precedence over old patterns.

- **Focused native eligibility change:** inspect `git show cadf5f2c -- Sources/PrivateApi/border.m Sources/AppBundle/ui/borders/WindowBorderController.swift Sources/AppBundleTests/ui/WindowBorderPiecesTest.swift`.
  It separates a testable classification rule from native queries and retains a
  fallback when the private query is unavailable. Predicate tests do not certify
  actual WindowServer behavior on every OS.
- **Ordered asynchronous saves:** read `Sources/AppBundleTests/ui/SettingsSaveQueueTest.swift`,
  especially `testScalarRawAndShortcutSavesShareOneOrderedQueue`. It injects access,
  holds an operation behind a gate, asserts observable order and releases the gate
  in cleanup. Bounded expectations establish completion without guessing via sleeps.
- **Ownership and rejection:** read `Sources/AppBundleTests/command/MonitorWorkspaceNavigationTest.swift`,
  especially `testSidebarOverrideBringsWorkspaceToDestinationWithoutSwapping` and
  `testOverrideRefusesToMoveAWorkspaceAssignedElsewhere`. Check
  source, destination and unaffected displays, including rejected operations.

For preservation tests, assert live state: captured objects can remain intact even
if the application replaces them with a different tree.

## Completion report

State what changed and why, then report actual commands and results, nonzero test
counts, failures/skips and any remaining limitation. Report desktop checks separately.
Do not infer success from a truncated log or native correctness from mocks.
Documentation-only work reports link, example and formatting checks instead of
unrelated runtime tests.
