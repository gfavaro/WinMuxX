# ADR-001: Virtual workspaces and display ownership

- Status: Observed
- Date: 2026-11-19 (recorded; not the original decision date)

## Context
Users need a portable unit of work across displays. Native apps own their windows. Displays can change.

## Decision
WinMuxX manages virtual workspaces, parks hidden windows and distinguishes ordinary selection from explicit relocation. A display viewport tracks the active workspace per display. [Principles](../../PRINCIPLES.md) specify the user contract.

## Why this approach
Observed benefit: a workspace can retain its organization while displayed elsewhere. The original complete decision history is unknown.

## Alternatives considered
Unknown historically. Native macOS Spaces is a conceivable alternative, but there is no evidence here that this project made a formal comparison for this decision.

## Consequences
The app reconciles native window placement and owns workspace/display policy. It does not control native Spaces as its workspace backend.

## Risks
External applications may reject or change frames. Disconnection and conflicting display identities complicate ownership.

## Source references
[Assignment](../../../Sources/AppBundle/tree/WorkspaceMonitorAssignment.swift), [registry](../../../Sources/AppBundle/tree/WinMuxWorkspaceState.swift), [tests](../../../Sources/AppBundleTests/command/MonitorWorkspaceNavigationTest.swift).
