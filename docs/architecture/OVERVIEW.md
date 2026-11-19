# Overview

## Plain English overview

Observed: WinMuxX maintains its own virtual workspaces for real application windows. It does not manage macOS Spaces. Each display shows a workspace. WinMuxX moves windows on hidden workspaces away from the visible desktop. A workspace belongs to a project. It contains a window tree and has an arrangement. Ordinary selection preserves display ownership. An explicit move changes display ownership. See [principles](../PRINCIPLES.md) and [workspace examples](../WORKSPACE_BEHAVIOR.md).

The app observes macOS and accepts commands. It reconciles its model with observations, computes window frames, and asks other apps to move or resize their windows. The operating system and those apps can refuse or change that state. The workspace model and native desktop consequently cannot be treated as a single transaction. Configuration uses TOML. Restart snapshots and frame recovery use separate stores.

A connected forced display assignment takes precedence over ordinary selection and rejects incompatible explicit moves. A move can replace the destination workspace. The policy chooses a source fallback and reconciles displaced secondary assignments. The [workspace examples](../WORKSPACE_BEHAVIOR.md) describe these cases.

## Architectural rules

Existing project rule: selection MUST preserve display ownership; explicit moves MUST preserve workspace organization. Existing: TOML owns user preferences. Proposed: changes SHOULD isolate policy and geometry from native effects, and SHOULD NOT represent failed AX writes as applied.

## Technical reference

`WinMuxRuntime` composes registry, configuration, focus and refresh state ([source](../../Sources/AppBundle/runtime/WinMuxRuntime.swift)). `WorkspaceMonitorAssignment` applies selection and relocation ([source](../../Sources/AppBundle/tree/WorkspaceMonitorAssignment.swift)). `refresh` reconciles observations and runs layout ([source](../../Sources/AppBundle/layout/refresh.swift)); `layoutRecursive` applies frames ([source](../../Sources/AppBundle/layout/layoutRecursive.swift)). `MacApp` and `MacWindow` bridge AX and native applications ([MacApp](../../Sources/AppBundle/tree/MacApp.swift), [MacWindow](../../Sources/AppBundle/tree/MacWindow.swift)). Master is a fourth workspace arrangement, alongside Dwindle, Tabbed and Scrolling.

## Failure modes

An app that does not respond can miss a refresh step. The next refresh may retry that step, but recovery is not guaranteed. Disconnected displays and ambiguous restart identities are handled conservatively; detailed limits and tests are in [state](STATE.md) and [audit](AUDIT.md). Automated mocks do not prove real window movement.

## Open questions

Unknown: physical behavior across all macOS releases, display topologies and third-party applications. Existing architectural intent is not proof that all paths enforce it.
