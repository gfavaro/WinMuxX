# Public state contract (schema 1)

`winmuxx state --json` reads the established model. `winmuxx subscribe state-changed`
streams newline-delimited JSON with an initial snapshot (unless `--no-send-initial`)
and complete replacement snapshots after committed changes. Existing subscription
messages are unchanged. `--all` retains the legacy event set; request
`state-changed` explicitly to opt into snapshots. Schema additions are optional; clients ignore unknown fields.
Snapshots contain no window titles, screen images, config contents, or keystrokes.

| Domain | Owner / commit boundary | Fields / missing values |
|---|---|---|
| mode | HotkeyState / activation, binding completion, suspension | name, initial, configured/resolved color, indicator enabled, timeout; null when no mode |
| workspaces | workspace registry / command and refresh completion | stable id, command name, display name/order, project, persistent, occupancy, active viewport ids |
| displays | monitor cache / reconciliation completion | UUID (null if unknown), current index, geometry, active workspace, focused |
| windows/focus | managed tree / command and refresh completion | id, app identity, workspace, tiled/floating/minimized/fullscreen/popup; native unknowns are null |
| layout | tiling tree / command and refresh completion | root layout, focused container layout/orientation; structured containers list describes mixed layouts |
| projects | project registry / command completion | id, name, order |
| runtime/UI | config, tray and presentation owners / change notifications | enabled, suspended, appearance preference/effective scheme, sidebar expansion, palette/overview visibility, successful config revision |

The envelope includes `_event: state-changed`, `schemaVersion: 1`, `instanceId`
(unique per runtime), monotonic `revision`, and `state`. Revisions may have gaps.
Reconnect starts from a fresh snapshot; a changed instance ID resets revision order.
No delta patch application is necessary. Slow clients are disconnected using the
existing 64-event/1-MiB queue bounds. Publication coalesces same-turn mutations and
never performs AX queries or layout. No subscriber means no background snapshot
serialization. High-frequency geometry changes do not launch shell scripts.

Hook subprocesses receive a captured context: `WINMUX_EVENT`, `WINMUX_MODE`,
`WINMUX_PREV_MODE` (mode callback only), `WINMUX_MODE_INITIAL`, `WINMUX_MODE_COLOR`,
`WINMUX_WORKSPACE`, `WINMUX_MONITOR_UUID`, `WINMUX_WINDOW_ID`, `WINMUX_ENABLED`,
`WINMUX_SUSPENDED`, `WINMUX_STATE_REVISION`, and `WINMUX_STATE_INSTANCE`.
Unavailable scalar values are empty strings, booleans are `true`/`false`.
Existing hook-specific values override common context. These values override
inherited/configured copies of the same names and apply only to launched children;
they cannot modify an already-running shell's environment. Mode colors resolve for
the native menu-bar appearance. Hook scripts may finish out of order: compare
instance/revision or use a single subscriber. Existing callback command order is
preserved. There is no new shell hook for every native event.

The built-in menu-bar indicator and snapshot mode fields use the same presentation
resolver. Hiding the built-in indicator does not disable queries/subscriptions.
See `script/examples/sketchybar_state.py` for a reconnecting optional adapter.
