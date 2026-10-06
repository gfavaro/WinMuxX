# Personal fork: WinMuxX

This fork integrates the six upstream contributions and retains personal defaults
(automatic dwindle and enabled built-in borders). Workspace persistence, display topology handling, learned minimum-size constraints
and sidebar appearance remain fork changes. Minimum-size observations persist
through the frozen-world state and constrain tile/dwindle fitting; interactive
validation is tracked in the roadmap.

## Repository workflow

- `origin`: https://github.com/gfavaro/WinMuxX.git
- `upstream`: https://github.com/ZimengXiong/WinMux.git
- `main`: stable personal integration branch; never rebase or force-push it.
- `feat/*`: personal feature branches, based on `main`.
- `contrib/*`: clean upstream contributions, based on `upstream/main`.

The existing six PR branches are preserved. Do not rebase or delete them while
their PRs are open. Weekly synchronization opens a PR, never auto-merges. A merge
conflict stops synchronization for manual resolution. If upstream squash-merges
a contribution, check for duplicate or altered implementations during integration.

```sh
git fetch upstream
git switch -c feat/my-change main
# For a contribution instead:
git switch -c contrib/my-fix upstream/main
```

## App isolation

Release app: `WinMuxX.app`, bundle ID `com.gfavaro.winmuxx`.
Debug app: `WinMuxX-Debug`, bundle ID `com.gfavaro.winmuxx.debug`.
The CLI packaged in the release is `Contents/MacOS/winmuxx-cli`; it connects to the
fork socket, not the original app. Debug CLI builds connect to the debug fork.
The app's displayed name and bundle identity are WinMuxX. Existing owned configuration
and Application Support directories retain their historical `winmux-gf`/`WinMux-GF`
names so the rename preserves user settings and recovery state. Login registration,
diagnostics, and sockets remain separate. No original launch agents are deleted.

The owned config is `${XDG_CONFIG_HOME:-~/.config}/winmux-gf/winmux.toml`.
On first launch, an existing original WinMux config is copied, not modified.
If none exists, the original AeroSpace import behavior is retained; otherwise a
starter config is generated. `--config-path` overrides this selection. Explicitly
sharing a config makes settings edits shared as well. Never run two window managers
at once: distinct bundle IDs do not prevent competing window manipulation.

## Local build and installation

### Workspace selection across monitors

Selecting a workspace already visible on another monitor now focuses it there,
without exchanging workspaces or changing either monitor's history. This applies
to shortcuts, explicit `workspace --monitor`, back-and-forth, and ordinary activation commands. Sidebar clicks ask for override confirmation
when the target workspace is visible on another display.
Hidden workspaces still activate on the requested/focused monitor, respecting
forced assignments. Explicit move/summon commands retain their own behavior.

### Border compatibility

Borders use the private WindowServer renderer when available. If border creation
is unavailable, the app uses a nonactivating, click-through AppKit panel and
keeps updating its geometry without repeatedly retrying the private renderer.

### Sidebar appearance

The active Settings screen is `ShortcutSettingsView`, whose Appearance destination
is `ShortcutAppearanceSettingsView`; sidebar placement and content live in Sidebar. The old SwiftUI tray renderer and General
screen have been removed; the tray is owned by `NativeActionMenu`.

`chrome-style = 'liquid-glass'` chooses native glass on macOS 26+, with a native
material fallback on older systems. `solid` uses opaque preset/custom colors.
The expanded glass sidebar always uses a frosted surface. `menu-bar-background`
adds regular glass to the compact rail; it defaults to transparent. Reduce
Transparency has priority and makes it opaque.
Legacy appearance/background/frosted-tint fields remain parseable, but the current
style selector determines the runtime appearance. Solid text adapts to color
luminance. Wallpaper contrast samples local files off the UI actor, using the
selected edge of each monitor; no screen capture or network access is involved.
Display, Space, wake and appearance events refresh the cached analysis without a
permanent polling timer. A valid static wallpaper sample takes priority over the
shared menu-bar appearance; unsupported dynamic variants use the native fallback.

`position = 'left' | 'right'` selects the display edge. Expansion remains anchored
to that edge; persistent width is reserved on the same side for tiled windows.
`height-mode = 'standard' | 'centered' | 'full'` controls vertical geometry.
Every mode protects the menu bar and notch, including the auto-hide reveal area.
Centered fits natural content up to 90% of the safe height; Standard and Full
currently have the same geometry. Legacy clearance is honored only without an
explicit height-mode and cannot reduce the mandatory system reservation.

Settings → Appearance → Menu bar chooses Icon or Workspace. Workspace shows the
initial of a configured label, otherwise the workspace number, on the focused
monitor. Icon supports color/monochrome. These preferences live in UserDefaults.

For architecture and validation commands, see [HACKING.md](../HACKING.md).
Investigation and visual-review notes are indexed in [docs/README.md](README.md);
those record historical experiments as well as the final behavior.

### Building

Xcode and the toolchain in `.swift-version` are required; `make xcodeproj` installs
the pinned XcodeGen helper if absent. The build has no Apple team dependency:

```sh
make check
make fork-build BUILD_NUMBER=1
```

Outputs: `.release/WinMuxX.app` and a version/build-number ZIP. The build is not
notarized. By default it uses an ad hoc signature. To keep macOS privacy permissions
across local builds, the script reads a signing identity name from
`${XDG_CONFIG_HOME:-~/.config}/winmux-gf/signing-identity` (or `CODESIGN_IDENTITY`);
the same certificate and bundle ID must be retained. CI without that local identity
continues to use ad hoc signing.
Quit the original window manager, then copy the app to `/Applications/WinMuxX.app`
and open it. The build command does not install, launch, or replace any app.
The old upstream `make install` target is intentionally disabled.

## CI and releases

CI tests PRs and `main`; trusted `main` builds also upload the app ZIP as an artifact.
Bot-created synchronization PRs do not rely on the normal PR event: synchronization
explicitly dispatches CI on its branch. Check that run in Actions before merging.
If dispatch fails, run CI manually on that branch. GitHub Actions must be allowed
to create pull requests in the fork's Actions settings.
Enable GitHub Actions for this fork if disabled. Releases run only on `gf-v*` tags,
test the code again, and require the tagged commit to be part of `main`.
The tag suffix must match `VERSION`. Build numbers use the GitHub run number.
Increment `VERSION` before a new release, then:

```sh
git tag gf-v0.5.7 main  # example; must match VERSION
git push origin gf-v0.5.7
```

Automatic updates are disabled in code and the app plist: no upstream feed or
Sparkle public key is bundled. To enable them later, create fork-owned Ed25519
keys, store the private key as an Actions secret, publish a fork appcast, and
configure the fork public key and feed. Keep the private key out of Git.
Apple certificate-based signing/notarization is a separate future setup.

## Bootstrap verification

Local tests/build results should be recorded separately from hosted CI. Publishing
the branch does not prove the hosted pinned-toolchain build passed. Existing
upstream PRs retain their independent defaults and do not receive fork branding.

Bootstrap local verification: 631 Swift tests and 9 Python tests passed. The
release app and its release CLI were built with local Apple Swift 6.4 / Xcode 27,
not the pinned CI Swift toolchain. Ad hoc signatures and bundled fork metadata
were verified. No app was installed or launched as part of bootstrap verification.
