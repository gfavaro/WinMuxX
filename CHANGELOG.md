# Changelog

## Unreleased

- Reorder workspaces by dragging a workspace's header in the sidebar, or with `move-workspace-order up|down`; numbers follow the new order.
- Keep workspace numbers when an empty workspace is removed after a restart, instead of swapping workspaces.

## 0.7.0

- Return windows to their workspaces after an app quits and relaunches, and match the only window of a relaunched app even when its title changed.
- Keep the saved window layout across logout, restart and shutdown; apps closing their windows as they quit no longer overwrite it.
- Add root `accent-color` to replace the macOS accent in borders, the active tab, the hover bar, the overview and mode indicators.
- Remember a workspace's Scrolling position across restarts, even when it was using another layout at shutdown.
- Show tab groups with an always-visible tab bar again, replacing the pill rail and the hover bar's tab row; remove `layout strip`, which now gives a tab group.
- Draw the sidebar as one surface with the windows beside it, following the window corners.
- Add illustrated layout, command and configuration recipe guides.
- Preserve dangling configuration symlinks during bootstrap and round-trip quoted Unicode CLI arguments.
- Report side-filtered shortcut failures and retry event tap installation for a bounded period.

Released versions are listed on the [GitHub releases page](https://github.com/gfavaro/WinMuxX/releases).
