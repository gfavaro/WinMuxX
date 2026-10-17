# Runtime efficiency

The runtime manages native application windows through Accessibility and private
WindowServer APIs. Model benchmarks exclude some cross-process and compositor costs.

## Persistence and recovery

Routine restart saves capture immutable model state on MainActor. A utility serial
worker encodes JSON and updates the primary/backup files. It holds one active write
and one replaceable pending snapshot, and skips snapshots equal to the last saved
state. Explicit final saves drain the worker synchronously before returning.

Application termination records one window assignment per departing window. Each
assignment contains one frozen leaf, rather than another full workspace tree.
Complete startup trees remain available during the 30-second late restoration
period. Consumed snapshots are compacted after that period or after a layout edit,
once any in-flight restoration readers have finished.

Crash-recovery originals are staged during discovery and flushed as one journal
batch before the first corresponding frame mutation. Recording a batch still
completes synchronously before native writes. Removal of closed-window entries can
coalesce for 50 ms; a subsequent record or clean quit flushes that pending update.

## Native events and input

Mission Control notifications share one pending 16 ms reconciliation. Border IDs
are checked through a set, owning applications are resolved once per scan, and a
required border reconciliation reuses the same native window snapshot. Managed
geometry updates retain the individual-window fast path. No reconciliation clock
runs when there are no events.

Run-loop cancellation reads and writes use the same lock. Fresh AX window elements
receive their timeout before ID resolution, and ID/attribute reads honor the
session budget and job cancellation. The per-app 1.5-second refresh deadline is
cooperative: an already-started native call must finish or time out before its AX
thread can acknowledge cancellation.

Layout reuse compares whole-point native targets, so fractional weight rounding
does not cause repeated identical AX writes. The six-window, ten-layout hotkey
benchmark now requires six writes instead of accepting sixty. Geometry events
still retain their explicit reassertion behavior.

Pointer focus uses cached geometry on the display under the pointer. Unchanged
pointer/scroll events keep the existing dwell task. After dwell, a worker checks
the frontmost native surface so floating or unmanaged windows are not ignored.

## Queries, subscriptions and captures

Read-only CLI list/config/agent-query commands read the established managed model
without triggering layout, UI reconciliation or restart persistence. Requested
native metadata, such as a window title, can still require an AX query. These
queries do not cancel pending native refreshes.

Each subscription has one ordered sender, with limits of 64 buffered events and
1 MiB, including the in-flight event. A client exceeding either limit disconnects;
other clients continue independently. Initial events use the same sender.

Double-sided window captures run on an actor. Only one capture can remain active,
including after cancellation. Preparation falls back to navigation after 80 ms,
and cancelled/late images cannot present an animation. Each retained image is
limited to 2 million pixels and a 2048-pixel longest edge. Native capture can still
temporarily allocate a full-resolution source image before reduction.

## Verification

The local check passed 1,131 Swift tests and 20 Python tests. Two focused Thread
Sanitizer tests passed for concurrent cancellation and persistence-worker
coalescing/final-save ordering, with no race reports. The strengthened six-window,
ten-layout hotkey benchmark records six frame writes; the geometry-event scenario
continues to record sixty explicit reassertions.

Regression tests cover 500 terminated-window assignments, recovery-reader lifetime,
unchanged-file suppression, worker coalescing and final-save ordering, cancellation,
throwing-session recovery, query isolation, journal batching, native event bursts,
slow subscribers, pointer targeting, capture deadlines and image resolution.

## Native release measurements

Build 82 was signed with the existing local identity and installed over build 81.
Strict/deep verification passed. Configuration bytes, window/workspace assignments,
populated workspace display/visibility state and restored focus matched across
installation. Doctor reported valid configuration, granted Accessibility/Screen
Capture and a listening raw-touch backend. Only the built-in display was connected.

An uninstrumented run of 100 serial `list-windows --all --count` processes measured:

| Metric | Build 81 | Build 82 |
| --- | ---: | ---: |
| CLI p50, including process launch | 41.72 ms | 20.79 ms |
| CLI p95, including process launch | 78.42 ms | 21.58 ms |
| Total elapsed | 4.81 s | 2.09 s |
| WinMux CPU time over all 100 queries | 73.84 ms | 5.31 ms |
| WinMux logical bytes written | 720,896 | 0 |
| WinMux disk bytes written | 557,056 | 0 |

These are single runs on an active desktop, not a controlled latency benchmark.
Counters came from `proc_pid_rusage`; they exclude CLI and WindowServer CPU. The
uninstrumented build-82 run is separate from the run that overlapped Time Profiler.
After queries, a 15-second settling sample wrote zero bytes and its footprint fell
by 0.14 MiB. Both builds were essentially idle when settled: the quiet tail of
build 81 measured 0.00029% of one CPU core; build 82's post-query sample measured
0.00022%. There is no evidence here of a material idle CPU reduction.

Build 82's fresh-process footprint was about 70.6 MiB after the workload versus
81.2 MiB in the longer-lived build 81. Different process lifetimes prevent treating
that difference as a measured memory-growth improvement. Sampling and Time Profiler
captures were collected; the observed desktop workloads were not matched closely
enough for an overall CPU speedup claim.

The live leak scan identified native TOML allocations. The pinned wrapper had no
native-root destruction or temporary-buffer cleanup. The local vendored ownership
patch is covered by seven additional regressions. An isolated optimized fixture
that repeats 1,000 parse/read/format/encode/error cycles reports 173,000 leaks /
10,864,000 bytes with the original pinned sources and zero leaks with the patch.
The same optimized 1,000-cycle fixture passed Address Sanitizer with no reports.
This fixture does not access user configuration or native windows.

Signed build 83 includes the TOML patch and is installed. Its live leak scan no
longer reports native TOML allocations; it reports six allocations / 384 bytes
rooted in an AppKit `_NSDisplayLink` / SwiftUI `ViewGraphDisplayLink` chain.
Allocation stacks are unavailable in this signed process, so their origin remains
unconfirmed. The process is not certified leak-free.

The session locked during installation, so initial AX enumeration was empty.
After unlock, all five window/workspace assignments, populated display ownership,
focus and configuration bytes matched the pre-install snapshot. No corrective
window movement was required for this validation.

## Extended validation

The isolated optimized TOML fixture completed 100,000 parse/read/format/encode/error
cycles with zero detected leaks. The same 100,000 cycles passed Address Sanitizer.
A native offscreen preview regression performs 1,000 begin/update/cancel cycles
across 20 controller lifetimes. Every controller reuses one panel, clears pixels
and animations on cancellation, and releases its panel and controller after
invalidation. It neither captures the desktop nor injects gestures.

The installed build completed 1,000 serial count queries in ten batches, with ten
seconds between batches, over 127 seconds. Settled footprint ranged from 71.24 to
72.00 MiB; the last reading was 0.53 MiB above the first settled reading. Eight
consecutive middle batches recorded zero logical writes. The first and final
batches/settles recorded 638,976 bytes in total, so this mixed desktop run does not
establish zero background I/O. Other diagnostics and offscreen tests overlapped
parts of the run. It is not a controlled query latency or long-duration leak test.

A further 500 count queries succeeded: p50 21.17 ms, p95 21.63 ms, 196,608 logical
bytes written and a 0.17 MiB footprint increase. In a subsequent 30-second settled
observation, footprint stayed at 72.24 MiB, both logical and disk writes were zero,
and app CPU averaged 0.00047% of one core. These short observations distinguish
settled behavior from the mixed workload; they do not establish lifetime bounds.

Before/after unlocked-process leak scans reported the same six allocations / 432
bytes at identical addresses, consisting of three `NSMutableDictionary` roots and
their storage. The earlier locked-process display-link chain was absent. These
reports did not grow during the observed workload; their allocation origin remains
unconfirmed because stack logging was not enabled. The whole app is not certified
leak-free.

Build 83 was compiled before these changes were committed locally and embeds base
hash `5579eaf1`. Its runtime implementation includes the fixes documented here;
subsequent changes add tests, stress-fixture arguments and these measurements.

Interactive Mission Control, gesture and occlusion checks remain unverified:
computer-use access to the native apps was denied. Multi-monitor/hotplug tests and
long-running managed-window churn are still pending. `powermetrics` was unavailable
without superuser access; no watts, battery-life or full-system wakeup improvement
is claimed from these process counters or unit tests.
