# ADR-006: Use the last window frame to tell identical windows apart on restore

- Status: Proposed (awaiting Product Manager approval)
- Date: 2026-11-23

## Context
After an app relaunches, a saved window is matched to a live one by document, accessibility identifier and title (ADR-002). Windows of one app that share all three, such as two windows of a remote-desktop app, cannot be told apart. With two saved and two live windows the match is refused, so each window follows the new-window rules and one can land in another workspace. Observed on 2026-11-23: after an install, one of two identical windows moved from workspace 3 to 5.

## Decision
Add an optional `frame` (the window's last known position and size) to the saved restart identity, and use it only to break ties.

- The saved file gains one optional field per window. A file without it still loads, and an older build ignores it. No version bump and no migration.
- Matching is unchanged while the existing evidence picks a single window. Only when several saved windows of one app tie, and the live windows of that app are unmatched, does the new step run.
- Step 1: pick the saved window whose frame is within 8 points of the live window's frame on every edge, if exactly one is.
- Step 2: if frames do not decide, and the number of tied saved windows equals the number of unmatched live windows of that app, pair them in window-id order (creation order).
- Anything still ambiguous stays unmatched, as today.

## Why this approach
A frame is already known when the state is written, and apps normally reopen windows where they were. The rule only acts where today's answer is "refuse", so it cannot override a match the current evidence makes.

## Alternatives considered
Match only by creation order (no schema change, but wrong when apps reopen windows in another order). Save a hash of the title (still ambiguous for identical titles). Do nothing (the windows stay mismatched).

## Consequences
A saved window's frame is written to `window-state.json`. This is geometry, not content; titles are unchanged. Window ids are only compared within one app's tied windows.

## Risks
Two windows swapped in place would pair wrongly. Mitigation: it needs both an exact tie in existing evidence and an unambiguous frame or order match, and the result is the same as today's worst case (a window in the wrong workspace). Tests cover the tie, the frame match, the order fallback and the loading of an older file.

## Verification plan
Unit tests for the matcher and the file loading; a real restart with two windows of one app.

## Source references
[Matcher](../../../Sources/AppBundle/tree/frozen/RestartWindowIdentity.swift), [restore](../../../Sources/AppBundle/tree/frozen/persistedFrozenWorld.swift), [ADR-002](002-restart-identity.md).
