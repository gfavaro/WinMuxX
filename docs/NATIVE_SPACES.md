# Native Spaces (experimental)

This branch implements read-only native Space observation and a separate experimental
Dwindle/Master tiling opt-in. Basic positioning, explicit focus, minimize/restore
and native fullscreen have been exercised on one SIP-enabled macOS 27.2 host.
Broader native validation remains a release gate. Virtual workspaces remain the default and retain their layouts,
projects, gestures, display movement and recovery.

## Opt in and roll back

Use an explicit configuration and restart the development app:

```toml
[workspace-backend]
type = "native" # observation only by default; virtual remains the default backend
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
stale. It reports WindowServer event availability, topology-audit work and per-window
JSON diagnostic rows (`Window frame:`) identifying PID, Space UUID, eligibility,
floating state and the last calculated layout target. Targets are cached model
state, may be stale for concealed windows, and are not actual AX measurements or
write permits. A local
read-only ownership preflight checks real process/Space identity without granting
the runtime any frame-write permits.
In observation mode, other CLI commands, including virtual queries and subscriptions, return an explicit
unsupported error. There is no automatic synthetic-input fallback for navigation.
The sidebar, palette, overview and project mapping are not integrated yet.

Change `type` back to `"virtual"` (or remove the table) and restart to roll back.
Live backend changes are rejected before publishing configuration; `reload-config
--dry-run` can validate the next launch's configuration. Native mode never loads or
saves `window-state.json`, modifies virtual layout recovery, or migrates workspace
membership. No personal configuration or installed build is modified by building
this branch. Keep the installed virtual manager out of any future native **tiling**
validation; read-only observation itself does not compete for window ownership.

## Experimental tiling opt-in

Use a separate development configuration and run only one window manager:

```toml
[workspace-backend]
type = "native"

[native-spaces]
tiling-enabled = true # false by default; changing this requires restart
restore-layouts = true
```

The initial implementation currently suspends tiling below macOS 27 because its
Mission Control overlay detection has not been validated on older systems. Read-only
observation remains available there. Accessibility permission must already exist;
native startup never prompts or changes system settings. Missing lifecycle event
support, read-only startup, invalid observation, Mission Control and mouse interaction
suspend native layout application. `doctor` reports the actual status.

`NativeTilingCoordinator` applies the existing geometry to active ordinary desktops.
Retained minimized/hidden windows and empty nested groups are filtered from frame
calculation without detaching or rebuilding their trees. Preferred master identity
and Dwindle shares survive temporary concealment. Floating windows keep their
physical frames unless an explicit layout command changes them. No native gesture
recognizer is installed.

Supported commands are `focus` and `move` within workspace boundaries, `resize`,
`swap`, `balance-sizes`, `split`, `swap-with-master`, `workspace-layout dwindle|master`,
and `layout` for tiles/orientation/tiling/floating. Dwindle resizing with concealed
siblings currently returns an unsupported error; restore those siblings first.
Default command targets require verified native app focus; an unmanaged/fullscreen
frontmost window cannot redirect commands to a previously focused desktop.
Configured shortcut modes are
available; unsupported commands in bindings return errors. Workspace switching,
cross-display movement, tabs, Accordion, scrolling, fullscreen commands, launch hooks,
window-detection command hooks, project commands, agent operations, virtual queries
and subscriptions remain unsupported. Cross-Space movement has no synthetic fallback.

Every queued frame write and retry requires a current generation permit, fresh
Space/process ownership and non-minimized/non-fullscreen AX state. Minimum-size
confirmation uses the same validation. Explicit keyboard focus uses a two-second
ownership lease so its own activation notifications can invalidate frame batches
without interrupting focus halfway through; newer explicit focus or mouse clicks
cancel its AX job. Ownership is checked before each focus/raise/activation step.
AX calls already dispatched cannot be recalled; this is not an atomic transaction.

Native layout state is stored separately in
`~/Library/Application Support/WinMux-GF/native-space-layouts-v1.json`, keyed by Space
UUID. Restore only binds uniquely matched windows already in that Space. It neither
launches apps nor moves windows between Spaces/displays. A missing or ambiguous
window keeps its complete saved tree pending and protected from autosave; a corrupt
or newer-version file is preserved and reported. Unsupported saved group layouts
remain pending. Numeric Space renumbering never causes ordinal matching. Set
`restore-layouts = false` to disable native loading/saving; existing files are retained.
The virtual `window-state.json` and recovery journal are untouched.

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

Tab/accordion integration and native navigation are pending. The opt-in tiling path
and native persistence have automated coverage. Initial physical Dwindle/Master,
resize, focus, minimize/restore and fullscreen checks passed on one display;
Mission Control's detection signature also passed a user-assisted read-only check.
End-to-end Mission Control tiling pause/resume, physical trackpad switching, delayed apps, multi-monitor movement,
Stage Manager and restart restoration on real apps remain unverified.
Do not use compilation or mocked tests as evidence
that those native behaviors work.

## Validation

The [assessment](NATIVE_SPACES_ASSESSMENT.md) records actual SIP-on results on
Apple Silicon/macOS 27.2, two connected displays, a real public Space-change event,
and inactive-window membership preservation. It lists untested hardware/OS and
lifecycle scenarios separately. The [decision record](NATIVE_SPACES_ADR.md) explains
the ownership boundary and rejected alternatives.

The [interactive validation record](NATIVE_SPACES_NATIVE_VALIDATION.md) separates
executed physical checks from unverified behavior. Commands retain their original
Space/display across a reconciliation wait; default targets also retain their
focused window. Explicit window-ID commands remain bound to that same window
object if application focus changes. Changed ownership, focus or reused IDs cancel
the affected command. Subsequent commands in a batch may follow focus changes authored by that
batch within the same Space; they cannot inherit another Space's focus. Directional
native focus currently excludes floating windows; explicit window-ID focus includes
them while preserving their tree membership.

The [Dinky comparison](NATIVE_SPACES_DINKY_COMPARISON.md) traces its current source
and identifies targeted reconciliation, missed-event recovery and native stacking
as implementation priorities. Targeted discovery and a topology audit are now
implemented; native stacking is pending. Native UUIDs retain layout-tree objects
across observed switching/renumbering. Pending reads revoke membership authority while retaining
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

`script/native-spaces-fixture.swift` supplies a disposable AppKit application with
two resizable windows, a Window menu, minimization and native fullscreen. Compile
it with `xcrun swiftc` into a temporary `.app` whose Info.plist declares the binary
as `CFBundleExecutable`, a unique `CFBundleIdentifier`, `CFBundlePackageType = APPL`
and `NSPrincipalClass = NSApplication`. Use a separately selected test desktop,
check for existing windows before enabling tiling, disable native persistence in
the test configuration, and pause the installed manager with a bounded restoration
watchdog. Stop the development manager before returning to a working desktop.
Never interpret fixture success as validation of restrictive third-party apps.
