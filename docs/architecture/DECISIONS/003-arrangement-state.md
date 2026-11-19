# ADR-003: Workspace arrangement state

- Status: Observed
- Date: 2026-11-19 (recorded; not the original decision date)

## Context
One workspace can be displayed through different arrangements, including a gesture-controlled scrolling strip.

## Decision
The workspace holds arrangement choice, tree and separate Tabbed, Scrolling and Master state. The snapshot records a subset including Tabbed layout and the Scrolling offset (saved in every arrangement since [ADR-004](004-scrolling-offset-persistence.md)).

## Why this approach
Observed code retains arrangement-specific state across in-memory switches. History `a061ee4a` says Scrolling state became a value to make previews save and restore it together without changing the restart format.

## Alternatives considered
Unknown historically. A common layout interface or persisting all per-mode state is conceivable but has not been accepted here.

## Consequences
Modes can retain distinct behavior, but transitions and shared commands must reconcile with a common tree. Retention in memory does not imply persistence across restart.

## Risks
Cross-mode regressions and conditional offset persistence deserve focused tests. The product behavior also needs clarification.

## Source references
[Workspace](../../../Sources/AppBundle/tree/WorkspaceType.swift), [transition](../../../Sources/AppBundle/tree/MasterLayout.swift), [snapshot](../../../Sources/AppBundle/tree/frozen/closedWindowsCache.swift).
