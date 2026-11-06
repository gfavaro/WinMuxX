# Workspace and configuration state cleanup

This is one implementation effort, including verification and installation. It completes the
workspace/configuration ownership cleanup previously deferred after Settings build 75.

## Scope and decisions

Use one main-actor runtime owner for configuration (value, source URL, reload gate,
watcher/scheduler, readiness and diagnostics), workspace/project/viewport registry, logical
focus/history/native-focus holds, hotkey registration/mode/tap/sequence state, recovery snapshots and pending recovery tasks,
and main-thread monitor caches/test overrides. Keep the
existing command and configuration syntax. Keep short computed configuration/focus accessors
where they express existing domain operations; they must not own independent storage.

Production has one process-lifetime owner. Tests can construct independent owners and bind
one for a scoped operation, including suspension. Legacy serial fixtures replace the whole
owner instead of resetting an expanding list of its fields. Do not claim all tests can run
in parallel: native window registries, UI singletons, refresh scheduling and persistence still
have process lifetimes. Native AX objects and multitouch callbacks retain their existing
thread ownership. This effort does not rewrite these unrelated subsystems or change layouts.

## Execution and completion criteria

1. **Inventory and ownership.** Introduce the runtime owner and explicit configuration state;
   migrate the workspace registry to it, removing its standalone mutable global. Preserve
   registry sorting caches, IDs, project indexes and display assignment rules.
2. **Focus lifetime.** Move requested/last/previous focus, workspace history, recursion guard
   and native focus holds into owned state. Initialize focus lazily, avoiding startup cycles.
   Fresh test runtimes must have no history or holds from the previous test.
3. **Configuration lifecycle.** Own the reload gate, diagnostics, watcher and scheduler.
   Publish config and URL together before dependent observers run. Bind reload work to its
   originating runtime across awaits; preserve dry-run, failure and reentrancy semantics.
4. **Monitor lifetime.** Own caches, invalidation observation and test monitor overrides.
   Remove unsafe mutable monitor globals. Preserve the uncached off-main native lookup path;
   only main-actor callers touch owned caches. Release notification observation with its owner.
5. **Fixtures and regression coverage.** Replace the runtime as a unit in legacy setup;
   remove obsolete granular reset functions. Add independent-owner, scoped async lifetime,
   focus history, monitor invalidation and configuration publication regression tests.
6. **Acceptance.** Run the complete existing checks plus new regressions, build signed release,
   install it with rollback archive, verify signature/CLI diagnostics and compare live workspace,
   window, display and focus state. Record actual results and limitations here and in TESTING.md.

No performance improvement is assumed: preserve caching and existing operation-count tests.
Desktop swipe latency and manual multi-display UI interaction are separate measurements, not
substitutes for these ownership checks.

## Results

Stages 1–5 complete. Config, workspace registry, focus/history/holds, monitor caches,
hotkeys and recovery state are owned. Obsolete granular resets were removed. Scoped
bindings and deferred work preserve owner identity across suspension. Monitor snapshots
are immutable/Sendable; main/list/sorted caches invalidate together, with no unchecked
Sendable conformance or unsafe mutable monitor globals.

Stage 6 complete: `make check` passed 1,073 Swift + 13 Python tests, including twelve
new runtime regressions. Signed build 76 was built, installed and strictly verified;
build 75 is archived at `.release/WinMuxX-before-runtime-build76.zip`.

Live CLI checks selected workspaces 1 and 2 on the built-in display and verified the
Samsung viewport did not change. All six window/workspace associations and populated
workspace display ownership/visibility matched the pre-install snapshot. The original
focused window was restored with the existing focus command after restart/navigation.
The secondary remained empty; its generated raw workspace name changed from 5 to 4
at startup. The first sample was taken before display discovery had settled; the
final sample and doctor reported both displays. The user config SHA-256 was unchanged.

Diagnostics report valid configuration, Accessibility and screen capture granted,
and the raw-touch backend listening. No desktop latency, manual gesture/sidebar or
hotplug validation is claimed. Native/UI/refresh process adapters remain explicitly
outside this ownership scope; the complete suite remains serial. All six stages of
this workspace/configuration cleanup are complete.
