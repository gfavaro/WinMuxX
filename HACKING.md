# Developing WinMuxX

WinMuxX is a personal fork of WinMux. Read [fork maintenance](docs/FORK.md) for
bundle identity, configuration ownership, upstream integration and signing policy.
Current user-facing options are described in [README.md](README.md). Historical
investigations and reviews are listed in the [documentation index](docs/README.md).

## Build and check

Development requires macOS and Xcode. `Package.swift` defines Swift targets;
`.swift-version` pins the toolchain used through `script/setup.sh` and CI. The app
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
`${XDG_CONFIG_HOME:-~/.config}/winmux-gf/signing-identity`, unless
`CODESIGN_IDENTITY` is supplied. Retain the identity and bundle ID across installs
to preserve macOS permissions. Without a configured identity the build is ad hoc.

The build does not install. Quit the current fork, save a ZIP backup, copy the new
bundle to `/Applications/WinMuxX.app`, verify it with
`codesign --verify --deep --strict /Applications/WinMuxX.app`, then open it.
Never rename an old bundle to `WinMuxX.app-previous-*`: archive it outside
Applications instead. `make install` is intentionally disabled. The installed
CLI is `WinMuxX.app/Contents/MacOS/winmuxx-cli`; `--version` compares client and
server versions. Installation and validation of interactive behavior are separate
from compilation and automated tests.

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

Settings navigation lives in `ui/settings/ShortcutSettingsView.swift`. Each config
pane has a `Settings*View.swift` file; controls and TOML persistence are shared in
`SettingsControls.swift` and `SettingsConfigPersistence.swift`. A TOML edit is
validated, written, reloaded and reflected through the settings model. Menu-bar
preferences use UserDefaults and publish through TrayMenuModel. Add controls to
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
