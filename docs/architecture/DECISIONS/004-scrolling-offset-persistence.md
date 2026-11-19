# ADR-004: Remember the Scrolling position across restarts

- Status: Accepted by the Product Manager
- Date: 2026-11-19

## Context
The restart snapshot saved a workspace's Scrolling offset only while Scrolling was the active arrangement. A workspace switched to another arrangement kept its offset in memory but lost it at restart (AUD-001).

## Decision
`FrozenWorkspace` always saves `scrollingState.offset`. Restore already applies a saved finite offset regardless of arrangement.

## Why this approach
It is the smallest change: the field and its restore path already existed, so only the save condition changed.

## Alternatives considered
Keep the conditional save (no work, but the position is forgotten). Save all per-arrangement state (larger, not needed).

## Consequences
Returning to Scrolling after a restart shows the strip where it was left. Snapshots stay compatible in both directions: the field was already optional, and older builds ignore a value they already understood.

## Risks
Windows can change while WinMuxX is not running, so a saved offset may be stale. The strip geometry clamps the offset to the current range, so it cannot point past the strip.

## Source references
[Snapshot](../../../Sources/AppBundle/tree/frozen/closedWindowsCache.swift), [clamp](../../../Sources/AppBundle/tree/ScrollingWorkspace.swift), [test](../../../Sources/AppBundleTests/command/MasterLayoutTest.swift).
