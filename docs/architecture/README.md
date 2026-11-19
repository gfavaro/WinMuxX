# Architecture baseline

This is the repository's entry point for the current architecture and future engineering decisions. It describes the checkout inspected on 2026-11-19; some Scrolling files and the user-facing layouts guide had pre-existing uncommitted changes during inspection. Claims about those files describe that working tree and must be rechecked against the revision being changed. This documentation does not certify native behavior.

**Evidence labels:** Observed means present in inspected source; Inferred means a reasonable consequence that needs verification; Proposed means a recommendation, not existing policy or approval; Unknown means evidence is missing. An observed implementation is not a guarantee under every macOS condition. Rules marked **existing** refer to code or existing project instructions; **proposed** rules describe desired future behavior, not evidence that it is enforced. Governance is an instruction once adopted in AGENTS.md.

Read [overview](OVERVIEW.md), [domain](DOMAIN.md), [components](COMPONENTS.md), [layouts](LAYOUTS.md), [events](EVENTS.md), [state and recovery](STATE.md), [invariants](INVARIANTS.md), [performance](PERFORMANCE.md), [governance](GOVERNANCE.md), [audit and backlog](AUDIT.md), and the [Product Manager review](PM_REVIEW.md). Historical decisions are in [DECISIONS](DECISIONS/README.md). For product rules and commands use [core principles](../PRINCIPLES.md), [workspace behavior](../WORKSPACE_BEHAVIOR.md), and [layout guide](../LAYOUTS.md); these remain authoritative for their respective scopes. If source and documentation disagree, investigate and update the documentation rather than assuming either proves intended behavior.

## Architectural rules

Existing: agents MUST preserve project instructions and distinguish tests from native validation. Proposed: agents SHOULD maintain source references and explicit uncertainty; they MAY link existing guides instead of duplicating them.

## Technical reference

The map starts at `Sources/AppBundle/runtime/WinMuxRuntime.swift`; source links in the individual documents lead to concrete owners. Tests are examples of coverage, not blanket proofs.

## Failure modes and open questions

A stale baseline can misdirect future changes; review affected documents alongside code. Source links are checkable but do not prove behavioral assertions. Unknown: full native behavior varies with applications, permissions and macOS versions.
