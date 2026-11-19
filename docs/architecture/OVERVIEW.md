# Overview

## Plain English overview

Observed: WinMuxX maintains virtual workspaces of real application windows; it is not a manager for macOS Spaces. Each display shows a workspace, and hidden workspaces' windows are parked away from the visible desktop. A workspace belongs to a project and carries a window tree and arrangement. Selecting and moving are different: ordinary selection preserves display ownership, while explicit relocation changes it. See [principles](../PRINCIPLES.md) and [workspace examples](../WORKSPACE_BEHAVIOR.md).

The app observes macOS and accepts commands, reconciles its model, computes frames, and asks external apps to move or resize. The operating system and those apps can refuse or change that state. The workspace model and native desktop consequently cannot be treated as a single transaction. Configuration is TOML; restart snapshots and frame recovery are separate stores.

## Architectural rules

Existing project rule: selection MUST preserve display ownership; explicit moves MUST preserve workspace organization. Existing: TOML owns user preferences. Proposed: changes SHOULD isolate policy and geometry from native effects, and MUST NOT represent failed AX writes as applied.

## Technical reference

`WinMuxRuntime` composes registry, configuration, focus and refresh state ([source](../../Sources/AppBundle/runtime/WinMuxRuntime.swift)). `WorkspaceMonitorAssignment` applies selection and relocation ([source](../../Sources/AppBundle/tree/WorkspaceMonitorAssignment.swift)). `refresh` reconciles observations and runs layout ([source](../../Sources/AppBundle/layout/refresh.swift)); `layoutRecursive` applies frames ([source](../../Sources/AppBundle/layout/layoutRecursive.swift)). `MacApp` and `MacWindow` bridge AX and native applications ([MacApp](../../Sources/AppBundle/tree/MacApp.swift), [MacWindow](../../Sources/AppBundle/tree/MacWindow.swift)). Master is a fourth workspace arrangement, alongside Dwindle, Tabbed and Scrolling.

## Failure modes

A nonresponsive app can miss a refresh step; the next refresh may retry, not guarantee recovery. Disconnected displays and ambiguous restart identities are handled conservatively; detailed limits and tests are in [state](STATE.md) and [audit](AUDIT.md). Automated mocks do not prove real window movement.

## Open questions

Unknown: physical behavior across all macOS releases, display topologies and third-party applications. Existing architectural intent is not proof that all paths enforce it.
