# ADR-002: Conservative restart identity

- Status: Observed
- Date: 2026-11-19 (recorded; not the original decision date)

## Context
Native window IDs and titles can change or be reused across application launches.

## Decision
Trust an ID only with matching process launch evidence. Otherwise, score available metadata and require uniqueness. A constrained fallback handles a single relaunched window.

## Why this approach
Avoid attaching saved organization to the wrong window when evidence is ambiguous. History `188df4a4` explains the sole-window case and app termination handling.

## Alternatives considered
A forced match by ordering or title alone is a conceivable alternative; the full historical alternatives are unknown.

## Consequences
Some windows are left unmatched rather than incorrectly restored. Document and accessibility identifiers improve evidence when available.

## Risks
Missing or generic metadata and late window creation can prevent correct recovery. Sole-window matching remains an inference about identity.

## Source references
[Matcher](../../../Sources/AppBundle/tree/frozen/RestartWindowIdentity.swift), [restart test](../../../Sources/AppBundleTests/tree/RestartWorkspaceTest.swift).
