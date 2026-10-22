# Mode timeout and indicator

Base implementation: verified and installed as signed build 123.
The repeatable navigation follow-up is described below; personal entry shortcuts
remain a user configuration choice.

## User behavior

Use existing binding modes as leader layers. A shortcut enters a mode; ordinary
bindings perform actions. Bindings returning to `main` remain one-shot; bindings
without that command allow repeated navigation until Escape or inactivity timeout.

Proposed configuration:

```toml
[mode.leader]
timeout-ms = 1500
show-indicator = true
indicator-color = '#5E9EFF'

[mode.leader.binding]
h = ['focus left', 'mode main']
j = ['focus down', 'mode main']
k = ['focus up', 'mode main']
l = ['focus right', 'mode main']
esc = 'mode main'
```

Add the entry shortcut to the existing `[mode.main.binding]`, avoiding conflicts
with the user's current shortcuts. Do not choose or change their leader key during
implementation. Keep Escape explicitly configured; do not silently replace bindings.

- `timeout-ms`: integer 0–60000; default 0 means no automatic exit.
- `show-indicator`: boolean; default false preserves existing modes' appearance.
- `indicator-color`: optional six-digit hex color per mode; reuse existing color
  normalization. When omitted, use the system accent color. It applies only while
  that mode is active and its indicator is enabled.
- The timeout measures inactivity since entry or the last accepted binding in that
  mode. Re-entering the same mode starts a fresh interval.
- Expiry returns to `main` through normal activation, including existing mode events
  and hooks. The `main` mode never times out or displays a mode indicator, even if
  these options are set there; document this reserved-mode behavior.
- Unbound keys keep existing pass-through behavior and do not reset the timeout.
  This is a mode-based leader, not an exclusive keyboard capture system.
- A command already accepted before expiry may finish. Once that binding is
  accepted, invalidate the old deadline; arm its next interval after its command
  sequence completes only if the same mode session remains active. No timeout may
  interleave an accepted command sequence or undo its explicit mode change.

## 1. Configuration and documentation

Extend `Sources/AppBundle/config/Mode.swift` and `parseMode` with these three fields,
preserving initializer defaults and existing bindings/tap/sequence parsing.
Update mode serialization in `command/impl/ConfigCommand.swift`, the configuration
reference, Settings mode-field preservation paths, and `docs/CONFIGURATION.md`.
Search all mode constructors/editors: saving a shortcut must preserve all three fields.
Provide an optional commented example in the default config; do not enable it.

Acceptance: old configs behave identically. Tests cover defaults, valid bounds,
wrong types, invalid ranges, serialization, and Settings edits retaining metadata.

## 2. Runtime-owned timeout lifecycle

Extend `HotkeyState` in `config/HotkeyBinding.swift` or extract a small mode-session
owner if that keeps the file clearer. Keep one cancelable one-shot timeout per
runtime, a session generation, and an injectable scheduler for deterministic tests.

- Integrate at `activateMode`, including same-mode re-entry. Register timeout and
  presentation for the committed mode before awaiting `on-mode-changed`; protect
  follow-up work from hooks that activate another mode.
- Route chord, side-filtered, tap, sequence, and CLI-triggered binding acceptance
  through one mode-session activity boundary. Inspect each current dispatch path.
- Queued callbacks must validate owner, mode session, and current availability
  before dispatch: an expired leader binding cannot run in `main`. Avoid closures
  retaining an obsolete mode's command list when a shortcut is reused across modes.
- Accepted commands cancel the previous deadline. Use session-aware completion
  handling for errors/cancellation and overlapping bindings; do not leave the timer
  permanently disarmed or rearm it while accepted work is still running.
- Reset, reload, mode change, disable, suspend, shutdown, and runtime replacement
  cancel deadlines and dismiss presentation. On temporary hotkey suspension retain
  the selected mode without an active timer; resume with a fresh interval if still
  enabled. Respect existing disable/re-enable and reload mode-selection policy.
- Use the existing command-session rules for timeout activation; do not fabricate
  input events or add native reads, layout work, a display link, or a repeating timer.

Acceptance: deterministic tests prove exact expiry, activity reset, same-mode
re-entry, old deadline rejection, hook re-entry, in-flight commands, all dispatch
paths, reload, suspension, disable, and independent runtimes. Use controlled time,
not sleeps. Existing binding semantics and command failure behavior remain intact.

## 3. Existing menu-bar indicator

Keep the user's existing menu-bar choice: icon or workspace text. Integrate mode
feedback into that status item rather than creating a separate HUD/panel.

- Icon indicator: tint the existing icon with the active mode's `indicator-color`.
  This temporarily takes precedence over the normal color/monochrome preference;
  restore that preference exactly when the mode exits or its indicator is disabled.
- Text indicator: preserve the existing workspace text and append ` | L` for mode
  `leader`, ` | N` for `navigation`, etc. Tint only the suffix with the mode color;
  keep the workspace text's existing appearance. Never assume workspace names are
  numeric or replace a configured name with a number.
- Derive the letter from the first non-whitespace grapheme of the mode name,
  uppercased and bounded to one displayed grapheme. Test Unicode and uppercase
  expansions. Use `?` if no displayable initial exists. Initial collisions are
  allowed: the tooltip provides the full name and mode colors can distinguish them.
- Tooltip: retain useful existing workspace information and append the full active
  mode name, for example `Workspace 4 — Mode: Navigation`. Include an Escape hint
  only when Escape actually returns to `main`. Supply the same full meaning in the
  accessibility label; do not rely on color alone for assistive technology.
- No suffix or mode tint in `main`, while disabled/suspended, or when
  `show-indicator = false`. Restore the ordinary tooltip on exit. If the status item
  is hidden by existing settings, respect that setting rather than showing a HUD.
- Use the existing status-item renderer/model and native menu-bar appearance. Resolve
  custom color contrast against its effective light/dark appearance, including
  Increase Contrast; preserve the chosen hue as far as readability allows. Check
  colored image/template rendering so AppKit does not discard the intended tint.
- Update on mode activation/exit, config changes, workspace changes, and native
  appearance changes through existing event paths. Avoid countdowns, polling,
  additional windows, and animated status-item width changes.

Acceptance: tests cover icon/text forms, color fallback and overrides, custom
workspace names, Unicode initials, tooltips/accessibility, suspension/reset/reload,
rapid mode changes, and exact restoration of normal rendering. Native smoke checks
both appearances and both indicator styles, verifies no focus changes, and confirms
that text fits without clipping. Menu-bar auto-hide still controls visibility;
mode timeout works whether or not the indicator is visible.

## 4. Public state for external bars and scripts

User requirement: mode feedback and other user-facing runtime states must be
available to external integrations such as SketchyBar, not only the built-in UI.

Reference: Dinky's `Sources/dinky/Hooks.swift` passes `DINKY_MODE` and
`DINKY_PREV_MODE` to mode hooks, workspace/previous-workspace/display to workspace
hooks, and display counts to display hooks. These are child-process environment
values, not globally changing environment variables in already-running processes.
Source: https://github.com/mikker/Dinky/blob/main/Sources/dinky/Hooks.swift

Existing WinMuxX foundations: `ServerEvent.swift`, `SubscribeCmdArgs.swift`,
`CmdEnv.swift`, `ExecAndForgetCommand.swift`, existing hook config and bounded IPC
subscriptions. Current events cover focus, focused monitor/workspace, mode, window
detection and binding activation. Extend this infrastructure rather than creating
a separate socket, polling service, or integration-specific source of truth.

### Contract and state coverage

Before coding, document a field/event matrix with the canonical owner, update
boundary, absent/unknown representation and existing compatibility obligations.
Interpret "all states" as supported user-facing model state; exclude internal
queues, animation frames and debug recorder internals.

- Mode: name, previous mode on change, initial, configured color, resolved indicator
  color, indicator enabled/visible, timeout configuration and suspended state.
- Workspaces: stable ID, internal command name, displayed label/order, persistent
  status, project membership, occupied/empty state and active viewport assignments.
  Do not conflate displayed numbers, command names and stable IDs.
- Displays: stable UUID plus current index, geometry, active workspace and focused
  display. Publish topology changes after model reconciliation.
- Focus/windows: focused window ID and app identity, workspace membership, tiled/
  floating/minimized/fullscreen classification and window counts. Reuse managed
  observations; represent unknown native state explicitly. Do not fetch AX titles
  or geometry merely to feed a bar.
- Layout: workspace layout and focused container layout/orientation where applicable,
  including tabs. Report mixed layouts without pretending one layout describes all
  containers; reuse existing structured tree queries for detailed inspection.
- Runtime/UI: enabled/suspended, effective appearance, sidebar presentation,
  palette/overview visibility, and configuration revision/successful reload.
  Include project state even if the current user does not use projects.

### Transport and consistency

1. Add a read-only, versioned JSON state query (proposed `winmuxx state --json`;
   finalize command naming against existing query APIs). Assemble an immutable
   snapshot from established model state without AX refresh, layout, or mutation.
2. Add an opt-in state subscription to the existing `subscribe` transport. Deliver
   one initial snapshot and subsequent committed-state changes with server-instance
   ID and monotonic revision. Snapshot and registration must share a serialized
   boundary so no update is lost between them. Preserve legacy event shapes and
   initial-event behavior for existing subscribers.
3. Use domain change markers and bounded coalescing at settled boundaries. Avoid
   serializing the entire window tree on every focus or geometry event. Reuse
   existing slow-consumer limits; clients reconnect to get a new initial snapshot.
4. Expose hook environment values derived from the same event snapshot, preserving
   existing `WINMUX_*` names. Proposed additive names include `WINMUX_MODE`,
   `WINMUX_PREV_MODE`, `WINMUX_MODE_INITIAL`, `WINMUX_MODE_COLOR`,
   `WINMUX_MONITOR_UUID`, `WINMUX_ENABLED`, `WINMUX_EVENT` and
   `WINMUX_STATE_REVISION`. Finalize the full documented mapping before coding.
   Scalars use predictable string encoding; structured state uses JSON, not dozens
   of flattened environment variables. Define absent values and precedence so
   inherited values cannot falsely describe the current event.
5. Capture hook context before async work. Pass values through `Process.environment`,
   never by interpolating workspace names or titles into shell code. Hook execution
   must not block state delivery; retain bounded work and document ordering where
   independently launched scripts may finish out of order. Prefer one persistent
   subscriber for high-frequency SketchyBar updates.
6. Drive the native mode indicator from the same mode presentation data. External
   integration remains active when the built-in menu-bar item is hidden.

Ship a documented SketchyBar adapter/example that subscribes once, initializes
from the snapshot, updates only affected items, handles missing state, and reconnects
with bounded backoff. Avoid requiring SketchyBar or launching it automatically.
Document startup/restart and schema-version behavior, privacy scope and event names.

Acceptance: tests cover initial snapshot/update race, revision order, reconnect,
restart identity, slow clients, unknown fields, hook variable precedence/quoting,
mode timeout/re-entry, display reassignment, rename/close and missing focus, config
reload, presentation changes and disabled management. Query/subscription paths
must perform zero extra native reads or layout work. Verify the example's payload
mapping with fixtures; claim live SketchyBar validation only if actually exercised.

Implement this as a separate reviewable stage after mode runtime/presentation;
complete the field/event matrix and compatibility tests before broadening events.

## 5. Verification and delivery

Run focused tests while iterating, then `make check` once on the final candidate.
Verify existing mode-change events/hooks remain compatible and default configs
produce no indicator/timer. Record actual test counts and untested native cases.

Build and install through the existing signed release/rollback workflow under the
standing delivery authorization. Use a temporary backed-up test config for native
checks, restore exact user config afterward, and verify surviving assignments.
Do not enable a personal leader shortcut without a user choice. Commit and push
the implementation and evidence; merging requires current merge authorization.

Completion: opt-in leader mode expires reliably, its indicator never steals focus,
existing modes remain unchanged, full checks pass, and release evidence is recorded.

## Implementation evidence (2026-10-22)

- Mode configuration, runtime-owned one-shot deadlines, session/binding identities,
  shared compact mode presentation, icon tint/text suffix, tooltip and accessibility
  meaning are implemented. Accepted sequences protect newly entered modes until
  their completion; expired or replaced activations reject queued callbacks.
- Chord/tap/sequence/side-filtered dispatch uses the shared binding acceptance path;
  explicit CLI binding execution participates when targeting the current mode.
  Existing explicit execution of a different mode's binding remains supported.
- Public state uses schema 1, a read-only query, explicitly opted-in `state-changed`
  subscription, captured hook context and a fixture-tested SketchyBar adapter.
  Legacy `subscribe --all` retains its original event set. Structural domains are
  cached across mode/UI-only updates; payload work is absent with no subscribers.
- Settled transaction boundaries defer publication. A first subscriber arriving
  mid-transaction receives its initial snapshot at completion even if state is
  otherwise unchanged. A query with no previously committed snapshot returns a
  retry error while the model is settling rather than exposing partial state.
- `make check` passed 1,327 Swift and 51 Python tests. Focused coverage includes
  stale deadlines, same-mode re-entry, accepted concurrent work, entry-sequence
  completion, hook re-entry, failed commands, suspension, runtime isolation,
  Unicode initials, contrast, reused Carbon registrations, metadata edits, initial
  subscription ordering/reconnect, legacy payloads, disabled management, direct UI
  mutation cache invalidation and a zero-native-read query.
- Native indicator/theme behavior and live SketchyBar remain separate from model
  tests. Record the signed build/install and actual native results below before
  declaring delivery complete.

### Native trial correction

Build 122 passed the automated suite and installer checks, but native observation
found repeated menu-bar effective-appearance notifications feeding repaint back
into the observer. A half-second idle observation advanced the state revision by
128,885 and process CPU was high. The build was rolled back to 121, and exact
personal config restoration was verified. Appearance updates now accept only an
actual light/dark scheme change before repainting. A 2,000-notification plus
re-entry regression checks bounded rendering; build 123 native validation confirmed idle
revisions no longer advance and the process returned to idle.
The temporary live-config helper also needed to preserve root dotted menu-bar
keys; its first invalid test edit was rejected and restored without changing
surviving window assignments.

### Build 123 delivery

`make check` passed 1,327 Swift tests and 51 Python tests. Signed build 123 embeds
app/client source `33d5041f7951a8bd92ba409f95c5426fa3ca550e`. Candidate dry-run and
strict/deep signatures passed. Initial installer verification flagged
`focus_not_restored`; a read-only resume validated the installation with no moved,
opened or closed windows. It did not replay stale focus.

Native temporary-mode checks confirmed icon tint, workspace `| M` suffix, captured
mode-hook variables matching the state API, and 1,500-ms timeout returning to main.
The persistent subscription delivered eight ordered snapshots. Focus and all seven
surviving assignments remained unchanged. Exact personal TOML bytes were restored,
including its original indicator preference; no leader shortcut is enabled.
Six successive idle samples kept revision 36 unchanged; a separate post-test
one-second observation also had zero revision growth. These finite checks rule out
the observed notification loop in those runs, not all possible energy regressions.

Native checks used the current system appearance. Automated tests cover both
appearance/contrast policies; physical system-theme/accessibility changes and live
SketchyBar were not exercised. The optional adapter passed fixture tests. Private
reports/screenshots/config backups remain in `.release/` and are not committed.

### Settings follow-up (build 124)

Dedicated controls now live under Shortcuts → Binding modes. Timeout, indicator
and color edits save automatically; Add mode creates an Escape-to-main binding
without choosing an entry shortcut. The main mode remains reserved. Regular
Settings fields, event text and existing rule/assignment edits autosave; the raw
Configuration editor retains explicit Save and apply. Build 124 and its checks
are recorded in `RELEASE_VALIDATION.md`.

## Repeatable navigation follow-up

Modes can opt into `exit-on-unbound-key = true` (default false). The existing
keyboard event tap observes key-down events before Carbon, checks the current
mode's chord and sequence bindings (including configured modifier sides), and
passes unassigned keys through unchanged. It disables the old layer immediately,
invalidates its deadline and queued bindings, then activates main on the next
main-actor turn. Shortcuts remain disabled until the triggering key is released,
so neither old navigation bindings nor newly enabled main shortcuts can consume
the original key press. Registration resumes on the actor turn after the key-up
event tap returns, allowing WindowServer to finish the release first. Tap recovery clears the release gate. Mode
changes, reload and suspension invalidate a pending exit. Modifier taps retain
their existing semantics; no extra event tap or polling timer is introduced.

Settings → Shortcuts → Binding modes exposes the option. Config serialization and
public state (`mode.exitOnUnboundKey`) include it. Main ignores the option.

A personal navigation layer can use a right-Command tap to enter/exit, a 3000 ms
inactivity timeout and a blue N indicator. Focus, move, display and workspace
bindings stay in navigation; Escape/Return exit, and sidebar/palette actions return
to main. These personal bindings are not installed as application defaults.
