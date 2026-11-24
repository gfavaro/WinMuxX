# ADR-007: Keep a workspace's display while that display is away

- Status: Proposed
- Date: 2026-11-24

## Context
Each saved workspace records the display it lives on, and each saved display records the workspace it shows. The record is rebuilt from the live state on every save. If a display is not connected when a save happens (still waking at launch, asleep, on a dock, unplugged), the workspace's display is resolved to the nearest connected one, and that is what gets written. The away display's own entry is dropped. The next launch, with the display back, then finds the workspace on the main display and creates a new workspace for the returning display.

Observed on 2026-11-24 (inference from the code and a display that was missing from the system's list minutes before it appeared; the earlier file was overwritten): a workspace that was on the secondary display came back on the main display, and a new one appeared on the secondary.

## Decision
Remember the display a workspace was placed on until the user changes it, even while that display is away.

- On restore, a workspace whose saved display is not connected keeps its saved display entry in memory (`homeDisplay`), together with that display's saved visible workspace.
- On save, a workspace with a `homeDisplay` whose display is still not connected is written with that saved display, not the fallback. The away display's entry stays in `monitors`.
- The `homeDisplay` is dropped when the user explicitly moves the workspace to a display, when the display returns (the live record takes over), or when the workspace is deleted.
- When a display returns, a workspace whose `homeDisplay` is that display goes back to it, and the display shows its saved visible workspace if that workspace still exists and is not shown elsewhere.
- Windows follow their workspace, as today.

## Why this approach
It keeps one rule: a workspace belongs to the display the user chose until the user chooses another. It adds no field to the file, because the saved `monitor` and `monitors` entries already hold the display and the visible workspace.

## Alternatives considered
Never prune an away display: simpler, but a display that is truly gone would keep workspaces off the main display for ever. Wait for all displays before restoring: the start would stall when a display never returns. Do nothing: the problem recurs whenever a display wakes late.

## Consequences
While a display is away its workspaces still show on the main display, as now. Saves keep their saved display. Explicit moves still win.

## Risks
A workspace stays assigned to a display that is never reconnected. Mitigation: the user can move it explicitly, which drops the remembered display; an entry is also dropped when none of its workspaces remain. Tests cover save, restore, return and explicit move.

## Verification plan
Unit tests for the save/restore of an absent display and for the return. A real test: sleep the secondary display, restart WinMuxX, wake the display, and check that each workspace is where it was.

## Source references
[Saved monitor](../../../Sources/AppBundle/tree/frozen/closedWindowsCache.swift), [Saved envelope](../../../Sources/AppBundle/tree/frozen/persistedFrozenWorld.swift), [Workspace display](../../../Sources/AppBundle/tree/WorkspaceType.swift).
