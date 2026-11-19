# Domain model

## Plain English overview

Observed: a project groups workspaces. A workspace is a portable unit containing windows and nested containers; a display viewport chooses which workspace is visible. A window belongs to another application and is managed through an Accessibility representation. The display, operating system and external app remain authoritative for their physical state. Window membership includes exceptional minimized and popup containers, so “every window is always in a workspace tree” is too strong.

## Architectural rules

Existing project rule: ordinary selection MUST NOT silently relocate a workspace; an explicit move MUST carry organization and identity. Proposed: a managed window SHOULD have an explainable context including minimized/popup exceptions. Workspace owns window organization / layout owns presentation is **partially descriptive, not an established clean boundary**: layout transitions and arrangement-specific commands also reshape or synchronize organization. A migration would need to preserve nested groups, focus, geometry and saved snapshots; no migration is approved here.

## Technical reference

| Entity | Observed ownership / identity | Evidence |
| --- | --- | --- |
| Display | `Monitor` represents current screen; UUID identifies a physical display when available, while `MonitorViewportId` is its top-left point; visible/usable rect drives layout. | [Monitor](../../Sources/AppBundle/model/Monitor.swift), [identity](../../Sources/AppBundle/tree/WorkspaceIdentity.swift) |
| Workspace/project | `Workspace` has generated runtime ID, name, project, lifecycle, preferred monitor point, tree and arrangement. Do not assume its generated ID is a permanent restart identity. | [Workspace](../../Sources/AppBundle/tree/WorkspaceType.swift), [registry](../../Sources/AppBundle/tree/WinMuxWorkspaceState.swift) |
| Application/window | `MacApp` owns native access; live windows use WindowServer `UInt32` IDs. Restart matching also considers bundle, process launch, title, document and AX identifier, with ambiguity rejection. | [MacApp](../../Sources/AppBundle/tree/MacApp.swift), [matching](../../Sources/AppBundle/tree/frozen/RestartWindowIdentity.swift) |
| Layout | Workspace arrangement selects Dwindle, Tabbed, Scrolling or Master; nested `TilingContainer` modes are a different level. | [workspace](../../Sources/AppBundle/tree/WorkspaceType.swift), [traversal](../../Sources/AppBundle/layout/layoutRecursive.swift) |
| Focus | Runtime focus/history and native focus are reconciled; Tabbed and Scrolling keep additional focus hints, not independently durable identities. | [runtime](../../Sources/AppBundle/runtime/WinMuxRuntime.swift), [Tabbed](../../Sources/AppBundle/tree/TabbedWorkspaceState.swift), [Scrolling](../../Sources/AppBundle/tree/ScrollingWorkspaceState.swift) |
| Viewport/floating | A monitor viewport selects an active workspace; a Scrolling viewport is a separate horizontal offset. Floating windows are workspace children outside tiled container geometry. | [registry](../../Sources/AppBundle/tree/WinMuxWorkspaceState.swift), [window](../../Sources/AppBundle/tree/Window.swift) |
| State | Live tree and derived geometry coexist with frozen restart data, recovery frames and configuration. | [state](STATE.md) |

## Failure modes

Reused IDs, missing AX metadata, UUID ambiguity, unavailable screens, and a window that rejects geometry can defeat a naive identity or placement assumption. Matching tests and monitor tests are starting evidence, not a macOS guarantee.

## Open questions

Unknown: whether all workspace rename/restart paths preserve the same user-facing identity in every case; trace the specific path before relying on runtime IDs. Verify behaviors for app-specific transient and hidden windows on a real desktop.
