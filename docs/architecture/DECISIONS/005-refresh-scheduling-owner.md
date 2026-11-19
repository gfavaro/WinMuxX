# ADR-005: Refresh scheduling rules live in RefreshCoordinator

- Status: Accepted by the Product Manager
- Date: 2026-11-19

## Context
`refresh.swift` mixed three jobs: deciding when a refresh runs, running it, and handling AX notifications. The state was in `RefreshCoordinator`, but the rules were in `refresh.swift`, reached through accessor shims. Five of the 11 refresh, lifecycle and focus fixes from 2026-09-20 to 2026-11-19 changed those scheduling rules, and the rules were tested only through whole refreshes.

## Decision
Move the scheduling rules into `RefreshCoordinator` with no change in behavior: `admit` (drop, coalesce or start), `finishScheduled`, `beginLight`, `owedAfterLight`, `queueFollowUp`, `shouldDrop` and `merge`. `refresh.swift` keeps task creation, event recording, logging, the session bodies and AX notification handling.

## Why this approach
The rules become one small unit with direct tests, and the event processing, ordering and outcomes stay the same.

## Alternatives considered
Leave the rules in place (cheaper, but they stay untested on their own). Rewrite refresh as an explicit state machine (larger, and not justified by the evidence).

## Consequences
New scheduling rules go in `RefreshCoordinator` with a test in `RefreshCoordinatorPolicyTest`. Session bodies and AX handling are unchanged.

## Risks
A subtle ordering difference in the move. Mitigation: the code was moved without reordering steps, and all existing refresh and overlapping-event tests pass.

## Source references
[Coordinator](../../../Sources/AppBundle/runtime/RefreshCoordinator.swift), [refresh](../../../Sources/AppBundle/layout/refresh.swift), [policy tests](../../../Sources/AppBundleTests/runtime/RefreshCoordinatorPolicyTest.swift).
