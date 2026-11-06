# Dwindle comparison — updated 2026-10-05

Compared WinMuxX with Dinky commit
[`d488ce74`](https://github.com/mikker/Dinky/tree/d488ce74eb1ec4319409118f56caebd88844fac6).
The current parity fixtures were obtained by compiling and running that actual
DinkyLayout engine. Runtime Accessibility validation is separate.

## Explicit-tree parity update

Dwindle now uses explicit, oriented containers with normalized sibling shares.
Legacy implicit spines and nested tiles migrate into that representation without
resetting their splits. Snapshot decoding remains backward compatible; new
snapshots persist sibling shares as well as the chosen orientation.

Insertion into a matching-axis parent gives the new child `1/(n+1)` and scales
old siblings proportionally. Otherwise it wraps the focused slot in a two-child
container. Removal redistributes within the affected parent. Normalization
promotes a remaining container with its own axis and ratios, and splices matching
fixed axes proportionally. Moving outside the root retains the Dwindle policy.

Keyboard resize rescales all other siblings proportionally; a mouse edge resize
transfers only to the adjacent sibling. `balance-sizes` equalizes each container;
flattening retains DFS order and equalizes the flattened sibling list. Slot swaps
preserve sibling shares. Tab groups remain a WinMuxX-specific feature.

`DwindleReferenceParityTest` checks Dinky's exported golden frames for same-axis
insertion, keyboard resize plus insertion/removal, a four-window spiral and root
promotion (within one point for rounding). Additional tests cover mouse-edge
transfers and limits, legacy migration, and snapshot round trips. This is evidence
for those sequences, not a claim that every OS interaction has been validated.

The sections below record the earlier implicit implementation and its fixes.

## Delivered in this change

WinMuxX now stores a ratio for each implicit dwindle split, defaulting to 50/50.
`resize width`, `height`, `smart` and `smart-opposite` select the nearest relevant
split, including nested tiles. Mouse edge resizing updates those same ratios.
Live layout and resize previews share geometry. Ratios are constrained to 10–90%,
and feasible learned minimums reserve space for both sides. When minimums cannot
fit, the requested distribution remains the fallback.

`balance-sizes` resets dwindle ratios and recursively balances tiles without
changing order, focus or tab-group membership. It no longer writes tile weights
to dwindle children, which caused the reported crash. Ratios survive frozen-world
serialization/restoration; old snapshots default to 50/50.

Dinky stores normalized sibling ratios in an explicit container tree. WinMuxX
retains its existing implicit child-versus-remainder splits. Consequently, resetting
all splits to 50/50 does not mean every window has the same overall area.

## Implemented follow-ups

All eight original dwindle follow-ups were implemented. At that stage WinMuxX kept its implicit
child-versus-remainder tree; it does not copy Dinky's explicit sibling model.

| Area | WinMuxX behavior |
| --- | --- |
| Insertion | Uses the anchor's physical rectangle, falling back to virtual geometry before the first layout. A tiles parent with the same axis is reused; otherwise the anchor is wrapped. A tab group remains intact. Replacing a dwindle slot preserves its ratios. |
| Membership and ratios | Closing or moving a child out collapses its implicit binary split. Its sibling/remainder inherits that rectangle; unrelated split ratios stay unchanged. Inserting into an adjusted dwindle divides the preceding slot's share (the first slot for index zero). Fresh/reset containers retain the default 50/50 spiral. Swaps preserve both parents' slot ratios; normalization preserves a replaced slot. |
| Minimums | Aggregation receives the workspace's resolved gaps and allocated rectangle. Nested dwindle follows each resolved split axis rather than summing every remaining window. Tabs reserve their bar and shell. Tiles fit content minimums plus their gap share, avoiding double subtraction. Layout, mouse geometry and tile previews share frame calculation. Impossible minimums retain the existing requested-distribution fallback. |
| Movement | `move` reorders slots within the same parent. Across parents it enters a matching tiles parent or wraps the spatial target with the requested axis, allowing a node to enter/leave containers. Tab groups move as a unit. Existing explicit swap operations retain slot-swap behavior. |
| Selection | Directional focus uses virtual slots and requires positive overlap on the perpendicular axis. There is no diagonal fallback. A tab group exposes its active tab as one spatial target; `focus tab-index`, `tab-next`, `tab-prev` and DFS selection reach hidden tabs. Workspace wrap uses the geometric opposite edge. |
| Orientation | Dwindle is automatic unless an explicit axis is selected. `layout horizontal`/`vertical` fix its split axis; `layout auto` restores automatic resolution. Layout, resize and navigation use the same resolver. The mode survives snapshots; missing fields keep old snapshots automatic. The default orientation setting applies at creation and updates existing dwindle roots when that setting changes. Unrelated reloads preserve manual choices. |
| Corner resize | Processes horizontal then vertical changes against recomputed geometry. Mouse-down edges determine adjacency. If resizing changes an automatic split's axis, the other axis does not reuse its stale length or ratio. Transfers continue to affect the implicit remainder, not an invented adjacent-sibling model. |
| Flatten | Preserves DFS window order and the chosen root layout, removes empty wrappers, resets dwindle ratios and returns orientation to the configured default. It preserves logical focus/MRU and leaves floating windows in place. `balance-sizes` continues to preserve the tree. |

Accordion is excluded by product decision: WinMuxX keeps its tab interface.

2026-10-05 correction: sibling-ratio normalization from Dinky cannot be applied
globally to WinMuxX's implicit binary spine. A default three-window spiral has
areas 1/2, 1/4, 1/4; removing either quarter must leave two halves, not 2/3 and
1/3. Removal now discards only the deleted leaf's split ratio. Tests cover all
three removal positions and cross-workspace movement with custom ratios.
Fixed workspace layouts remain deferred as requested. Manual Accessibility checks
with real minimum-constrained applications, nested tab groups, corner drags and
rotated/external displays remain part of runtime validation.

## Primary references

- [Insertion, orientation, focus and flatten](https://github.com/mikker/Dinky/blob/d488ce74eb1ec4319409118f56caebd88844fac6/Sources/DinkyLayout/Workspace.swift)
- [Tree mutation and ratio redistribution](https://github.com/mikker/Dinky/blob/d488ce74eb1ec4319409118f56caebd88844fac6/Sources/DinkyLayout/Tree.swift)
- [Directional movement, virtual focus and keyboard resize](https://github.com/mikker/Dinky/blob/d488ce74eb1ec4319409118f56caebd88844fac6/Sources/DinkyLayout/Commands.swift)
- [Edge and corner resizing](https://github.com/mikker/Dinky/blob/d488ce74eb1ec4319409118f56caebd88844fac6/Sources/DinkyLayout/ResizeTo.swift)
- [Minimum fitting](https://github.com/mikker/Dinky/blob/d488ce74eb1ec4319409118f56caebd88844fac6/Sources/DinkyLayout/Geometry.swift)

The original nine resize regressions remain, and 15 additional tests cover
membership redistribution, matching-axis insertion, slot replacement and
normalization, nested minimums, tab chrome, per-monitor gaps, explicit/automatic
orientation and reload, structural movement, sequential corners, hidden tabs,
slot-preserving swaps, flatten and geometric wrap. Existing focus and move tests
now assert the intentionally changed alignment and slot-preservation policies.
The complete Swift suite passes with 706 tests; the 11 release-script tests also
pass. Dependency resolution leaves `Package.resolved` unchanged. Interactive
Accessibility validation remains pending.
