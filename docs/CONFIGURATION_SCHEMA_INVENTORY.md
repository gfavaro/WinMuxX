# Configuration schema inventory

Source checked against `Sources/AppBundle/config/parseConfig.swift` and its
referenced parsers on 2026-10-22. The parser rejects unrecognized keys; shared
fixtures verify that the schema also rejects an unknown root key. TOML inline
dotted keys and table headers can express equivalent structures.

| Root key / table | Accepted shape | Parser source / notes |
| --- | --- | --- |
| `config-version` | integer 1–2 | `parseConfigVersion` |
| `appearance` | `system`, `light`, `dark` | root parser |
| `after-login-command` | empty array only | Deprecated parser |
| `after-startup-command`, `on-display-changed`, `on-focus-changed`, `on-mode-changed`, `on-focused-monitor-changed` | command string or string array | `parseCommandOrCommands` |
| normalization, startup, login, reload, hidden-app, tiling, focus and shake flags | booleans | root parser |
| `default-root-container-layout`, `drag-stack-layout` | layout strings; drag accepts stack layout | root parser; legacy/current names differ |
| `default-root-container-orientation` | `horizontal`, `vertical`, `auto` | root parser |
| `focus-follows-mouse-dwell`, `tab-group-padding` | integer | root parser |
| `shortcuts-preset` | string; `rectangle` now errors as removed | root parser + semantic validation |
| `persistent-workspaces` | string array; requires version 2 | ordered names, version check |
| `single-window-alignment` | `center`, `left`, `right` | root parser |
| `single-window-aspect-ratio` | scalar or monitor-specific dynamic value | `parseSingleWindowAspectRatio` |
| `follow-app-activation` | boolean or `{enabled, exclude-apps}` | `FollowAppActivationConfig.swift` |
| `master` | `{size: 0.1…0.9, side, stack-layout}` | `MasterConfig.swift` |
| `animations` | `{enabled, duration-ms: 0…2000}` | `AnimationsConfig.swift` |
| `workspace-swipe` | enabled, reverse direction, duration 0…1000 | `WorkspaceSwipeConfig.swift` |
| `workspace-overview` | `three-finger-up` boolean | `WorkspaceOverviewConfig.swift` |
| `gaps` | nested inner/outer dynamic integer values | `parseGaps.swift` |
| `workspace-sidebar` | appearance, dimensions, behavior, labels/colors and monitor selector | `parseWorkspaceSidebar.swift`; cross-field width check |
| `menu-bar` | indicator and icon appearance enums | `parseMenuBar.swift` |
| `window-tabs` | enabled, height >20, double-sided flag | `parseWindowTabs.swift` |
| `borders` | enabled, finite width ≥0, colors, order, app IDs | `WindowBordersConfig.swift` |
| `modifiers` | modifier names mapped to `both`, `left`, `right` | `ModifierSides.swift` |
| `workspace` | dynamic workspace names with layout/orientation/display overrides | `WorkspaceLayoutConfig.swift` |
| `workspace-to-monitor-force-assignment` | dynamic workspace names to monitor-selector arrays | `parseWorkspaceToMonitorAssignment.swift` |
| `on-window-detected` | array of matcher/run tables | `parseOnWindowDetected.swift` |
| `mode` | dynamic mode names; binding and mode settings | mode parsers and keyboard mapping |
| `key-mapping` | dynamic key names and mappings | key mapping parser |
| `exec` | command environment table | Exec config parser |
| deprecated migration keys | legacy values; some intentionally error | root parser and migration |

Defaults live in `Config.swift` and sub-config initializers. Conditional rules,
valid command strings, TOML version interactions, regex validity, monitor selector
resolution and cross-field constraints need the Swift parser/runtime.
