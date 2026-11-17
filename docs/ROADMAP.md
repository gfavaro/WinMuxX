# Roadmap

What is still open. Everything else is shipped.

| Priority | Work | Done when |
| --- | --- | --- |
| 1 | Display topology | Real dock, undock, reconnect and three-display runs keep explicit ownership and one secondary workspace per display; ordinary navigation never relocates workspaces |
| 2 | Recovery and sizing | Crash recovery with real windows, delayed restoration, learned minima, nested dwindle, tab groups and overflow |
| 3 | Native Settings and sidebar | Manual keyboard and accessibility, save and conflict, compact layout, appearance and Bring Here checks |
| 4 | App and system compatibility | Windows App and Electron accessibility, Cmd-Tab and Dock with several windows, Mission Control, focus-follows-mouse, permission transitions |
| 5 | Test isolation | Isolate native window registries, UI singletons and refresh and persistence adapters so the suite can run in parallel |

Record remote CI and physical runtime checks separately from local test results.

Not planned: fixed grids and scrolling workspace layouts.
