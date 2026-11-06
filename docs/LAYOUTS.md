# Layouts

WinMuxX has two related choices: a workspace layout controls its tree, and a
container layout controls how that container displays its children.

## Dwindle

Dwindle is the default. Opening a window splits the focused area along its
longer axis. Closing or moving windows lets the tree rebalance. The
[dwindle diagram](assets/layouts/dwindle.svg) shows successive splits.

## Master

Master gives one window a larger area and arranges the remaining windows in a
stack beside it. Choose it for a workspace with `workspace-layout master`; run
`workspace-layout dwindle` to return to a splitting tree. The
[master tiles](assets/layouts/master-tiles.svg) and
[master accordion](assets/layouts/master-accordion.svg) diagrams show the stack
in each mode. `swap-with-master` exchanges the selected pane with the master.
`balance-sizes` resets split shares; it does not rebuild the tree. See
[master settings](archive/DINKY_020_ADOPTION.md#master-layout).

Master keeps one main window on every display, including ultrawide displays. The
remaining windows form a stack beside it. Two windows share the screen.

## Container modes and tabs

`layout tiles` places the focused container's children beside one another.
`layout accordion` gives the selected child the visible area and lets you cycle
through its neighbours. Run `layout tiles accordion` to cycle these choices.
In master mode, this applies to the stack. A tab group keeps its windows together;
see the [tab group diagram](assets/layouts/tabs.svg).

`layout strip` shows a tab group as a strip instead: its windows sit side by side as
columns inside the group's tile, in Dwindle or Master. Each column takes just under half
the group (gaps included, so two show at once) unless it was resized, and the
columns that fit fill the tile. The others wait hidden; focus left or right steps through
the columns and scrolls hidden ones in, leaving the strip at either end. `layout tab-group`
shows the same group as tabs again. The choice is saved with the layout. Make a group with
`stack-with` or by dragging a window onto another, then choose Commands → Container Layout →
Strip in the menu or bind Stacked: Strip in Settings → Shortcuts.

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

The query value `fixed` describes a tiles, accordion or tab-group root. It does
not provide Dinky's reserved-cell fixed grid. See
[workspace layout commands](DINKY_021_ADOPTION.md#migrating-commands).
