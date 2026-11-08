# Layouts

WinMuxX has two related choices: a workspace layout controls its tree, and a
container layout controls how that container displays its children.

## Dwindle

Dwindle is the default. Opening a window splits the focused area along its
longer axis. When a half would be smaller than an app's known minimum size, the new
window opens as a tab in the tile instead. Closing or moving windows lets the tree rebalance. The
[dwindle diagram](assets/layouts/dwindle.svg) shows successive splits.

## Master

Master gives one window a larger area and arranges the remaining windows in a
stack beside it. Choose it for a workspace with `workspace-layout master`; run
`workspace-layout dwindle` to return to a splitting tree. The
[master tiles](assets/layouts/master-tiles.svg) diagram shows the stack. `swap-with-master` exchanges the selected pane with the master.
`balance-sizes` resets split shares; it does not rebuild the tree. See
[master settings](archive/DINKY_020_ADOPTION.md#master-layout).

Master keeps one main window on every display, including ultrawide displays. The
remaining windows form a stack beside it. Two windows share the screen.
When another stack row would be shorter than an app's known minimum size, a new
window opens as a tab in the window in use instead, so the stack stops growing.

## Tabbed

Tabbed shows every tiled window of the workspace as a tab under a browser-style bar
at the top of the display: one window fills the area below it, and clicking a tab, or
focus left and right, switches windows. New windows open as new tabs. Choose it with
`workspace-layout tabbed`, Arrange Windows → Tabbed in the menu, or Settings → Windows
→ Workspace layout. The tree underneath is untouched, so `workspace-layout dwindle` or
`master` restores the previous splits and tab groups, with new windows placed as
Dwindle places them. Floating windows keep their own position. The bar shows even
with tab strips off, since it is how you switch windows there.

The bar is the original WinMux tab strip: drag a tab along it to reorder, or away to
drop the window on another window, a sidebar workspace or another display; right-click
for Move Tab Left and Right. `move left` and `move right` reorder too, and `focus
tab-next`, `tab-prev` and `--tab-index` follow the bar. One border encloses the bar and
the window, and the bar's surface continues behind the window.

To see windows side by side, split the workspace into tab groups: columns and rows,
each with its own bar showing one of its windows. Tabs shrink to their icons before
any would scroll out of sight. The focused group's bar ends in three buttons: Split
Right and Split Down open the tab shown in a new column or row, and Focus fills the
screen with it, as `fullscreen` does; each tooltip gives the keys bound to it. A split
the windows have no room for, side by side or stacked at the sizes they allow, is
unavailable: the button is greyed out with the reason as its tooltip, `split` reports
it, and the drop zones on those edges show a no-entry sign and the reason instead.
Right-click a tab for Move to New Column, Move to New Row, or Merge All Groups. In a
bar showing folded groups, a thin line marks where each group's tabs begin. `split horizontal` and `split vertical` open the
focused tab in a new column or row, and `join-with` moves it into the group on that
side.

Drag a tab out of its bar, sideways or down, and onto another group's bar: the tabs
part where it would land, and it joins that group there. Back over its own bar it slides into its new
place. Drag it onto the edge of a window shown in the workspace to open a new group on
that side, or onto the middle of a window to move it into that window's group. The
handle at the end of a bar carries the whole group: onto an edge to move it there, or
onto the middle of another group to merge them. Floating windows and windows dragged
from another workspace land the same way. New windows open in the focused group, and
a group whose last tab leaves closes. `focus` in a direction goes to the group on that
side, or along the bar when there is none; `move left` and `right` reorder along the
bar first, then carry the tab into the group beside it. `resize` or dragging a
window's edge resizes its group against its neighbour. The groups are kept apart from
the tree, so Dwindle and Master return to the splits they had, and they survive a
restart.

A group is never narrower or shorter than the most demanding of its windows needs,
shown or not, and resizing stops there. When the display has no room for every group
at those sizes, the group farthest from the one in use folds into its neighbour's bar:
its tabs show there, and choosing one shows it in that area. The group itself stays,
and returns on its own once there is room, on a larger display or after a merge.

## Container modes and tabs

`layout tiles` places the focused container's children beside one another, and
`layout tabbed` keeps them together as a tab group showing one at a time; see the
[tab group diagram](assets/layouts/tabs.svg). Run `layout tiles tabbed` to cycle
these choices. The accordion layout was removed: `layout accordion` and
`layout stacked` now give a tab group, so existing bindings keep working.

`layout strip` shows a tab group as a strip instead: its windows sit side by side as
columns inside the group's tile, in Dwindle or Master. Each column takes just under half
the group (gaps included, so two show at once) unless it was resized, and the
columns that fit fill the tile. The others wait hidden; focus left or right steps through
the columns and scrolls hidden ones in, leaving the strip at either end. `layout tab-group`
shows the same group as tabs again. The choice is saved with the layout. Make a group with
`stack-with` or by dragging a window onto another, then choose Arrange Windows → Columns in the menu or bind Window Group: Columns in Settings → Shortcuts.

`layout floating` and `layout tiling` change the selected window's state. These
commands target the focused window and do not select a workspace layout.
`flatten-workspace-tree` rebuilds the workspace tree from its configured defaults.

## Lone ultrawide window

On ultrawide displays, a lone tiled window can use a configurable maximum width
and is centered. Manual width resizing is respected for the current session. The
[ultrawide diagram](assets/layouts/ultrawide.svg) illustrates this behavior.
See [single-window sizing](../README.md#single-window-on-ultrawide).

## Workspace and container commands

`workspace-layout` requires a focused tiled window and changes that window's
whole workspace. `layout` changes the focused window's container, or toggles its
floating state. Layout choices preserve existing nested containers as described
in the [0.21 migration notes](DINKY_021_ADOPTION.md).

The query value `fixed` describes a tiles or tab-group root. It does
not provide Dinky's reserved-cell fixed grid. See
[workspace layout commands](DINKY_021_ADOPTION.md#migrating-commands).
