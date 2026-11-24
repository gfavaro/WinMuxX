# Changelog

## Unreleased

- Skip a tile whose window closed while the workspace was being laid out, instead of crashing with "Can't change weight if TreeNode doesn't have parent".
- Add an `all-displays` menu-bar indicator that lists the workspace each display shows, the main display first, with the focused one in bold, beside the focused workspace's layout icon.
- Add Send to… to the hover bar: a menu of workspaces and displays to move the window to; a floating window is tiled where it lands.
- Add a map in Settings → Automation: drop an app on a workspace to open its windows there; the workspaces up to it are kept so Option-number reaches them.
- Keep the workspace a display showed while that display is away (asleep, still waking, unplugged) across a restart, so it comes back to the display instead of moving to the main one.
- Bring Finder windows back on quit; Finder reports no launch date, so its windows were never recorded.
- Bring parked windows back into view on quit even when they were first seen parked in the corner.
- Focus the window you asked for in an app with several windows, instead of whichever one macOS had as its main window.
- Reorder workspaces by dragging a workspace's header in the sidebar, or with `move-workspace-order up|down`; numbers follow the new order.
- Keep workspace numbers when an empty workspace is removed after a restart, instead of swapping workspaces.
- Look for windows again when the screen unlocks, so a start while the screen was locked no longer leaves windows unmanaged.
- Start the sidebar right below the menu bar on every display, using its measured height, so no gap shows on displays without a notch.
- Set a lone-window width per display in Settings → Displays.
- Set the accent color in Settings → Appearance.
- Find far more controls with Settings search; a test now fails when a setting is added without a searchable control.
- Show collapsed sidebar tile hover from the pointer position, on the display under the pointer only, so it no longer lags or sticks.
- Log why a saved window was not restored after a restart, and list the windows still waiting, by workspace and app, in the diagnostics report.
- Tell apart identical windows of one app when restoring after a restart, using where each window was, then the order they were opened.
- Keep a workspace until its saved windows have come back, so apps that are slow to appear after a restart no longer lose their place, and keep the saved layout until the restore finishes.

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
