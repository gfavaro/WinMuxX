# WinMuxX GUI checks with Atlas

Run these commands as the operator in a dedicated host terminal. The CLI
sends GUI actions to the helper. Keep a separate test account with clean
settings and no personal files, account sign-ins, competing window managers
or login items. The helper shares the Mac, CPU, filesystem areas, network
and system services. First validate session confinement before relying on
it for window-management tests. If the main account currently runs a window
manager, use a maintenance window for the initial confinement check or a
separate test Mac or VM. Subsequent same-Mac runs are conditional on that
check and on the APIs and actions under test.

## Set up Atlas

On macOS 14 or later, install Atlas from the
[InsaneArts releases](https://github.com/InsaneArts/atlas/releases) and follow
[Atlas setup](https://github.com/InsaneArts/atlas/blob/main/docs/getting-started.md).
Run `atlas init` and complete the helper login and permission steps. Return
to your main account with the helper still signed in. The commands below
use the Atlas CLI from your host terminal.

## Prepare and identify the artifact

Only build code and dependencies the operator has reviewed. Treat package
manifests, scripts, Xcode phases and test executables as executable code.
From a dedicated clean build checkout at the candidate SHA, use
[HACKING](../HACKING.md), [Testing](TESTING.md) and [FORK.md](FORK.md).
Set up the Swift version specified by `.swift-version` and the schema
virtual environment first.
Use a fresh positive build number. The ad hoc signing override avoids
reading the persistent local signing identity.

```sh
git rev-parse HEAD
git status --short
make check
make fork-build BUILD_NUMBER=1 CODESIGN_IDENTITY=-
test -d .release/WinMuxX.app
codesign --verify --deep --strict .release/WinMuxX.app
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' .release/WinMuxX.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' .release/WinMuxX.app/Contents/Info.plist
codesign -d --verbose=4 .release/WinMuxX.app 2>&1 | awk '/^CDHash=/'
git status --short
```

Run steps in order and stop at the first failure. Compare the bundle ID to
`com.gfavaro.winmuxx`. Record the SHA, build number, CDHash and check
results. Account for generated version/hash changes under Sources/Common.
Use the fresh .app from this build. Leave it in the build checkout. Do not
run `make install`, `make run` or macOS `open` for this workflow.

## Check the helper and get launch approval

Pick a unique session identifier per run, including the build number. Use
the same terminal for every command through cleanup.

```sh
export ATLAS_SESSION=winmuxx-pilot-build1
atlas doctor --json
atlas run -- /usr/bin/id -un
atlas apps
```

Require `ready: true`. Verify the reported user is the expected helper and
differs from the host terminal's `id -un`. Inspect the helper app list
and ensure no other tests or competing window managers are running. Close a
previous test run through its own cleanup. Review the candidate's startup
path and any changed APIs that can act outside the helper. Confirm the
operator approves opening this exact build. Start with clean helper-local
settings and disposable TextEdit documents. The WinMuxX startup code can
import configuration and run startup hooks. Keep personal config, recovery
files, launch agents and login state out of the helper.

Grant the WinMuxX build's Accessibility and any requested Screen Recording
permission only in the helper, via the operator and the normal macOS prompt.
A new ad hoc build can need fresh approval. If the permissions or helper
state require recovery, stop the test and recheck identity before continuing.

## Launch and exercise the app

```sh
atlas open "$PWD/.release/WinMuxX.app"
atlas apps
atlas windows --app WinMuxX
atlas screenshot
```

WinMuxX is an LSUIElement menu-bar app. Confirm the helper app entry and
inspect the helper screenshot for onboarding, permission dialogs or the
menu bar. A visible Settings window is optional at startup. Use the app
name reported by `atlas apps` if it differs. Use the Atlas viewer for the
menu bar or controls that lack a targetable app window. Once the Settings
window is intentionally opened, use `atlas wait --app WinMuxX` and
`atlas elements --app WinMuxX` to inspect it. Inspect a fresh screenshot
or element listing before acting. Use an exact app target for input when
available and verify the resulting state after each action. Do not retry
an unknown outcome blindly.

| Case | Action in the helper | Pass condition |
| --- | --- | --- |
| Launch and Settings | Inspect the menu-bar entry, open Settings and close it | Settings responds and the app stays in the helper. The main desktop keeps its own focus and window geometry |
| Selection and tiling | Create two disposable TextEdit windows. Use the sidebar to select a second workspace and return to the original | The expected windows reappear with their original grouping and layout. Main-session windows stay untouched |
| Explicit movement | Where a second display is visible to the helper and the task needs this case, explicitly move a workspace and move it back | Ownership changes only for the explicit moves. Projects, tabs and nested layout travel together |
| Native follow-ups | Validate hotkeys, physical gestures, permissions, private window APIs, or hot-plug separately when changed | Record real hardware and OS coverage. Mark unavailable cases SKIP with the reason |

For first contact, observe the main account during both launch and the first
window manipulation. Stop if focus, input, layout or other state crosses
sessions. Use Atlas Stop for further agent input and quit the affected test
app as the operator. Atlas Stop alone does not terminate an already-running
WinMuxX. The current WinMuxX uses its own workspaces. Native Spaces are
tracked separately in SpaceMuxX.

## Collect and close

Save or reference only the relevant helper screenshots from the paths Atlas
returns. Redact them before sharing. Store local evidence outside tracked
source, for example under the checkout's ignored `.local/atlas/` directory.
Close only the app instance you opened after checking the session and app
list. Then preview cleanup and apply it only when it names this run's items.

```sh
atlas close --app WinMuxX
atlas cleanup
# After reviewing the preview:
atlas cleanup --apply
atlas apps
atlas cleanup
```

Close synthetic fixture windows without saving personal data. Atlas cleanup
covers tracked staged copies and applies to the selected session or task.
Helper-local settings and macOS privacy grants can persist. Keep them for a
repeatable fixture or reset them through the helper account after the run.
For command outcomes, scope, limitations and recovery see
[Using Atlas](https://github.com/InsaneArts/atlas/blob/main/docs/using-atlas.md).

```text
Candidate SHA / build number / CDHash:
macOS / Atlas version / helper account / display topology:
Case / PASS, FAIL, SKIP or BLOCKED / actual observation:
Evidence path and main-session observation:
Fixture and cleanup status:
```
