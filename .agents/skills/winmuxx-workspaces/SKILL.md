---
name: winmuxx-workspaces
description: Implement or review WinMuxX workspace lifecycle, selection, display ownership, summon, and whole-workspace moves. Use for changes to these behaviors, including sidebar routing.
---

# Workspace and display changes

Read [core principles](../../../docs/PRINCIPLES.md) and the ownership section in
[HACKING](../../../HACKING.md). Resolve these paths from this skill directory.

Trace the requested action from its command or sidebar adapter into
`Sources/AppBundle/tree/WorkspaceMonitorAssignment.swift`. Distinguish ordinary
selection, explicit relocation, configured assignment and startup restoration.
An already-owned hidden workspace also retains its display during selection. A
configured assignment overrides ownership while its display is connected, as in
AeroSpace: selection shows it there and moves elsewhere are refused.

## Current behavior and entry points

Read [workspace behavior examples](../../../docs/WORKSPACE_BEHAVIOR.md) for concrete
selection, movement, rejection and topology cases. These describe today's behavior,
not a prohibition on an explicitly requested change. Bring Here already exists;
check the code before assuming a new action is needed. The
[task map](../../../docs/CONTRIBUTOR_TASKS.md) identifies entry points, completion
criteria, examples and how to handle failures.

## Implementation and verification

Inspect the relevant workspace identity, lifecycle and persistence code before
changing ownership. Preserve the workspace tree and project identity; adapt frame
geometry to the destination rather than rebuilding the user's organization.
Account for source fallback, destination displacement, focus history, minimized
windows and startup-only assignments where the requested change affects them.

For fixture-based monitor assertions, compare the established monitor identifier or
`rect.topLeftCorner` representation used by that suite. `Monitor` is a protocol;
do not assume it supports Swift class identity (`===`). Workspace and tree objects
can use identity assertions when preservation of those live objects is intended.

Use the existing command tests as starting points:

- `Sources/AppBundleTests/command/MonitorWorkspaceNavigationTest.swift`
- `Sources/AppBundleTests/ui/WorkspaceNamingTestMonitorAssignment.swift`
- `Sources/AppBundleTests/command/SummonWorkspaceCommandTest.swift`
- `Sources/AppBundleTests/command/WorkspaceCommandTest.swift`

Follow [Testing](../../../docs/TESTING.md) for runtime fixtures and serial suite
execution. Assert resulting ownership and layout on both displays, including
unaffected workspaces. For asynchronous paths, exercise cancellation or stale
completion when it can change the result.

Useful focused commands, run from the repository root:

```sh
swift test --no-parallel --filter MonitorWorkspaceNavigationTest
swift test --no-parallel --filter WorkspaceCommandTest
swift test --no-parallel --filter WorkspaceSidebarOverrideTest
```

Run the subset relevant to the change, then the required `make check` gate. Confirm
the filter executed tests. If piping output, preserve the test command's exit status
with `pipefail`; a successful `tail` or `tee` does not establish test success.

When checking layout preservation, inspect the live workspace root and its reachable
children after the operation. Captured references to an old tree can remain intact
even if the workspace now uses another tree. Assert window membership, tab layout
and floating parentage, plus source fallback and displaced-owner visibility. A
failing test is a reason to compare expectations with the requested behavior and
existing policy before changing production code. For a requested mutation trial,
temporarily break the invariant being tested, verify the relevant assertion fails,
and restore production code before the final passing run.

Membership and layout mode are separate assertions. For example, unchanged
`tabs.children` does not prove `tabs.layout == .tabGroup`: the same children can
remain after a bug changes the container to tiles. Check both, including on a
rejected operation that promises no state change. Before reporting completion,
compare each acceptance condition with an assertion or explicitly recorded manual
check; a passing suite cannot establish an invariant the test never observes.

Do not infer tested multi-display behavior from another project's API signatures.
For manual validation, move a populated workspace to another display and back;
check organization, focus and both displays' resulting workspaces. Report manual
checks separately from automated results and do not imply installation from a build.
