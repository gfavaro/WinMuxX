# Performance architecture

## Plain English overview

Observed: WinMuxX runs continuously. Unnecessary wakeups, repeated layout passes and blocking on an unresponsive application affect responsiveness. The implementation combines some refresh requests and delays saves to reduce repeated work. It bounds some retries and instrumentation. It also caches display and workspace views. No benchmark in this baseline establishes a universal overhead target.

## Architectural rules

Existing project guidance: prefer native events and bounded, coalesced work. Proposed: changes SHOULD measure the affected workload, bound observer/task lifetimes, avoid unnecessary AX round trips and retain cancellation; MAY add targeted benchmarks when justified.

## Technical reference

`RefreshCoordinator` and [refresh](../../Sources/AppBundle/layout/refresh.swift) coalesce and drop selected geometry events. [FrameRecovery](../../Sources/AppBundle/runtime/FrameRecovery.swift) delays and caps repeated reapplication. [snapshot writer](../../Sources/AppBundle/tree/frozen/persistedFrozenWorld.swift) waits before saving, limits identity refresh and avoids writing identical envelopes. [GlobalObserver](../../Sources/AppBundle/GlobalObserver.swift) handles high-frequency pointer events without a task hop when already on the main thread. AX budgets/retry backoff are described in [reliability](../RELIABILITY.md). [RuntimeWorkMetrics](../../Sources/AppBundle/runtime/RuntimeWorkMetrics.swift) is bounded and opt-in; instrumentation does not cover all AX calls. Per-app AX threads reduce some blocking, while main-actor orchestration and synchronous work still need measurement. Gestures and frequent display changes can cause frequent layouts. Observer leaks and unbounded queued work are risks to check, not demonstrated leaks.

Use the existing procedure in [Testing](../TESTING.md): comparable machine, OS, displays, config and workload, warm-up, process sample, comparison and repeat criteria. Include idle, repeated workspace/layout change, rapid gestures and an unresponsive app when relevant. Track CPU, wakeups, memory, refresh count and partial AX metrics. Record scenario and baseline; do not infer battery life or WindowServer cost from app-process counters. `RuntimePerformanceScenarioTest` checks bounded lifecycle behavior, not actual desktop performance.

## Failure modes

An event storm can cause excessive CPU or geometry churn, an AX timeout can stall a refresh step, and retained observers/tasks can grow memory. Existing mitigations apply to specific paths. This document does not assert a measured regression.

## Open questions

Unknown: current measured baseline and bounds for gesture-heavy, many-window and multi-display workloads; no new measurements were taken for this documentation task.
