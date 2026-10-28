# Workspace backend boundaries

This describes the `feat/native-spaces` implementation. The virtual backend remains
the default; this document does not change behavior or propose a migration.

## Composition and operations

`WinMuxRuntime` owns `WorkspaceBackendState`, which selects and locks one backend at
startup. The AppBundle `WorkspaceBackend` contract routes commands and exposes
workspace queries, focus and geometry behavior. It still uses concrete AppBundle
`Command`, `CmdEnv`, `CmdIo`, `Workspace`, `Monitor` and `Window` types. Separately,
`WorkspaceBackendUI` composes native or virtual sidebar projection/actions, project
grouping, palette extras and tray behavior. It uses AppBundle UI types and the same
runtime binding, and is not an independent module.

The similarly named operations have different effects:

| Operation | Implementation and effect |
| --- | --- |
| Virtual workspace selection | `activateWorkspaceForUser` selects within the virtual model and retains display ownership. `activatesVirtualWorkspaces` gates that mechanism, virtual navigation gestures and sidebar-hover activation. |
| Virtual workspace relocation | Explicit monitor move/summon changes ownership through `WorkspaceMonitorAssignment`, with destination displacement and source fallback. `relocatesVirtualWorkspaces` gates the virtual move section in Settings. |
| Native desktop selection | `NativeSpaceNavigator.selectDesktop` resolves a current desktop or retained UUID and asks the Dock to switch; it checks fresh topology and landing. It does not use the virtual activation capability. |
| Native window transfer | `NativeWindowSpaceMoves.transferWindow` moves a window to a native desktop or a display's showing desktop, with arrival confirmation. |
| Native desktop-content transfer | `transferDesktopContents` moves windows and their layout to the destination display's showing desktop. The source macOS desktop itself stays on its display; partial arrival is reported. It is not virtual workspace relocation. |

`NativeCommandPolicy` preserves command admission and the native tiling fence;
actual native availability, permissions, observation and tiling determine whether an
operation can proceed. The virtual capability flags do not claim that native Space
switching or native content transfer is unavailable. CLI and config names are unchanged.

## Native lifecycle and target boundary

`NativeWorkspaceLifecycle` owns observation, navigation, transfers, layout projection,
window reconciliation, write authority, tiling, activity/focus state, UUID-keyed
layout persistence and the cancelable desktop top-up. The existing `NativeSpaces`
Swift target supplies snapshots, observation, pure navigation and desktop top-up
planning, and SkyLight/Dock bridges. AppBundle consumes the top-up plan; creation,
timer ownership, configuration and reconciliation remain in AppBundle. The target
does not own the AppBundle workspace tree.

`NativeSpaceLayouts` maps observed UUIDs to shared `Workspace` objects and
`NativeWindowReconciler` adopts AX windows. The tiling coordinator, persistence and
UI depend on those objects, config, monitors, focus and process-lifetime AppKit/AX
services. `NativeOriginalFrames`, `NativeScrollingPan` and `NativeObservationChrome`
remain process-level owners outside the lifecycle. These dependencies prevent moving
the full backend to an independent target merely by moving files. A further module
split needs interfaces for those dependencies; there is no duplicate workspace or
window model here.

Config reload chooses the backend before selection is locked and rejects a live
backend/tiling change after startup. Native startup records existing windows and
starts observation; virtual startup loads its frozen world, initializes workspaces,
restores placement and starts its regular observers. Native observation invalidates
write authority and tiling before reconciling, then notifies waiters and schedules
bounded top-up reads. Disable cancels top-up and restores native frames before
stopping shortcuts; re-enable requests a fresh observation. Shutdown cancels owned
work and invalidates observation and writes. Virtual recovery and parking remain
capability-gated and are not used by native mode.

`WinMuxRuntime.withValue` supplies the task-local runtime binding. Native observer
callbacks explicitly rebind their originating owner; its tasks retain that binding.
Generation checks and cancellation remain with their existing coordinators. Native
Space identity is a UUID, while desktop numbers follow current observed ordering.
