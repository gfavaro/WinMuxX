# Workspace behavior examples

These describe current behavior, not a ban on an explicitly requested change.
Swapping workspaces remains a separate product decision.
M is the main display, S a secondary display and T a third display. A, B and C are
workspaces. Unless stated otherwise, no forced assignment applies.

| Before and action | Expected result | Existing evidence |
| --- | --- | --- |
| A on M, B on S; ordinary selection of B requests M | B stays on S and receives focus there | `testSidebarFocusesWorkspaceOnItsExistingDisplay` |
| B hidden but owned by S; ordinary selection requests M | B activates on S; ownership is not inferred from the requesting display | `testHiddenWorkspaceSwitchKeepsItsOwningMonitor` in `WorkspaceCommandTest` |
| A on M, B on S, C on T; explicitly bring A to S | A becomes visible on S; M receives a same-project fallback; B is hidden and returns to M ownership where allowed; T retains C | `testSidebarOverrideBringsWorkspaceToDestinationWithoutSwapping` |
| A assigned to M in config; explicitly move A to T | Refused; nothing changes (as in AeroSpace) | `testOverrideRefusesToMoveAWorkspaceAssignedElsewhere` |
| C assigned to S in config; WinMuxX starts, then the user shows B on S, then selects C | C starts on S; B may replace it, C stays hidden on S, and selecting C shows it on S again. Moving or summoning C elsewhere is refused | `testStartupShowsAnAssignedWorkspaceWhichStaysOnItsDisplay` |
| C assigned to S in config; C hidden; select C from M | C shows on S | `testAssignedHiddenWorkspaceActivatesOnItsAssignedDisplay`, `testAnAssignedWorkspaceOpensOnItsDisplayFromAnyDisplay` |
| B on M; an assignment of B to T is added (reload) | B moves to T and keeps focus; M gets a fallback | `testAnAssignedWorkspaceShowingElsewhereMovesToItsDisplay` |
| B assigned to a display that is not connected | The assignment constrains nothing until it is | `testAnAssignmentToADisconnectedDisplayConstrainsNothing` |
| C assigned to S in config; WinMuxX restores a saved arrangement with B on S | B stays on S and C stays hidden there, unless Start workspaces on main display is on | `testARestoredWorldKeepsItsDisplaysWhereAssignmentsAllow` |
| Activate a sidebar row for a workspace on another display | The row may show bring-here confirmation; confirming or using its Bring Here context action explicitly relocates it | `WorkspaceSidebarWorkspaceSection.swift`; `WorkspaceSidebarOverrideTest` |
| Disconnect and reconnect a display | Reconcile valid active viewports and preserve surviving display history; do not promise physical restoration beyond tested behavior | `testDisconnectAndReconnectPreservesSurvivingDisplayHistory`; desktop checks still required |
| B on S; S disconnects and reconnects, possibly elsewhere in the arrangement | S shows B again, matched by display UUID; if the user showed B elsewhere meanwhile, B stays there and S gets a fallback | `testReconnectedDisplayShowsItsWorkspaceAgainEvenWhenRearranged`, `testReconnectedDisplayLeavesItsWorkspaceWhereTheUserShowedItMeanwhile` |
| A on M, B on S; M and S swap positions in the arrangement | Each display keeps its workspace | `testDisplaysThatSwapPositionsKeepTheirOwnWorkspaces` |
| A on M, B on S; S disconnects and the user swipes on M before the topology settles | B is hidden at once, so the swipe can show it on M; when S returns, B stays on M and S gets a fallback | `testSwipeRightAfterUnplugCanShowTheDisplaysWorkspaceWhichThenStaysAndTheStaleDeadlineDoesNothing` |
| A window of hidden C is missing after sleep or lock; the user selects B, then the window reappears | It returns to C, not the focused B; B stays selected | `testSelectionWhileWindowIsMissingKeepsItsWorkspaceAndTheSelection` |

Unnamed test classes above refer to `Sources/AppBundleTests/command/MonitorWorkspaceNavigationTest.swift`.
`WorkspaceCommandTest.swift` is in that directory. `WorkspaceSidebarOverrideTest.swift`
is under `Sources/AppBundleTests/ui`; sidebar source is under `Sources/AppBundle/ui/sidebar`.

Bringing A back is another explicit move. It does not imply that displaced B
automatically becomes visible on S. Consult `Sources/AppBundle/tree/WorkspaceMonitorAssignment.swift`
for fallback and assignment policy. A user request to swap should be treated as
an intentional behavior change, with expectations updated accordingly.

## Preservation and desktop checks

Retain workspace identity, project membership, nested organization, tab membership
and floating-window membership. Pixel coordinates can change to fit usable display
area and application minimum sizes. Check the live root and reachable descendants,
source fallback, displaced owner and unaffected display.

On the desktop, move a populated workspace between unequal displays and back.
Inspect focus, tab interaction and floating windows. Exercise startup assignment
and disconnect/reconnect when affected. Model tests do not establish native
Accessibility behavior or physical display restoration.
