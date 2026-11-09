# Testing

## Fresh-checkout setup

Use the macOS/Xcode and Swift version in [HACKING](../HACKING.md). The full check
also needs the schema test environment used by CI. From the repository root,
create it if absent and install pinned requirements:

```sh
python3 -m venv .deps/config-schema
./.deps/config-schema/bin/pip install --requirement requirements-schema.txt
```

Use the project-local environment rather than changing system Python or dependency
pins. Then run `make check`; its setup validates the Swift version.
The gate reports a missing schema environment immediately and runs schema validation
before the Swift suite, so setup errors do not waste a full compile/test cycle.

Before a direct focused Swift command, verify the active compiler too:

```sh
./script/check-swift-version.sh "$(swift --version)"
```

If it fails, select the pinned toolchain using the setup in HACKING; do not change
the pin as a workaround. If dependencies cannot be installed, report the setup
blocker and the checks still possible without them.

## Running and interpreting checks

Run `make check` before submitting runtime, test, build or validation-script changes.
Documentation-only changes use the lighter checks described below. The full gate runs the Swift suite, Python
release checks, and dependency lockfile validation. It captures the full Swift output in
`.build/test-output.log`; CI uploads that log even when a test fails. The pipeline
preserves Swift's exit status, so logging cannot turn a failure into a pass.

For focused checks, use `swift test --no-parallel --filter <TestClassOrMethod>` and
confirm the intended XCTest suite executed a nonzero number of tests. A trailing
Swift Testing summary of zero tests can coexist with a successful XCTest run;
read the relevant suite summary. Prefer direct commands. When piping output, use
`set -o pipefail` so `tee` or `tail` cannot mask failures. Avoid shell-reserved
variable names such as zsh's read-only `status` when recording exit codes.

For documentation-only contributor guidance changes, run
`python3 script/check_contributor_guidance.py` and `git diff --check`; inspect new
examples against source. Runtime changes still require the full gate below. Changes
to the checker itself also run `python3 -m unittest script/test_contributor_guidance.py`.

SwiftPM currently [does not produce XCTest xUnit reports in serial mode](https://github.com/swiftlang/swift-package-manager/issues/9961).
Keep the complete log rather than uploading a misleading empty report or enabling
parallel execution solely to obtain XML.

## Choose the appropriate test

- Test pure policy and geometry with deterministic inputs and observable results.
- Test command behavior through parsing and execution when command routing matters.
  Also assert that unrelated displays and workspaces remain unchanged.
- Keep native rendering and filesystem integration tests identifiable. The
  `WorkspaceSwipeRenderingTest` uses offscreen Metal rendering, with no desktop
  capture or interaction. It explicitly skips when Metal is unavailable; rendering
  failures on supported hardware fail the test.
- Use isolated manual validation for physical trackpad feel, native Spaces
  conflicts, real application Accessibility behavior, permission changes, and
  display hot-plugging. Mocked monitors and rendered curves do not prove those
  behaviors work on the desktop.

For a bug fix, reproduce the user's sequence and confirm the regression test fails
against the old behavior before fixing it. Assert the expected result and relevant
invariants, rather than reproducing the implementation's calculations in the test.
Include cancellation, boundaries, and rejection paths where they change behavior.
Avoid assertion-count or coverage-percentage goals that encourage redundant tests.

## Isolation and cleanup

Workspace/configuration state belongs to WinMuxRuntime. New focused tests can
construct independent owners and bind them with `withValue`, including across
suspension. The broader suite still uses process-scoped native registries, UI
singletons and refresh/persistence adapters, so `make check` passes `--no-parallel`
explicitly. Main-actor isolation alone does not isolate tests across suspension.

New tests using the workspace world should inherit `WorkspaceTestCase`, which
pairs `setUpWorkspacesForTests()` in setup and teardown even when a test throws.
When extending a suite already using `WorkspaceNavigationFixture`, reuse its paired
setup/cleanup rather than adding a second runtime reset. Its three displays and
populated workspaces are defined in `Sources/AppBundleTests/testUtil.swift`.
Pure helper tests should continue using XCTestCase without a workspace fixture.
The fixture replaces the runtime as a unit (configuration, monitor caches/overrides,
focus/history/holds, hotkey state, recovery and workspace registry), then resets the
remaining process-level test adapters, including scheduled refresh overrides. Tests that install their own fixture must clean it up
in teardown as well. Register cleanup with `defer` or `addTeardownBlock` immediately
after acquiring temporary files, global overrides, windows, watchers or tasks.
Do not rely on the next test to clean up. Never use real user configuration files
as writable fixtures; use unique temporary directories or isolated defaults suites.

## Asynchronous and timing tests

Coordinate callbacks with XCTest expectations and a finite timeout. Do not use
unbounded `Task.yield` loops or checked continuations as the test's only completion
signal. Release continuation gates and cancel tasks during cleanup, including when
an assertion fails. A deliberately cancellable delay that models an in-flight
operation is different from sleeping and assuming an operation has finished.

Prefer injected time, explicit events, and operation counts to wall-clock speed
assertions. Render animations at chosen timestamps. Keep optional latency benchmarks
separate from correctness requirements, and report environment-sensitive timings
as measurements rather than universal pass/fail limits.

## Review and verification

For code changes, run focused tests while editing, then the complete `make check`. Investigate failures
instead of retrying until green or broadening tolerances without evidence. Check
test discovery and explicit skips in the output. A zero-test filtered run is not
validation. Run additional isolation/order checks when shared fixtures change.

The current suite does not certify physical gesture feel or all third-party app
behavior. Record manual checks separately from automated results.

After installing a build, `script/smoke.sh` checks the running app with real windows
in whichever mode it runs, read from `doctor`. Using only its own TextEdit window, it
checks adoption, put-back after the app moves the window, the three-try limit against
an app that keeps moving it, `retile`, moves between workspaces and displays and back
(in virtual mode, that a window on a hidden workspace is out of sight and shown again),
focus following, switching another display's workspace, return of focus, survival of
the app quitting and new crash reports; native mode adds its permissions and pan lag.
It prints PASS, FAIL or SKIP per check and exits with the failure count. It skips the
window checks when TextEdit is already open, and does not cover gestures, the
sidebar's own click path or quitting WinMuxX. Changes confined
to tests and CI do not require rebuilding or restarting the installed app.

References: Apple's [test setup and teardown](https://developer.apple.com/documentation/xctest/set-up-and-tear-down-state-in-your-tests)
and [asynchronous tests and expectations](https://developer.apple.com/documentation/xctest/asynchronous-tests-and-expectations).

## Swipe controller regression boundary

`WorkspaceSwipeController` accepts internal `WorkspaceSwipeDependencies`; its live
factory connects native services. Controller tests inject a preview spy, monitor
lookup, pointer, eligibility and direction, and a controlled navigation session.
They feed real recognizer frames and use the actual workspace selection policy.
They do not start the raw input backend, capture the desktop, or require permissions.

Use `WorkspaceNavigationFixture` for the controller and monitor-navigation tests.
Pair construction in setup with `cleanUp()` in teardown. Reset controllers and
release navigation gates before destroying the fixture. Session gates deliberately
allow cancelled native work to return, so stale success and error paths are tested.
All waits have bounded XCTest expectations; no timing sleeps are used.

## Workspace overview regression boundary

`WorkspaceOverviewDependencies` injects model snapshots, display/project context,
ordering/capture, panel creation and navigation. Controller tests exercise real
queue/lifetime logic with synthetic images and cancellation-ignoring captures.
`WorkspaceOverviewModelTest` uses `WorkspaceNavigationFixture` to check inactive
workspace geometry and ownership without native AX traffic. Gesture integration
tests inject action callbacks into the shared axis router and cover independent
feature flags. Synthetic view rendering and native panel allocation/teardown are
separate from real desktop and physical trackpad validation. See
[overview documentation](WORKSPACE_OVERVIEW.md) for the resource budgets.

## Validation history

Build-by-build results, test counts and native checks up to build 100 are in the
[validation log](archive/VALIDATION_LOG.md). They record what was true for those
builds; the sections above and below describe how to test today.

## Runtime and UI reliability checks (2026-10-20)

Run `make check` for the Swift suite, Python tooling checks and pinned dependency
resolution. The reliability changes passed 1,271 Swift tests and 47 Python checks.
Native palette fixtures are written to `.build/native-overlay-fixtures/`; CI
uploads these with `.build/test-output.log`. Pixel assertions use the same AppKit
color-profile pipeline for actual and reference images. Resolver tests cover
wallpaper/system fallback, explicit tint, custom color and accessibility policy;
native container tests cover surface ownership and appearance. These tests do
not certify live blur, animation smoothness or multi-display appearance.

The focused lifecycle scenario is:

```sh
swift test --filter RuntimePerformanceScenarioTest
```

It performs 20 warm-up and 100 measured cycles of palette/sidebar cleanup and
workspace navigation, asserting balanced monitors and cleared deferred work.
Overview tests separately exercise capture bounds, late callbacks and 1,000
presentation sessions. No desktop applications are moved by these fixtures.

For process measurements, record build, OS, display arrangement, config hash and
scenario alongside the output. After a 30-second warm-up, sample the app for
120 seconds using `script/profile_runtime.py --help`. Keep the workload and
hardware comparable; run idle sampling without UI automation. Compare summaries:

```sh
python3 script/compare_runtime_profiles.py \
  --baseline baseline/summary.json --candidate candidate/summary.json \
  --output comparison.json \
  --baseline-environment baseline/environment.json \
  --candidate-environment candidate/environment.json
```

A candidate above the CPU baseline by max(0.5 percentage points, 25%), above
wakeups by max(1/second, 25%), or growing by max(5 MiB, 5% of initial footprint)
requests repeats. Pass three `--candidate` arguments to use their medians before
calling it a confirmed regression. Incomplete or interrupted samples cannot pass.
Environment files contain `os`, `monitors` and `config_sha256`; missing fields
or a mismatch make the comparison inconclusive. Omit both environment arguments
only for summaries whose environment was verified separately. Counters describe
this process, not battery life or WindowServer energy.

Manual acceptance still includes light/dark glass, Reduce Transparency, increased
contrast, both sidebar edges, multiple displays, IME, outside-click delivery and
rapid close/reopen. Record unavailable hardware or unperformed cases explicitly.
