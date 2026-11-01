# Native Spaces interactive validation — 2026-10-26

This records executed native checks separately from automated coverage. It does
not certify the remaining OS, hardware or interaction matrix.

## Environment and scope

- Apple Silicon, macOS 27.2 (26B118), SIP enabled; no security settings changed.
- One connected external display, logical viewport 1710 × 1112 points.
- Native desktop 5094, UUID `BB8CBEFB-914E-921B-1D2B-B35C8837ADA5`.
- Two disposable resizable AppKit windows from `script/native-spaces-fixture.swift`.
  The test desktop also contained one existing terminal window: the positioning
  test therefore involved three windows from two applications, not an empty desktop.
- Separate development configuration with native tiling enabled and
  `restore-layouts = false`; no personal configuration or installed build replaced.
- Installed virtual manager paused through its CLI. A separate 180-second watchdog
  stopped the development process and re-enabled the installed manager. The first
  session reached that deadline; the second ended through its finish signal.

The tested frame engine was commit `d7d77c55`, with additional per-window doctor
diagnostics. The subsequent queued-command target fence has automated validation;
its new cancellation paths were not exercised through an interactive Space switch.

Final `make check` passed 1,454 AppBundle and 40 NativeSpaces tests (1,494 Swift
tests), 19 schema fixtures covering 52 parser keys, all script checks and dependency
resolution. Coverage includes changed native owners/focus, observed Space switches,
window-ID reuse, execution-time revocation and invalidation during a floating-size
read, plus preservation of unsupported nested groups before frame application.
These are automated safety tests, not additional physical validation.
Temporarily bypassing target revocation made the observed-Space-switch regression
test execute and fail its behavioral assertion. The production fence was restored
before the final passing full gate; the red-run log is
`.build/native-target-fence-red.log`.

## Observed results

| Check | Actual result |
| --- | --- |
| Dwindle positioning | Three live CG frames exactly matched their calculated layout targets; maximum discrepancy 0 points. |
| Master and resize | `workspace-layout --window-id … master`, then `resize --window-id … width +50`, produced the expected master/stack arrangement. All three settled CG frames matched targets exactly. |
| Explicit native focus | `focus --window-id …` selected Native Fixture 1 from Native Fixture 2. The UI tool confirmed the actual focused AX window. Cross-application focus was not checked. |
| Minimize | Minimizing Fixture 1 retained all three tree windows while marking it ineligible. The two remaining visible frames exactly matched their new targets. |
| Restore | The fixture's native Window menu restored Fixture 1. It became eligible again, regained its preferred Master pane and all three frames matched targets exactly. |
| Native fullscreen | The standard green window button created native fullscreen Space 5196, type 4. WinMuxX reported “no active ordinary desktop,” retained three windows and had zero eligible preflight identities. |
| Exit fullscreen | Escape returned to desktop 5094. Fullscreen Space 5196 disappeared, ordinary desktop UUIDs remained unchanged, tiling resumed, and all three CG frames matched their targets exactly. |
| Unrelated desktop | Fifteen windows belonging exclusively to desktop 4 had identical CG bounds before and during the first native tiling session. No change to those frames was observed. |
| Mission Control detection | A bounded read-only probe compiled the production transition guard. User-assisted opening produced `false → true`; closing produced `true → false`. The user confirmed the final open/closed states. This validates the host's overlay signature, not an end-to-end native tiling pause/resume cycle under Mission Control. |
| Cleanup | Both development managers and fixture applications exited. Installed manager PID 70487 remained running and its CLI reported enabled. Native persistence file remained absent. |

The command response acknowledges model execution; it does not wait for all queued
AX frame writes to land. Frame comparisons above used later settled snapshots,
rather than treating an immediate successful CLI exit as physical validation.

One debug-process sample after fullscreen exit measured 0.1% CPU and 101,056 KiB
RSS. This is not a sustained profile or a comparison against an equivalent virtual
debug build. No performance regression conclusion is drawn.

## Evidence

Local, ignored `.build` artifacts retain the relevant observations:

- `native-validation-dwindle-doctor.txt` and `native-validation-dwindle-actual.json`
- `native-validation-settled-doctor.txt` and `native-validation-settled-actual.json`
- `native-validation-minimized-doctor.txt` and `native-validation-minimized-actual.json`
- `native-validation-restored-doctor.txt` and `native-validation-restored-actual.json`
- `native-validation-fullscreen-doctor.txt` and `native-validation-fullscreen-spaces.json`
- `native-validation-fullscreen-exit-doctor.txt`, `native-validation-fullscreen-exit-actual.json`
  and `native-validation-fullscreen-exit-spaces.json`
- `native-mission-control-observed.jsonl` and `native-mission-control-close-observed.jsonl`
- `native-validation-watchdog.log` and `native-validation-check.log`

The Mission Control close probe recorded `true` at 22:46:46 UTC and `false` at
22:46:54 UTC. Sampling was limited to this diagnostic session at four reads/second;
no corresponding permanent polling loop was added to WinMuxX.

## Remaining validation

Not performed: physical trackpad gestures while the native manager is active;
ordinary-desktop switching with queued commands; end-to-end Mission Control tiling
pause/resume; cross-app focus or overlapping tab/Accordion ordering; attached
sheets; restrictive/delayed application resizing; native persistence across actual
app/manager restart; sleep/wake; Stage Manager; multiple displays and relocation;
disconnect/reconnect; rcmd; macOS 15/26; sustained comparable performance profiles.

Computer-use desktop shortcuts did not switch Spaces in this environment. Ghostty
UI access was rejected by the computer-use safety check, so no Ghostty-specific
computer-use interaction or content inspection was attempted. Mission Control had no working launch control in
the UI tool. User-assisted desktop switching and Mission Control observation were
used instead. These tool limitations are not evidence of native gesture failure.

Native navigation, sidebar/palette/overview integration, overlapping group layouts
and project mapping remain implementation milestones. Virtual remains the default.
