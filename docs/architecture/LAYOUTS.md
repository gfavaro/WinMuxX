# Layouts and transitions

## Plain English overview

Observed: each workspace selects an arrangement. Nested containers can also have layout modes. Dwindle splits space recursively. Tabbed presents selected windows in groups. Scrolling places groups along a horizontal strip that can move. Master gives one group a main area. These are not implementations of one common layout protocol. Shared traversal, workspace membership, focus, native writes and recovery surround arrangement-specific behavior. The [user layout guide](../LAYOUTS.md) describes controls and configuration.

## Architectural rules

Existing project rule: workspace moves MUST retain nested organization. Proposed: switching arrangements MUST preserve membership and recoverable state where practical, and repeated calculation SHOULD be stable for unchanged inputs. These are desired contracts, not proof that all paths enforce them.

## Technical reference

Depending on the mode, inputs include a workspace tree, usable display rectangle, gaps, configuration, minimum window sizes and current focus. Each mode ultimately produces frame operations via [layoutRecursive](../../Sources/AppBundle/layout/layoutRecursive.swift). Native apps can reject the result. Floating and minimized windows follow shared model/visibility handling, not ordinary tiled geometry.

| Arrangement | Observed state, ordering and behavior | Coverage starting point |
| --- | --- | --- |
| Dwindle | Recursive container splits use `DwindleLayoutGeometry`, ratios, orientation, minimums and tree order; directional focus and resize consult the tree. Insertions and removal alter that tree; nested tab groups and floating windows require separate handling. Activation and display changes recalculate using the workspace's current usable area. | [geometry](../../Sources/AppBundle/layout/DwindleLayoutGeometry.swift), [tree](../../Sources/AppBundle/tree/WorkspaceDwindle.swift), [focus](../../Sources/AppBundle/tree/DwindleDirectionalFocus.swift), [test](../../Sources/AppBundleTests/command/DwindleParityTest.swift) |
| Tabbed | `TabbedWorkspaceState` retains group layout, last group, last focused ID and presented layout; `TabbedGroups` synchronizes groups with live windows. Traversal computes group frames and active content; focus commands update selection. Adding/removing windows needs synchronization. Display changes recompute frames; saved frozen group structure is restored against matched windows, missing windows are pruned. | [state](../../Sources/AppBundle/tree/TabbedWorkspaceState.swift), [groups](../../Sources/AppBundle/tree/TabbedGroups.swift), [test](../../Sources/AppBundleTests/command/WorkspaceTabbedArrangementTest.swift) |
| Scrolling | Workspace state holds offset, anchor, focus hint, pin and gesture session. Tree-derived columns and widths form a strip; the Scrolling viewport clips/conceals offscreen columns, and focus can adjust offset. Widths and display changes recalculate and anchor the Scrolling viewport. A horizontal Dock swipe moves the strip, then selects focus on release. Adding/removing groups changes strip metrics. Only an active Scrolling arrangement's offset is saved in `FrozenWorkspace`; runtime anchor and gesture session are not the same persistence contract. | [state](../../Sources/AppBundle/tree/ScrollingWorkspaceState.swift), [strip](../../Sources/AppBundle/tree/ScrollingWorkspace.swift), [swipe](../../Sources/AppBundle/mouse/ScrollingDockSwipe.swift), [test](../../Sources/AppBundleTests/layout/ScrollingGeometryTest.swift) |
| Master | Workspace tracks main group and ratio; shared tree groups retain their nested structure. | [implementation](../../Sources/AppBundle/tree/MasterLayout.swift) |

`transitionArrangement` cancels strip gesture state, can wrap the root to support columns, and synchronizes Tabbed groups; it sets the most recent tab when entering and preserves per-workspace state in memory. `preservesTopLevelGroups` changes later Dwindle interpretation. This combines preservation and reconstruction. It is not a byte-for-byte reversible transform. Saved state includes arrangement, tree, Tabbed structure and conditional Scrolling offset ([transition](../../Sources/AppBundle/tree/MasterLayout.swift), [snapshot](../../Sources/AppBundle/tree/frozen/closedWindowsCache.swift)). Restore depends on identity matching. Failures and missing applications can result in incomplete reconstruction. Unknown: exact preservation for every combination of floating, minimized and nested groups; add targeted round-trip tests before changing it.

A workspace arrangement selects the workspace-wide policy. Each nested container still has its own mode. The recursive dispatcher handles tiles and Dwindle separately. Changing an arrangement does not imply that every nested container becomes Dwindle. See [dispatcher](../../Sources/AppBundle/layout/layoutRecursive.swift).

Logical focus is WinMuxX's selected window and workspace. Native focus is controlled by macOS and external apps, and refresh reconciles the two. Tabbed and Scrolling keep local focus hints for their presentation. These hints do not independently replace the logical or native focus. See [refresh](../../Sources/AppBundle/layout/refresh.swift), [Tabbed state](../../Sources/AppBundle/tree/TabbedWorkspaceState.swift), and [Scrolling state](../../Sources/AppBundle/tree/ScrollingWorkspaceState.swift).

### Candidate contract assessment

| Principle | Assessment | Evidence and recommended test |
| --- | --- | --- |
| Switch does not silently change membership | Partially enforced: transition preserves tree intent but can wrap/sync; no proof across all cases. Test live reachable windows before/after all pairwise transitions, including floating and minimized. |
| Layout does not own persistent identity | Partially enforced: shared restart matching owns identity, but Tabbed/Scrolling retain window IDs as hints. Test ID reuse and missing windows. |
| One focus authority | Partially enforced: logical/native focus reconciled with arrangement-specific hints. Test delayed native focus and group selection across transitions. |
| Recoverable state on transition | Partially enforced: runtime state retained; snapshot persists selected subset. Test restart from each mode after visiting others. |
| Layout state cannot corrupt other modes | Partially enforced: separate structs, shared tree and command branches still couple modes. Test mixed-mode edits and return. |
| No unbounded geometry drift | Proposed: pure helpers help but native minimums and rounding are external. Reapply unchanged inputs and compare bounded geometry. |
| Deterministic calculations | Partially enforced for pure geometry inputs; timing/native state are not deterministic. Test equal value inputs and explicit tie cases. |
| Avoid duplicate shared behavior | Proposed: inspect duplication before refactoring; test observable shared behavior. |
| Independently evolvable capabilities | Proposed: arrangement-aware commands and shared tree couple changes. Test unrelated modes when changing a mode. |

## Failure modes

Invalid or missing saved groups are handled leniently; unmatched windows can return through normal discovery rather than their old exact location. An AX frame failure can leave native geometry different from calculated geometry. Specific geometry and command tests above are not evidence of physical gesture feel or every transition.

## Open questions

Unknown: exhaustive activation/deactivation interactions and exact error paths for every mode under simultaneous display changes and window creation. No blanket guarantee of deterministic native placement is made.
