# Runtime release validation

This checklist tracks evidence rather than assigning an artificial confidence
percentage. A passing model test does not establish physical desktop behavior.
The installed runtime is signed build 83; the follow-up changes are test and
measurement tooling, so they do not require another installed app build.

| Check | Current evidence | Status |
| --- | --- | --- |
| Automated regression suite | 1,133 Swift tests and 26 Python checks pass | Passed locally |
| Native TOML ownership | 100,000 optimized cycles, zero detected leaks; Address Sanitizer passes | Passed fixture |
| Preview lifetime | 1,000 offscreen cycles, 20 controller lifetimes; panels/controllers release | Passed fixture |
| Model lifecycle | 32 windows over 40 rounds: 5,120 fullscreen/minimize state transitions and 160 close/replacements, preserving unique live IDs | Passed fixture |
| Fixture memory isolation | Reset releases minimized/popup roots that previously survived between cases | Fixed and regression tested |
| Lock/unlock restoration | All five assignments, display ownership, focus and config match pre-install state after unlock | Passed on built-in display |
| Two-hour app observation | Finite sampler started 2026-10-17 18:12:51 UTC; writes progress and final status automatically | Running; not a completed result |
| Residual live leaks | Six allocations / 432 bytes stayed at identical addresses over the earlier query workload | Origin unresolved |
| Real managed-window churn, Mission Control, gestures and occlusion | Computer-use tool rejected WinMuxX and TextEdit access, including after explicit user authorization | Blocked by tool access |
| Physical display hotplug and sleep/wake | No external display available; no physical test completed | Pending |
| Matched full-system energy comparison | `powermetrics` requires administrator access; noninteractive sudo refused; WindowServer rusage returned EPERM | Unmeasured |

## Long observation

`script/profile_runtime.py` reads macOS `proc_pid_rusage` counters without AX,
window interaction, configuration changes or a sleep assertion. It checks process
identity so a reused PID cannot silently contaminate results. It writes raw
`samples.jsonl`, run metadata, and an atomically updated `summary.json` in a new
private directory. Completion and interruption are explicit. Sampling gaps are
reported; a sleeping or interrupted machine must not be described as continuously
observed.

```sh
python3 script/profile_runtime.py \
  --pid "$(pgrep -x WinMuxX)" \
  --seconds 7200 --interval 10 \
  --output ".local/validation/runtime-soak-$(date -u +%Y%m%dT%H%M%SZ)"
```

The current detached run is identified by `.local/validation/latest-runtime-soak.json`.
Its report directory is `.local/validation/runtime-soak-20261017T181251Z`.
The expected sampling finish is 2026-10-17 20:12:51 UTC, subject to scheduling and
system sleep. Read `status` and coverage before interpreting the final numbers.
The run stops with an interrupted report if the target exits or its PID is reused.

The first few minutes contained a footprint rise from approximately 73 to 94 MiB
and real trackpad activity reported by the application's existing diagnostics.
Those observations neither establish a leak nor justify an idle-workload claim.
Review the complete series for continuing growth versus a bounded cache plateau,
and compare settled intervals separately from active use. CPU values are percent
of one core; process wakeup counters are not full-system wakeups. No watts or
battery-life conclusion follows from this sampler.

## Remaining leak attribution

Small independent optimized probes of Foundation bundle access, NSWorkspace app
enumeration and NSApplication/NSScreen initialization each reported zero leaks
with allocation stack logging. They created no windows and did not reproduce the
live application's dictionary allocations. Therefore the remaining report cannot
be dismissed as a demonstrated framework-only issue. Attributing it still requires
a controlled native reproduction with allocation stacks or equivalent evidence.

## Completion criteria

Before treating this as a high-confidence release, complete real window lifecycle,
rapid Mission Control/gesture interruption, occlusion, physical display and
sleep/wake checks; inspect the finished long observation; resolve unexplained
growth or new leak reports; and collect matched app/WindowServer energy traces.
Keep the same workload, display setup and system conditions for before/after
comparisons. Do not substitute passing synthetic tests for these checks.
