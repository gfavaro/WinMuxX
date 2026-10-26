# Native Spaces (experimental)

This branch implements read-only native Space observation. It does **not** yet
tile native Spaces. Virtual workspaces remain the default and retain their layouts,
projects, gestures, display movement and recovery.

## Opt in and roll back

Use an explicit configuration and restart the development app:

```toml
[workspace-backend]
type = "native" # experimental read-only; default is "virtual"
```

Native observation enumerates desktops and fullscreen Spaces per display, records
window memberships, and follows public Space/display/session/application events
plus dynamically resolved WindowServer lifecycle notifications.
It does not request Accessibility or Screen Recording permission, activate Spaces,
create/delete Spaces, move windows, park windows, run virtual startup hooks or
register WinMuxX trackpad gestures/hotkeys. Mission Control and native gestures
remain under macOS control. When Accessibility permission already exists, active
desktop windows are AX-classified into the existing layout trees without applying
frames or running detection-command hooks. Missing AX responses retain nodes;
explicit WindowServer closure and confirmed process termination remove them.
Leaving a Space or disappearing from AX does not imply closure.

The menu bar lists the latest native Space observations and provides refresh and
diagnostics. `winmuxx doctor` reports native IDs, UUIDs, per-display active Spaces,
membership counts, query duration, AX classification and whether the observation is
stale. It reports WindowServer event availability and topology-audit work. A local
read-only ownership preflight checks real process/Space identity without granting
the runtime any frame-write permits.
Other CLI commands, including virtual queries and subscriptions, return an explicit
unsupported error. There is no automatic synthetic-input fallback for navigation.
The sidebar, palette, overview and project mapping are not integrated yet.

Change `type` back to `"virtual"` (or remove the table) and restart to roll back.
Live backend changes are rejected before publishing configuration; `reload-config
--dry-run` can validate the next launch's configuration. Native mode never loads or
saves `window-state.json`, modifies virtual layout recovery, or migrates workspace
membership. No personal configuration or installed build is modified by building
this branch. Keep the installed virtual manager out of any future native **tiling**
validation; read-only observation itself does not compete for window ownership.

If startup configuration is invalid, shipped defaults remain available for error
display but the process stays read-only until restart. This prevents an invalid
native configuration from starting virtual parking as a fallback. Fix the file and
restart to re-enable window management. A failed configuration reload retains the
running configuration.

## Failure handling and limits

Read-side SkyLight symbols are dynamically resolved behind `NativeSpaces`.
Unavailable symbols, invalid topology or a topology change during a read suspend
observation. A Space-change event immediately revokes the current observation;
superseded reads cannot publish older membership. Last successful observations may
remain visible as **stale diagnostics**, never as permission to write frames.
An app-backend topology-only audit runs every 500 ms to recover missed Space
notifications. Unchanged topology does not enumerate windows or query AX. Three
consecutive audit failures suspend automatic retry until a real event/manual
refresh. Audits and subscriptions stop with the backend. The standalone probe's
bounded watch remains event-driven without an idle audit.

These private APIs are unstable across macOS versions even with SIP enabled. No
SIP change, root helper, Dock injection or non-exported symbol scanning is used.
Unknown/native fullscreen Space types and shared/all-Spaces/unknown memberships
are observable but excluded from the proposed native tiling policy. Missing UUIDs
cannot be restored by guessing an ordinal. Numeric IDs are not restart identities.

Native tiling, independent layout persistence, tab/accordion integration and native
navigation are still pending. Do not use successful compilation or mocked tests as
evidence that those features work.

## Validation

The [assessment](NATIVE_SPACES_ASSESSMENT.md) records actual SIP-on results on
Apple Silicon/macOS 27.2, two connected displays, a real public Space-change event,
and inactive-window membership preservation. It lists untested hardware/OS and
lifecycle scenarios separately. The [decision record](NATIVE_SPACES_ADR.md) explains
the ownership boundary and rejected alternatives.

The [Dinky comparison](NATIVE_SPACES_DINKY_COMPARISON.md) traces its current source
and identifies targeted reconciliation, missed-event recovery and native stacking
as implementation priorities. Targeted discovery and a topology audit are now
implemented; native stacking is pending. Native UUIDs retain layout-tree objects
across observed switching/renumbering; this is model integration, not window tiling
or restart persistence. Pending reads revoke membership authority while retaining
last-observed viewport history; failed/stopped observation clears native visibility.

Run the standalone diagnostic without launching a manager:

```sh
swift run winmuxx-native-spaces-probe --watch 30
swift test --no-parallel --filter NativeSpacesTests
swift test --no-parallel --filter WorkspaceBackend
make check
```

Interactive macOS checks require an unlocked desktop and an actual AppKit event
loop. CI fixtures verify parsing, ownership, eligibility, cancellation, configuration
and command rejection; they cannot verify private API compatibility or native UI.
