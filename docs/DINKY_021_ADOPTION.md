# Dinky 0.21 command separation

Reviewed against [Dinky v0.21](https://github.com/mikker/Dinky/releases/tag/v0.21),
commit `38a2effdcb9d34f4e402a3f69476f39be660a878`, and its implementation commit
`27bad1c6228392f92114f9282b23062318d96ca2`. WinMuxX adapts the command boundary
to its existing tree and simulated workspace model.

## Migrating commands

This is a deliberate breaking change. Old workspace choices no longer parse in
`layout`, including in configuration bindings and callback command lists:

| Before | After |
| --- | --- |
| `layout dwindle` | `workspace-layout dwindle` |
| `layout master` | `workspace-layout master` |
| `layout dwindle master` | `workspace-layout dwindle master` |
| `layout master tiles` | `workspace-layout master dwindle` |

`layout tiles accordion` and `layout floating tiling` keep their existing scopes.
Workspace choices and container choices cannot be mixed in one cycle. WinMuxX has
no scrolling engine; `scrolling` is rejected by both commands rather than accepted
as an alias for a different layout.

The new workspace command accepts `--window-id` and targets that window's entire
workspace even when it belongs to a nested container. It requires a tiled window;
empty, floating and invalid targets fail without changing the workspace. Entering
master promotes the targeted pane, keeping tab groups atomic. Leaving master
keeps existing containers and the stack's current tiles/accordion style instead
of rebuilding it from configuration defaults. This preserves WinMuxX's tree
structure; it does not flatten every window into Dinky's rebuilt tree.

`layout` changes the focused window's immediate container or floating state. In
master mode, tiles/accordion choices target the master stack from any tiled pane.
Other container choices cannot replace the master root. Master orientation remains
controlled by `[master].side`. Native popup/minimized/fullscreen/hidden windows
retain the established restrictions. The one-shot next-window option is unchanged.

Multiple choices now cycle after the last matching description, wrapping to the
first; if none matches, the first choice applies. Three-item lists therefore visit
all three items instead of alternating between the first two.

## Queries and UI

`%{workspace-layout}` is available in workspace and window queries, including JSON:

```sh
winmuxx list-workspaces --all --format '%{workspace} %{workspace-layout}'
winmuxx list-windows --all --format '%{app-name} %{workspace-layout}' --json
```

Values are `dwindle`, `master`, or `fixed` for roots using tiles, accordion or tabs.
`%{workspace-root-container-layout}` still reports the concrete root container
layout and orientation. Layout menu workspace choices use the new command, in a
separate group from container choices; Settings shortcut actions use it too.
