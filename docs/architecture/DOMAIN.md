# Domain model

## Plain English overview

Observed: a project groups workspaces. A workspace contains windows and nested containers and can move between displays. A display viewport chooses which workspace is visible. A window belongs to another application. WinMuxX manages it through an Accessibility representation. The display, operating system and external app remain authoritative for their physical state. Window membership includes exceptional minimized and popup containers, so “every window is always in a workspace tree” is too strong.

## Glossary

These are the preferred terms in the architecture documents. Swift identifiers
retain their exact source spelling. A *monitor* in a Swift identifier refers to a
display; use **display** in explanatory text.

| Term | Meaning |
| --- | --- |
| **Display** | A physical screen and its current geometry. Layout uses its usable area and configured gaps. |
| **Workspace** | A WinMuxX-managed unit of work that contains windows and nested containers. It belongs to a project and has an arrangement and display relationship. It is distinct from a macOS Space. |
| **Window** | An application-owned window that WinMuxX can observe and manage through macOS APIs. |
| **Window identity** | The evidence used to distinguish a window. A live WindowServer ID is not by itself a permanent restart identity. Restart matching can also use process and window metadata. |
| **Layout** | The calculation and application of window positions and sizes. A workspace **arrangement** selects its overall layout behavior; a nested container can also have a layout mode. |
| **Viewport** | A context that selects or shows part of something. A **display viewport** tracks the active workspace on a display. A **Scrolling viewport** is the visible portion of the horizontal strip and has an offset. These are different concepts. |
| **Focus** | The window or workspace selected for interaction. WinMuxX tracks logical focus and reconciles it with native macOS focus. |
| **Floating window** | A window outside ordinary tiled-container geometry. It remains associated with its workspace. |
| **Runtime state** | Information held in memory while WinMuxX runs, such as the live workspace registry and focus history. |
| **Persisted state** | Information saved for later use, including restart snapshots and recovery data. It is separate from the live model and from TOML preferences. |
| **Layout state** | Information an arrangement or container uses to present windows, such as split ratios, Tabbed groups or the Scrolling offset. Its lifetime and persistence depend on the field. |
| **Window frame** | A window's position and size. A calculated frame and the frame accepted by macOS or an application can differ. |
| **Reconciliation** | Comparing observations and the model, then making the updates or requests needed by the relevant path. It does not guarantee immediate agreement with macOS. |
| **Snapshot** | A saved representation of state at a particular time. A restart snapshot is distinct from the original-frame recovery journal. |

## Architectural rules

Existing project rule: ordinary selection MUST NOT silently relocate a workspace; an explicit move MUST carry organization and identity. Proposed: a managed window SHOULD have an explainable context including minimized/popup exceptions. Workspace owns window organization / layout owns presentation is **partially descriptive, not an established clean boundary**: layout transitions and arrangement-specific commands also reshape or synchronize organization. A migration would need to preserve nested groups, focus, geometry and saved snapshots. No migration is approved here.

## Technical reference

| Entity | Observed ownership / identity | Evidence |
| --- | --- | --- |
| Display | `Monitor` represents current screen; UUID identifies a physical display when available, while `MonitorViewportId` is its top-left point; visible/usable rect drives layout. | [Monitor](../../Sources/AppBundle/model/Monitor.swift), [identity](../../Sources/AppBundle/tree/WorkspaceIdentity.swift) |
| Workspace/project | `Workspace` has generated runtime ID, name, project, lifecycle, preferred display point, tree and arrangement. Do not assume its generated ID is a permanent restart identity. | [Workspace](../../Sources/AppBundle/tree/WorkspaceType.swift), [registry](../../Sources/AppBundle/tree/WinMuxWorkspaceState.swift) |
| Application/window | `MacApp` owns native access; live windows use WindowServer `UInt32` IDs. Restart matching also considers bundle, process launch, title, document and AX identifier, with ambiguity rejection. | [MacApp](../../Sources/AppBundle/tree/MacApp.swift), [matching](../../Sources/AppBundle/tree/frozen/RestartWindowIdentity.swift) |
| Layout | Workspace arrangement selects Dwindle, Tabbed, Scrolling or Master; nested `TilingContainer` modes are a different level. | [workspace](../../Sources/AppBundle/tree/WorkspaceType.swift), [traversal](../../Sources/AppBundle/layout/layoutRecursive.swift) |
| Focus | Runtime focus/history and native focus are reconciled; Tabbed and Scrolling keep additional focus hints, not independently durable identities. | [runtime](../../Sources/AppBundle/runtime/WinMuxRuntime.swift), [Tabbed](../../Sources/AppBundle/tree/TabbedWorkspaceState.swift), [Scrolling](../../Sources/AppBundle/tree/ScrollingWorkspaceState.swift) |
| Viewport/floating | A display viewport selects an active workspace. A Scrolling viewport is the visible area of the strip; its offset is separate state. Floating windows are workspace children outside tiled container geometry. | [registry](../../Sources/AppBundle/tree/WinMuxWorkspaceState.swift), [window](../../Sources/AppBundle/tree/Window.swift) |
| State | Live tree and derived geometry coexist with frozen restart data, recovery frames and configuration. | [state](STATE.md) |

## Failure modes

Reused IDs, missing AX metadata, ambiguous UUIDs, unavailable displays, or a window that rejects geometry can invalidate an assumption about identity or placement. Matching tests and display tests are starting evidence, not a macOS guarantee.

## Open questions

Unknown: whether all workspace rename/restart paths preserve the same user-facing identity in every case; trace the specific path before relying on runtime IDs. Verify behaviors for app-specific transient and hidden windows on a real desktop.
