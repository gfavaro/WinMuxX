# Engineering governance

## Plain English overview

The Product Manager owns user experience, priorities, acceptance and product trade-offs. The Product Manager approves significant architecture changes. The implementing agent investigates, proposes, implements, tests, updates documents and reports evidence. A reviewing agent independently checks compliance, evidence, regression risk and unnecessary complexity. For significant changes, a different reviewer is preferred when available. Trivial changes do not require multiple agents. Repository documents are authoritative across tools; external memory can supplement them.

## Architectural rules

For nontrivial work an agent MUST:

1. Read AGENTS.md and the relevant architecture and product guides.
2. Trace the real implementation.
3. Identify the affected contracts.
4. Explain the approach.
5. Explain potential regressions.
6. Implement the smallest reasonable solution.
7. Run relevant verification.
8. Update affected architecture documents. Search `docs/architecture/` for the changed type, function and file names, and link new tests from the claims they settle.
9. Report results.

Agents make ordinary decisions autonomously within existing contracts.

An agent MUST NOT silently change core domain ownership, workspace or window identity, layout contracts, persistence schemas, major event processing, public architectural interfaces or fundamental dependency direction. If needed, before implementation explain the problem in plain English, simplest viable solution and alternatives, trade-offs, migration and compatibility; prepare a proposed ADR and request Product Manager approval. Approval applies to the concrete decision. It does not apply to every implementation detail. Do not mark a proposal accepted without explicit approval. Existing product rules in [principles](../PRINCIPLES.md) continue to apply.

A substantial completion report MUST cover what changed, why, architectural impact, verification actually run and its results, risks, documentation updated, and commit IDs (or state that none were made). Separate automated checks, builds, installation and real desktop validation. Never claim a test passed when it did not run.

## Technical reference

[AGENTS.md](../../AGENTS.md) is the agent entry point; [CONTRIBUTING](../../CONTRIBUTING.md), [Testing](../TESTING.md), [invariants](INVARIANTS.md) and [decisions](DECISIONS/README.md) provide operational detail. An ADR is a repository file, not hidden agent memory. For the existing docs-only validation workflow use the contributor guidance checker and `git diff --check`.

## Failure modes

A review that only repeats implementation claims can miss errors. An outdated ADR or an acceptance that did not occur can mislead later agents. Review independently where feasible and cite concrete source and test evidence; record unverified assumptions.

## Open questions

Unknown: availability of a genuinely independent reviewer in every environment. Lack of one is reported, not disguised as independent review; it does not require extra agents for trivial work.
