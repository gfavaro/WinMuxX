# Developing WinMuxX

The `feat/native-spaces` branch has an experimental native backend: observation is
the default, with a separate Dwindle/Master tiling opt-in. Initial single-display
positioning/focus/fullscreen checks passed; broader native validation remains pending.
`WorkspaceBackendState` belongs to `WinMuxRuntime`; its native lifecycle owns
observation and native runtime services. Capabilities gate virtual lifecycle, parking
and recovery. `NativeSpaces` isolates dynamic read-side SkyLight
access and generation-checked event reconciliation. Layout trees/algorithms remain
shared, with native visibility filtering and separate UUID-keyed persistence.

When behaviour differs between the backends, shared code does not check
`workspaceBackend.kind`. It asks `runtime.workspaceBackend.current` (the
`WorkspaceBackend` protocol in `runtime/WorkspaceBackend.swift`) for behaviour:
commands with their own implementation, listing and naming workspaces, focus side
effects, diagnostics and geometry events. `workspaceBackend.ui` selects sidebar,
palette and tray adapters. It asks
`workspaceBackend.capabilities` for policy, such as parking hidden windows, virtual
recovery, animated motion, arranging floating windows, publishing state and owning
workspace lifecycle. Checking `kind` directly is left to the native tiling engine
itself: its command fence, layout projection, write validation, startup and
observers. Add a protocol method or capability rather than a new `kind` check.
See [workspace backend architecture](docs/WORKSPACE_BACKEND_ARCHITECTURE.md),
[native mode and rollback](docs/NATIVE_SPACES.md), the
[assessment](docs/NATIVE_SPACES_ASSESSMENT.md) and [decision record](docs/NATIVE_SPACES_ADR.md).

WinMuxX is a personal fork of WinMux. Read [fork maintenance](docs/FORK.md) for
bundle identity, configuration ownership, upstream integration and signing policy.
Current user-facing options are described in [README.md](README.md). Historical
investigations and reviews are listed in the [documentation index](docs/README.md).

## Build and check

Development requires macOS and Xcode. `Package.swift` defines Swift targets;
`.swift-version` pins Swift 6.4.0 for `script/setup.sh` and CI. Local Xcode’s
Swift 6.4 is accepted as the same release version. A mismatched compiler fails
before building; install the pin with Swiftly or select a matching Xcode. Release
app builds pass the selected compiler to Xcode through `SWIFT_EXEC`, so the app
and CLI use the same compiler. `Package.swift` still requires tools version 6.2.
See [dependencies](docs/DEPENDENCIES.md) for retained packages and audit decisions.
The app
supports macOS 13+, with native Liquid Glass enabled on macOS 26+.

```sh
swift build                  # Fast compilation with the active toolchain
swift test                   # Swift tests with the active toolchain
make check                   # Swift + Python checks and lockfile validation
make fork-build BUILD_NUMBER=26
```

Choose a fresh build number for each installed build. `make fork-build` generates
the Xcode project from `project.yml`, builds the release app and CLI, verifies the
signature and fork metadata, and writes `.release/WinMuxX.app` and a ZIP. It also
regenerates version/hash files in `Sources/Common`; review their diff before
committing. `WinMux.xcodeproj` and build outputs are generated artifacts.

For local releases, `script/fork-build.sh` reads the signing identity from
`${XDG_CONFIG_HOME:-~/.config}/winmuxx/signing-identity`, unless
`CODESIGN_IDENTITY` is supplied. Retain the identity and bundle ID across installs
to preserve macOS permissions. Without a configured identity the build is ad hoc.

GitHub releases and main-branch CI artifacts use that same persistent identity.
The repository Secrets `WINMUXX_SIGNING_P12` (base64-encoded PKCS#12 containing
the certificate and private key), `WINMUXX_SIGNING_PASSWORD`, and
`WINMUXX_SIGNING_IDENTITY` (certificate SHA-1 fingerprint) must be configured.
The workflows import it into a temporary keychain and delete the keychain after
the build. Pull-request builds stay ad hoc and do not receive the signing key.
Signing does not notarize the app; switching from an ad hoc build may require
granting permissions once more.

The build does not install. Quit the current fork, save a ZIP backup, copy the new
bundle to `/Applications/WinMuxX.app`, verify it with
`codesign --verify --deep --strict /Applications/WinMuxX.app`, then open it.
Never rename an old bundle to `WinMuxX.app-previous-*`: archive it outside
Applications instead. `make install` is intentionally disabled. The installed
CLI is `WinMuxX.app/Contents/MacOS/winmuxx-cli`; `--version` compares client and
server versions. Installation and validation of interactive behavior are separate
from compilation and automated tests.

See [Testing](docs/TESTING.md) for fixture isolation, asynchronous tests, rendering
coverage, regression requirements and CI reports.

## Architecture

| Area | Responsibility |
| --- | --- |
| `Sources/WinMuxApp` | SwiftUI app entry point and scene wiring |
| `Sources/AppBundle` | Window-manager runtime and native UI |
| `Sources/Common`, `Sources/Cli`, `Sources/PrivateApi` | Shared protocol/types, CLI transport, private Accessibility bridge |
| `Sources/AppBundleTests` | Tests organized alongside runtime subsystems |
| `resources`, `script`, `.github/workflows` | App resources/default config, build helpers, automation |

Within AppBundle, `tree` owns windows, workspaces and containers; `layout` computes
geometry; `command` implements actions; `focus` and `mouse` handle input policy;
`config` parses TOML. `ui` groups native features such as settings, sidebar, borders,
tabs and the menu bar. Keep pure geometry/policy separate from AppKit side effects.

Settings saves are owned by a model-local `SettingsSaveQueue`. Scalar/document,
shortcut and raw-editor saves share its ordering. Structured saves share progress,
error and retry handling; the raw editor retains its own baseline and error UI.
TOML transformations live separately from UI save orchestration. For persistence
tests, create a fresh ShortcutSettingsModel with injected SettingsConfigAccess and
SettingsDraftStore; production uses the shared instance with native access. The
workspace/config state has an explicit runtime owner as described below.

Every user-facing config key has a Settings control (a `@SettingsDraft("section.key")`
written with `persistConfig`), and every user command has a Shortcuts entry, and a
menu item when it is an action. Add the key to `docs/schemas/winmuxx.schema.json`
(`make check` rejects parser keys missing from it) and to `SettingsNewKeysTest`,
which writes each key the way Settings does and parses the result back. Deprecated
keys, hooks and `config-version` stay config-only.

`runtime/WinMuxRuntime.swift` is the composition point for configuration, workspace /
project / viewport registry, focus history and native focus holds, monitor caches,
hotkeys and recovery snapshots/tasks. Production uses one process-lifetime owner.
The `config`, `configUrl` and focus accessors are domain conveniences over that
owner, not independent storage. Config reload publishes value and path together
before observers run, and its gate, diagnostics, watcher and debounce belong to
the configuration owner. Monitor snapshots are immutable and Sendable; cached
main/list/sorted snapshots invalidate together on screen changes.

For focused state tests, construct a WinMuxRuntime and use `withValue` for a scoped
binding, including across suspension. Deferred work can use `runtime.task` to retain
its originating binding. A Workspace is used within its runtime binding; IDs are
unique within a registry, while object equality remains identity. Legacy serial
fixtures replace the runtime as a unit. Native window registries, UI singletons,
persistence adapters and UI singletons still have process lifetimes, so this
does not make the complete suite parallel-safe. Do not replace production runtime
state or alter AX/multitouch thread ownership to simplify a test.

`WorkspaceMonitorAssignment.swift` owns ordinary selection and explicit display
moves. `Workspace.assignedMonitor` is the ownership lookup; `workspaceMonitor` adds
a fallback for unassigned slots. Selection preserves ownership. Explicit moves
invalidate recovery state and replace secondary slots, returning displaced owners
to main without activating them. Startup/restoration only seed ownership.

`WorkspaceGestureCoordinator` owns raw-touch lifecycle and axis routing wiring.
Recognizer policy, the bounded mailbox, native device ownership and the shared
spring each have separate modules. The overview presentation owns panel-only
motion; the horizontal controller owns horizontal navigation. Keep new gesture
behavior out of startup/configuration/observer entry points beyond delegation.

The swipe preview uses `WorkspaceSwipePreviewPhase` to wait for both the animation
and workspace layout before removing its overlay. Async completions must check their
generation before affecting a newer interaction. Outgoing screen capture and incoming
composition share the bounded actor worker. The preview reuses one native surface;
ordinary cancellation must hide it and clear images/animations, while invalidation
releases it. See [swipe performance](docs/SWIPE_PERFORMANCE.md) for timing boundaries
and the distinction between synthetic surface tests and physical gesture latency.

Settings navigation lives in `ui/settings/ShortcutSettingsView.swift`. Each config
pane has a `Settings*View.swift` file; controls and TOML persistence are shared in
`SettingsControls.swift` and `SettingsConfigPersistence.swift`. A TOML edit is
validated, written, reloaded and reflected through the settings model. Menu-bar
preferences use `[menu-bar]` in TOML and publish through TrayMenuModel. Double-sided
windows use `[window-tabs].double-sided-windows`. UserDefaults is restricted to
session/cache data and one-time legacy preference import. Add controls to
the destination used by navigation, not to a detached alternative screen.

The sidebar panel controller owns panel instances and monitor-local models. Its
extensions separate lifecycle, geometry, animation, hover, hit testing, edge
trapping and menu tracking. Sidebar views receive a snapshot and action adapter;
the native panel handles screen positioning and input capture. Pointer-driven
hover uses events and deferred rechecks, not a permanent polling timer. Centered
height measurement is independent of the proposed panel height to prevent layout
feedback loops.

## Making changes

- Preserve the existing subsystem boundaries; add a file where responsibility is clear.
- Remove unreachable implementations once callers and tests have been checked.
- Keep behavior fixes separate from file moves and refactoring.
- Use existing tests first; add tests for meaningful behavior or regression cases.
- For UI changes, verify the active navigation path and inspect the installed app.
- Test both monitor edges, multiple displays and accessibility settings when changing sidebar geometry or materials.
- Keep README/FORK current; label historical investigations rather than treating them as current configuration guides.
- Make commits independently understandable. Reorganize unpublished history only; preserve published commits and upstream contribution branches.

## Runtime and overlay ownership

`WinMuxRuntime.refresh` owns refresh tasks, coalesced requests and activation
state. Schedule refresh work through the originating runtime's `throwingTask`;
this preserves its TaskLocal binding across suspension. Replacing a test runtime
invalidates its coordinator before installing the next one.

Palette item loading and outside-click callbacks belong to a presentation
generation. Dismissal invalidates that generation before releasing monitors.
A late completion must never populate or dismiss the next presentation. Sidebar
search adoption follows the panel's reveal generation and retirement state.

`ChromeAppearanceInputs` is the shared policy for expanded sidebar and overlay
colors. Pass wallpaper tone, system scheme and accessibility state explicitly;
do not create a full sidebar snapshot to resolve an overlay color. Native glass
still requires desktop inspection because offscreen bitmaps cannot verify the
WindowServer's backdrop composition.

`WorkspaceSidebarView` retains its SwiftUI state. Paging, controls and surface
composition live in separate extension files; moving presentation code must not
introduce another owner for selection, search, rename or gesture state.
