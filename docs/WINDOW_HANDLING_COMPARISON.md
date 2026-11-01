# Window handling: WinMuxX, WinMux and Dinky

Reviewed 2026-11-01. This compares how each project identifies windows and their apps,
reaches them through Accessibility (AX), isolates slow apps, writes frames, hides
inactive windows and reports failure. Layout algorithms are out of scope; see the
[Dwindle comparison](DWINDLE_DINKY_COMPARISON.md). Native Spaces specifics are in the
[native Spaces comparison](NATIVE_SPACES_DINKY_COMPARISON.md).

| Project | Revision | Notes |
|---|---|---|
| WinMuxX | `feat/native-spaces` `e46116bd`, build 262 | Installed and running when reviewed |
| WinMux (original) | `upstream/main` `470eedbf`, v0.5.6 | The fork point; no upstream commits since |
| Dinky | `efa24ab`, v0.23 | Source inspected, not built or run; MIT, see [license](licenses/Dinky-MIT.txt) |

Evidence is source reading unless marked **measured**. Dinky was read in its window
model, frame applier, frame scheduler and coordinator, not exhaustively.

## Summary

WinMuxX keeps WinMux's architecture: a long-lived app object per process with its own AX
thread, which windows hold for life. That design isolates slow apps and supports the
richer model (workspace trees, tab groups, whole-workspace moves, restart recovery), but
a window bound to a destroyed app object fails silently. Dinky has no app object at all:
windows are WindowServer-first and AX elements are a disposable cache, so that failure
class cannot occur.

WinMuxX's [Safari parking bug](#the-orphaned-window-bug) was a fork regression: WinMux
confirmed termination with `isTerminated` and never destroyed a running app's object.

Recommendation: keep WinMuxX's per-app threads and model; keep moving its identity rules
towards Dinky's (one stable app object per process, failures visible). The open items
are under [Recommendations](#recommendations).

## Comparison

| Area | WinMux (original) | WinMuxX | Dinky |
|---|---|---|---|
| Window identity | `MacWindow` by window ID, holding `let macApp` | Same | `Window.Identity(id, pid, firstSeen)` from WindowServer; `firstSeen` rejects a reused window ID (`WindowModel.swift`) |
| App identity | `MacApp` per pid in `allAppsMap`; `getOrRegister` returns any existing entry for the pid | Same map; `isSameRunningProcess` (`isEqual`), `appRegistrationDecision` never evicts a live registration | No app object; pid only |
| App teardown | GC destroys when `nsApp.isTerminated` | GC uses the observed running-apps cache, confirmed by `isTerminated`; `destroy` retires synchronously and removes only its own registry entry | `forget(pid:)` drops cached elements on `didTerminateApplication` |
| AX isolation | One thread and run loop per app; app element timeout 1 s, focus queries 0.25 s; per-app refresh deadline 1.5 s | Same, plus `AXReadBudget` per refresh | One serial queue per pid (`FrameScheduler`); AX timeout 1 s; raises on a separate queue |
| Element lookup | Registry only; a stale element yields nil until a refresh re-registers | `withRecoverableWindow` re-looks up once on `.invalidUIElement`; discovery adds main and focused windows to `AXWindows` | Cache keyed by (pid, window ID); `lookUp` creates the app element and finds the window; re-looks up once on `.invalidUIElement` |
| Frame write | Size, position, size again only if it changed; Enhanced UI off during the write, restored after | Same, plus a position-first path for parked windows, native ownership permits and animated steps | Size, position, size; newest frame per window wins |
| Write confirmation | None | A tiled write that changes size is read back twice, 150 ms apart; a refused size becomes a learned minimum and the layout adapts (`MacWindow.setAxFrame`). App-initiated moves are put back by `VirtualFrameRecovery` | Every window read back; written once more if it landed elsewhere |
| Minimum sizes | None | Learned per window and persisted per bundle ID (`PersistedAppMinimums`), seeding every new window of the app; reset from Settings | Learned, persisted per bundle ID so a new window is right the first time |
| Enhanced UI | Toggled per write | Toggled off and restored around each write, left untouched while VoiceOver or Switch Control runs (`AssistiveTechnology`) | Disabled before each batch and left off, except under VoiceOver or Switch Control |
| Hiding inactive workspaces | Parked in a screen corner; parking trusted its own flag | Virtual mode parks, verifies the parked frame through WindowServer, and records parking only when the write reached an element; native mode uses Spaces | Native Spaces through SkyLight; nothing is parked |
| Window events | AX observers per app | AX observers; native mode adds WindowServer lifecycle events | WindowServer (SkyLight) notifications |
| Failure visibility | Silent nil | `doctor` window reachability; a window that cannot be parked is logged once | Logs a window whose element is gone after invalidation, and writes that cannot be read back |

## The orphaned-window bug

In virtual mode a Safari window, and later Rex, stayed visible on whichever workspace was
showing. AppKit returns different `NSRunningApplication` objects for one process
(**measured**: `frontmostApplication` and pid lookups are `isEqual` but not `===` to the
`runningApplications` entry). Commit `91768903` made GC compare them by `===`, so an app
registered while frontmost was destroyed while running. Its windows kept the destroyed
`MacApp`, every move and park became a no-op, and parking still recorded success.

- WinMux: not affected; GC asked `isTerminated`.
- WinMuxX: fixed in `076c4f5b` (process equality) and hardened in `a9d85eda`
  (lifecycle, loud parking failure) and `677dca2d`, `45141c3e`, `e46116bd` (`doctor`).
- Dinky: cannot occur; no object outlives its process or is shared by windows.

**Measured** cost of the equality fix on this Mac: `===` 2.4 ns, `isEqual` between distinct
objects 5.8 µs (it reaches LaunchServices), `isTerminated` 17 ns. Equality runs only when
the objects differ and only for registered apps, about 40 µs per refresh at worst.

## Where each design is stronger

**WinMuxX** supports what the others do not: nested workspace trees, tab groups, projects,
whole-workspace display moves, restart recovery, and both virtual and native backends.
Per-app threads keep one hung app from stalling the rest. Parking verification catches
apps that move their own windows back, which WinMux missed.

**WinMux** is simpler in app lifecycle: by never replacing a pid's app object, it could not
orphan windows, at the cost of a LaunchServices request per app per refresh.

**Dinky** has the most robust identity model, reads back every write including moves, and
retries a write that landed elsewhere. WinMuxX instead reads back size changes, turns a
refusal into a learned per-app minimum and lays out around it. Both persist minimums per
bundle ID and leave Enhanced UI alone for assistive technology users.

## Recommendations

1. Keep WinMuxX's architecture; do not replace `MacApp` with Dinky's stateless lookup.
2. Bind refresh results and pending registrations to the process instance that produced
   them (deferred step 4 of the lifecycle review), only if another lifecycle bug appears.
3. Read-back confirmation and per-app minimum sizes already exist (see the table); an
   earlier draft of this review missed them.
4. Done: Enhanced UI is no longer toggled while VoiceOver or Switch Control runs. A manual
   VoiceOver check of workspace switching remains worthwhile.
