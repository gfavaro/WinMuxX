# Claude audit discussion — 2026-11-06

Claude Code was restricted to Read, Grep and Glob, with external MCP servers
disabled. These are its responses, retained as review evidence rather than
authoritative instructions. Codex checked the disputed source and responded
between rounds; the final reconciled position is in REFACTOR_AGREEMENT.md.

## Round 1: Independent assessment

# My assessment of REFACTOR_AUDIT.md

I read the audit and checked the source behind about a dozen findings. I didn't edit, build or test anything. Overall the audit is careful and its "behavior to preserve" notes are mostly right. But a few findings are weaker than they look, one would be unsafe if read loosely, and some duplicate items already in the review queue.

## Where I disagree or would add caveats

**RF-02 is not a simple deletion, and the audit's own caveat actually applies here.** `runtime.workspaces.visibleWorkspace(for:)` is `mutating` and calls `ensureMonitorViewportExists` (`WinMuxWorkspaceState.swift:125-128`). So the empty `if` at `WorkspaceMonitorAssignment.swift:136` does change state: it creates a viewport for the monitor at that corner. I still think removing it is safe:
- `setActiveWorkspace(_:on:)` calls `ensureMonitorViewportExists(viewportId)` first (`:138`).
- `MonitorViewportId(monitor)` and `MonitorViewportId(topLeftCorner: self)` are the same value (`WorkspaceIdentity.swift:68-75`).
- The `isWorkspaceActive` guard runs before the lookup, so it can't see the side effect.

The audit should state this reasoning rather than leave "confirm no side effect" as a to-do. It isn't purely cosmetic either: it touches workspace display assignment.

**RF-04's "only after confirming resolve has no side effects" check is already settled by line 170.** `config.keyMapping.resolve()` is called there for `parseModes`, so calling it again at `:173` adds nothing. One thing the audit misses: `shouldValidateMainMode` at `:174` still treats `shortcutsPreset != .none` as a trigger. That legacy coupling has to stay, or `rectangle` configs will report different errors.

**RF-13 isn't worth doing yet.** The duplicated block is about five lines (`WorkspaceSidebarActions.swift:70-75` and `:92-97`). It sits on the explicit-relocation path, which AGENTS.md calls the defining capability. Also, "coordinate-based Bring Here" is wrong: it resolves by `targetMonitorScopeId`. If the two error messages are meant to stay identical, extract only the message string. A shared "relocate and focus" helper invites someone to call it from the ordinary-selection path at `:59`.

**RF-24 overstates the problem.** `canSkipPostCommandRefresh` is already a protocol requirement (`Command.swift:15`). The type list is just the default in an extension, and `AgentCommand` overrides it. A per-command metadata scheme already exists. The real issue is that the default list is opt-in by type, which is safe because unknown commands get a full refresh. Moving it to "a centralized descriptor" is a redesign with no measured benefit. I'd drop this or reduce it to a comment.

**RF-05, RF-06 and RF-30 shouldn't start now.** Their target files (`SettingsControls.swift`, `SettingsSearch.swift`, `NativeActionMenu.swift`) are uncommitted work that hasn't been validated on the desktop yet. RF-06 is the same as queued UI-07, and RF-30 overlaps UI-03. Keeping both in REFACTOR_AUDIT and REVIEW_QUEUE means tracking each twice. Commit the current tree first, then pick one tracker.

**RF-05 sees the problem but misses its size.** `ShortcutSettingsModel.shared` appears 11 times in `SettingsControls.swift`, including an `@ObservedObject` default at `:477` and `onReceive` at `:318`. That's a broad change across the view tree, not a "targeted refactor". It also changes behavior in tests and only improves test isolation, so I'd rank it below the work that guards user data.

**Low-value items I'd drop:**
- **RF-16:** cosmetic. `project!` straight after an assignment can't crash.
- **RF-26:** marketing code that only renders images.
- **RF-27:** moves code between files with no clear benefit.
- **RF-21:** cleaning up tuple return types in a transport that works and has tests.
- **RF-28:** the audit admits there's no measurement. Keep it only as "benchmark if a layout ever feels slow."

## The five strongest behavior-preserving refactors

1. **RF-07: store each restart snapshot with its matched windows in one entry.** Verified. `restartMatchedWindows` is rebuilt as `pendingRestartSnapshots.map { _ in [:] }` in four places (`persistedFrozenWorld.swift:77, 89, 312, 325`) and appended separately at `:437`. It's indexed by `index` captured before an `await` (`:460`, `:488-490`) and used afterwards (`:497`, `:512`). That's only safe because of the `restartRestorationsInFlight` compaction barrier. Note that the 30-second expiry task at `:312` resets matches without checking that barrier. That may be fine, since it doesn't reindex, but write a test for it before migrating. This finding has the best ratio of risk removed to code changed, because a bug here loses the user's workspace layout.
2. **RF-09: pull the parking-corner geometry out of `layoutWorkspaces`.** Verified at `refresh.swift:613-636`. It's a pure function of monitor rectangles buried inside a function full of native writes. Extracting it makes the strict `<` comparison (ties go to bottom-right) testable for adjacent and stacked displays without touching any orchestration. One correction: `important` isn't unexplained. It weights the exact-corner probe, and this code came from upstream, so give it a name rather than treating it as a mystery.
3. **RF-01: remove the leftover minimum-observation code.** Verified: the unused `oldMinimum` at `MacWindow.swift:474` and `&& true &&` at `:491`. This is a trivial, warning-clearing cleanup. Keep the order of the generation and cancellation checks.
4. **RF-15: store each overview display's model and panel in one entry.** These are the same kind of parallel arrays as RF-07 (`WorkspaceOverviewController.swift:107-108`). With rapid dismiss/reopen and displays being removed, an index mismatch is plausible. Do this after RF-07 using the same pattern.
5. **RF-25: split installer polling from its decisions, tested with fake operations only.** `verify()` (`install_fork.py:233+`) controls rollback of the live app. Recording each poll's observations in one record makes the 150-attempt / three-ready-sample policy reviewable. `install_fork.py` is also modified in the working tree, so this waits for that commit.

Runners-up: RF-02 with the reasoning above, and RF-18 (naming the restore steps) if recovery tests are expanded first.

## Release workflow schema environment: confirmed

The audit is right, and the failure is certain rather than just likely:
- `makefile:88` checks for `./.deps/config-schema/bin/python` with `test -x` and exits 1 if it's missing, before any test runs.
- `.deps` is gitignored (`.gitignore:21`), so a fresh checkout never has it.
- `release.yml` only installs Swift (`:35-39`) and then runs `make check` (`:41`). It has no `setup-python` step and no venv step.
- `ci.yml:37-45` does both, with Python pinned to 3.14.

Any `gf-v*` tag push fails at "Test", before signing. Because of that, the `if: always()` keychain cleanup runs with no keychain to remove; the cleanup script should handle that cleanly, so check it. The audit is honest in calling this unobserved on a hosted runner. The fix should copy CI's pinned `setup-python` and venv steps (or share them through a composite action). It shouldn't rely on whichever `python3` the runner happens to have, or release and CI will use different Python versions. Keep it as a separate commit from any refactor.

## Invariants every change must protect

- **Selection vs. movement:** ordinary selection (`activateWorkspaceForUser`) never changes which display owns a workspace. Only explicit relocation calls `activateWorkspaceOnMonitorPreservingSourceViewport`.
- **One active display per workspace:** a workspace is active on at most one display viewport, and `checkWorkspaceHierarchyInvariants` runs after each assignment.
- **Projects and layouts survive:** projects, workspace IDs, nested layouts and tabs are kept through every restore, move and recovery.
- **Restart restore:** snapshot indices stay stable while any restoration is in flight. The stored file format doesn't change. Late restores rebuild only the destination workspace and never repeat display selection.
- **Native reads:** re-check identity and generation after every `await`. Treat "unknown" AX state differently from "confirmed absent". Keep the cancellation checks before confirmation reads.
- **Refresh:** unknown commands always get a full refresh.
- **Parking:** windows are parked before others are revealed, and tie-breaking rules don't change.
- **Settings saves:** committed saves complete even if the page that submitted them disappears.
- **Personal fork:** signing identity, bundle ID and recovery data are left alone.

One process point: the audit says these refactors are "behavior-preserving", but several need characterization tests written first (RF-07, RF-09, RF-15), and the parking and overview changes still need checks on physical displays. I'd require those tests to exist before each change starts.


## Round 2: Response to corrections and proposed ordering

# Final position on the audit

## RF-13: your correction is right

I checked the code and you're right. `workspaceSidebarMonitorScopeId(for:)` builds `monitor:<x>,<y>` from `rect.topLeftCorner` (`WorkspaceSidebarMonitorScope.swift:7-13`). `workspaceSidebarMonitor(forScopeId:)` parses that back into a point and matches it against `topLeftCorner` (`:28-29`). Move to Display looks the display up by UUID instead, ignoring case (`:33-36`). So Bring Here goes through a scope ID that is built from coordinates.

Two details make the split matter more than either of us said:
- **A focused-display alias.** `forScopeId` also accepts `workspaceSidebarFocusedScopeId`, which maps to the focused workspace's display (`:25-26`).
- **Different failure behavior.** If the workspace or target is missing, Bring Here returns silently (`WorkspaceSidebarActions.swift:66-69`). Move to Display shows a specific error for each case (`:84-91`).

Any shared helper must start after the target is resolved, and both lookup paths stay as they are. I still think only the assignment-error message is worth sharing.

## Ordering: defensible, with three changes

Your sequence holds up. Here's what I'd adjust:

0. **Commit the current uncommitted tree first, as its own baseline.** Do it through the normal `make check` path. Right now the Settings, menu, sidebar and installer changes aren't committed. If refactors land on top, no diff can be reviewed on its own and a revert can't be done cleanly. This isn't refactoring, but every step below depends on it.
1. **Fix the release prerequisites.** Copy CI's pinned `setup-python` 3.14 step and the venv step into `release.yml` before `make check`. Keep it in its own commit. We can only fully validate it with a real tag run, and that's the user's call because it publishes a release.
2. **RF-01**, then **RF-09 (parking-corner extraction)**, as two separate commits. For RF-09, write a characterization test first that runs the *current* inline expression on these layouts:
   - side-by-side displays
   - stacked displays
   - an offset secondary display
   - a tie case
   
   Then extract the function and show the results match. Name the constant after what it does (the weight given to the exact-corner probe). The test runs before the extraction, not alongside it.
3. **RF-02, now that we've agreed the reasoning.** Add a test asserting the target viewport still exists after a refused assignment and after an accepted one. Classify it as policy-sensitive, as you proposed.
4. **Characterization tests for restart restore, then RF-07.** Tests should cover:
   - a restore suspended at the `restartWindowIdentities()` await while another snapshot is appended (`persistedFrozenWorld.swift:437`)
   - compaction deferred while `restartRestorationsInFlight > 0`
   - the 30-second expiry (`:309-315`) firing during an in-flight restore. It resets matches and then calls `compactPendingRestartSnapshots()` without its own barrier check. The tests should pin down whether that's harmless.
   - the saved file's contents compared byte-for-byte before and after.
   
   Only then combine each snapshot and its matched windows into one entry, migrating one operation at a time.
5. **RF-15** (overview display model and panel stored together), using the same pattern as RF-07 and only after RF-07 has settled.

Further down the list:
- **RF-25 (installer verification split):** after the baseline commit, tested with fake operations only.
- **RF-18 (naming the restore steps):** only alongside expanded recovery tests.

Each step needs `make check`, with native validation reported separately. Steps 2, 4 and 5 still need a check on physical displays: display disconnect and reconnect, relaunch with windows open, and rapid overview open and close.

## Explicitly do NOT implement

- **RF-24 descriptor redesign.** Keep the `canSkipPostCommandRefresh` protocol requirement and its per-command overrides. At most, add a comment that unknown commands default to a full refresh.
- **RF-13 shared relocate-and-focus helper.** Share at most the error string.
- **RF-05 as a refactor now.** It's a broad change to how the Settings view tree gets its model, and it only improves test isolation.
- **RF-06 and RF-30 as audit items.** Fold them into UI-07 and UI-03 so each is tracked in one place.
- **Low-value items: RF-16, RF-26, RF-27, and RF-21's `Result` migration.** They're cosmetic, marketing-only, file moves, or a churn of working transport code.
- **RF-28** unless a benchmark shows a real slowdown.
- **Removing the `rectangle` preset case, or the `shortcutsPreset != .none` main-mode trigger at `parseConfig.swift:174`.** RF-04 is just a rename and dropping the unused parameters.
- **Anything the audit's "keep these designs" section rules out:**
  - generic state machines in place of `DockSwipeTracker`
  - a new queue type for `SubscriberEventWriter`
  - merging the native and AppKit border paths
  - merging the config-watcher and writable-file symlink handling
- **Replacing refresh generations with a busy flag** in RF-08. I'd defer RF-08 entirely until RF-07 shows the staged approach works.


## Round 3: Explicit confirmation of agreement

Yes, we agree. Both of your corrections are right.

**RF-02:** My earlier wording was wrong. The guard at `WorkspaceMonitorAssignment.swift:132-135` returns `false` before execution reaches the empty `if` at `:136`. A rejected assignment has never reached `visibleWorkspace(for:)` or the `ensureMonitorViewportExists` call in `setActiveWorkspace(_:on:)`. So I was wrong to say the target viewport "still exists after a refused assignment". The correct invariant is yours: a rejection changes nothing and doesn't create a viewport that wasn't there before. An accepted assignment creates and activates the viewport. These need two separate tests.

**RF-07 fixtures:** Agreed. One addition: holding timestamps fixed isn't enough, because time also feeds into the restore logic.
- `isExpired()` filters snapshots at load (`persistedFrozenWorld.swift:317`).
- `lateRestartTreeDeadline` is set from `.now` (`:307`).

The tests need a controlled clock, or fixtures placed well inside the expiry window, so the 30-second-expiry and in-flight-restore tests behave the same on every run. The expiry task only runs when `!isUnitTest` (`:308`), so testing that case may need a test hook. That's for the person implementing it to decide later; I don't disagree with the plan.

I also confirm the scope of this discussion:
- No implementation, commits, tags or releases.
- The baseline commit is a prerequisite we recommend, not something done here.
- RF-06 and RF-30 become cross-references to UI-07 and UI-03.
- RF-08 waits until the restart pairing work is settled.

I have no remaining concrete disagreements.

