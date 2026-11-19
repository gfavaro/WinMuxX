# Independent architecture and documentation review

Reviewed revision: `74aa3ba4` (2026-11-19), with a clean `Sources/` tree and `docs/architecture/` tree. This review replaces the earlier review recorded in `fabe304d`. That review's findings are rechecked below. No production code, architecture page or `AGENTS.md` was changed, and no commit was made.

Method: every architecture page and ADR was read in full. Claims about ownership, gestures, persistence, the invariant checker and display viewports were traced to Swift source. Every relative link under `docs/architecture/` was resolved. Git history for the architecture directory and for the sidebar and Scrolling gesture code was compared with the documents. No tests were run, and nothing was validated on a real desktop.

## Executive Assessment

The baseline describes WinMuxX accurately in its central claims, and it is careful about evidence. The core model is verified: virtual workspaces grouped into projects, a display viewport that selects one active workspace, four arrangements (`dwindle`, `master`, `tabbed`, `scrolling`) over one shared tree, a separate restart snapshot and original-frame journal, and conservative restart matching. The documents label observed, inferred, proposed and unknown claims, and they rarely overstate them.

The baseline can guide future agents. It has one confirmed factual error: the sidebar corner surface described in `COMPONENTS.md` no longer exists. It also lags behind code that changed on the same day it was written. The cause is a process gap, not a design gap. Nothing makes an agent update the architecture pages when the code they describe changes, and the most recent sidebar work (by this reviewer's own sessions) did not update them.

## Verified Strengths

1. **Selection and explicit moves are separate, and the docs say so correctly.** `setActiveWorkspace` records the previous workspace and the preferred display point without moving ownership ([registry](../../Sources/AppBundle/tree/WinMuxWorkspaceState.swift#L137)). Explicit moves and forced assignment live in [`WorkspaceMonitorAssignment`](../../Sources/AppBundle/tree/WorkspaceMonitorAssignment.swift). `OVERVIEW.md` now states the forced-assignment exception next to the rule.
2. **Evidence discipline.** Every page separates Observed, Inferred, Proposed and Unknown. Tests are described as examples, not proof. Native behavior is never claimed as certified. AUD-001 is a good example: `FrozenWorkspace` saves `scrollingOffset` only when the arrangement is Scrolling ([source](../../Sources/AppBundle/tree/frozen/closedWindowsCache.swift#L72)). The docs record this exactly and route it to the Product Manager as a question, not a bug.
3. **Proportional governance.** `AGENTS.md` and `GOVERNANCE.md` list the change classes that need approval: domain ownership, identity, layout contracts, persistence schemas, major event processing, public interfaces and dependency direction. Ordinary choices are left to the agent. An independent reviewer is preferred but not required for trivial work. The rules name no specific agent platform. The contributor checker now covers `docs/architecture/` ([checker](../../script/check_contributor_guidance.py#L26)), so broken links fail `make check`. That closes the earlier finding IR-006.

The earlier review's IR-001 (gesture guards) and IR-002 (three recovery paths) were also addressed. `EVENTS.md` now has a "Horizontal Scrolling gesture lifetime" section that matches the receiver's guards: a weak workspace reference, `isVisible` and arrangement checks, no epoch comparison, and epoch checks only in the minimap ([receiver](../../Sources/AppBundle/mouse/ScrollingDockSwipe.swift#L54), [minimap](../../Sources/AppBundle/ui/WorkspaceScrollingMinimap.swift#L128)). `STATE.md` now has "Three recovery paths".

## Architectural Findings

No P0 or P1 finding was established.

| ID · severity | Finding and evidence | Impact | Correction | Confidence |
| --- | --- | --- | --- | --- |
| IR2-001 · P2 | **Verified error: the sidebar corner surface in `COMPONENTS.md` was removed.** The page says an opaque full-height sidebar on macOS 27 "owns a separate click-through surface with fixed inward curves" that "do not track windows". That surface (`cornerBacking`, added in `e83a9486`) no longer exists: `grep cornerBacking Sources` finds nothing. Commits `0a671b6d` through `74aa3ba4` replaced it with an edge layer inside the sidebar panel. That layer is shaped by `workspaceSidebarWindowEdge(on:)` from the outer gap, the window border width and the system window corner radius. It is drawn only when the rail is at rest, full height and flat. | An agent changing the sidebar would look for a panel that does not exist and reason about the wrong layering. The stated limitation ("curves do not track windows") is now wrong in the other direction. | Rewrite the paragraph to describe the in-panel edge layer, its conditions (not centered, at resting width, solid or Reduce Transparency colors only), and the extra click-through backing width. | High |
| IR2-002 · P2 | **Process gap: architecture pages are not updated with the code.** The governance rule says "update affected architecture documents". Two same-day changes show it is not followed reliably. (1) The sidebar commits above changed `COMPONENTS.md`'s subject without touching it. (2) `c93772ec` added `ScrollingReceiverLifecycleTest`, including `testReceiverAcceptsCallbackAfterDisplayOwnershipChanges`. `EVENTS.md` still says "whether a delayed callback reaches this receiver … is not established", `AUDIT.md` lists that case as a gap, and INV-009 lists it as a missing test. None of them link the new test. | The baseline goes stale silently. The checker validates links, not meaning. | Keep the rule, and make it cheap to follow. In `GOVERNANCE.md`, add one line asking agents to search `docs/architecture/` for the type or file names they changed. Link the new receiver tests from `EVENTS.md`, `AUDIT.md` and INV-009, and record that a callback after a display-ownership change is *accepted* (now pinned behavior, not unknown). | High |
| IR2-003 · P2 | **"Partially enforced" overstates two invariants.** INV-001 and INV-003 cite `ModelInvariantChecker` as enforcement. The checker is reachable in production only through the `debug-windows` command ([caller](../../Sources/AppBundle/command/impl/DebugWindowsCommand.swift#L38)) and in tests. For INV-003, `setActiveWorkspace` does not reject a workspace that is active on another viewport. A separate `isWorkspaceActive(_:outside:)` query exists for callers, and the guard is in caller policy, not in the registry that the table names as owner. `INVARIANTS.md`'s own rule says not to claim enforcement from a read-only diagnostic. | An agent could add a new caller of `setActiveWorkspace` and assume the registry prevents duplicates. | Name the owner as "assignment policy (callers of `setActiveWorkspace`)" and the checker as "detection". Keep "Partially enforced" only where a test asserts the guard. | Medium (caller guards were not traced exhaustively) |
| IR2-004 · P2 | **Normative words under a "Proposed" label still read as requirements.** Examples: `OVERVIEW.md` "Proposed: … MUST NOT represent failed AX writes as applied"; `LAYOUTS.md` "Proposed: switching arrangements MUST preserve membership…"; `STATE.md` "Proposed: … native failures MUST NOT be described as successfully applied". This was IR-005 in the earlier review and is unchanged. | A future agent may treat an unapproved target as a contract, or block legitimate work on one. | Use SHOULD for proposed rules, or move them under a "Proposed contracts" heading. Reserve MUST for existing project rules. | High |
| IR2-005 · P3 | **Stale snapshot caveat.** `README.md` says some Scrolling files "had pre-existing uncommitted changes during that inspection". The working tree no longer has them. | Low. It invites unnecessary rechecking. | Replace with the revision the baseline describes, and update it when pages are refreshed. | High |
| IR2-006 · P3 | **Review documents accumulate.** `AUDIT.md`, `PM_REVIEW.md` and this file are point-in-time reviews kept beside living reference pages. The README tells agents to read all of them. | Reading cost grows, and old findings can be read as current. | Mark review pages as dated records in the README reading order. Keep only the backlog and open PM question live. | Medium |

Risks that were checked but **not** raised as defects:
- The horizontal receiver accepts callbacks for its workspace after a display-ownership change. This is now pinned by a test, so it is intended or at least known behavior. Whether it surprises users is a product question.
- The Scrolling offset is not persisted when another arrangement is active. This is documented and already routed to the PM (AUD-001).
- The `Runtime` has a broad composition role. The docs describe it honestly, and nothing showed that it causes harm.

## Documentation Quality

The writing is mostly good pragmatic controlled English. Sentences in the overviews are short, mostly active, and limited to one idea each. The glossary fixes the terms "display", "display viewport", "Scrolling viewport" and "arrangement" versus container "layout". Those terms are used consistently. `PM_REVIEW.md` is readable by someone who does not read Swift.

Weaknesses:
- Technical tables (`EVENTS.md`, `STATE.md`, `COMPONENTS.md`) pack the owner, trigger, side effect and evidence into single cells, using semicolon chains such as "AX callback resolves IDs, dispatches to main actor; destruction can retire…". These are the hardest parts for a PM.
- Hedging is sometimes heavier than the evidence needs. Most pages end with several "Unknown" statements that do not change any decision. The repeated text weakens the important unknowns.
- The "viewport" glossary row opens with "a context that selects or shows part of something", which adds nothing before the two precise definitions.
- AX and ADR are used before they are expanded on several pages.

The editorial pass (`a41d9823`, then `93993c8d` and `73971eda`) did not change architectural meaning in the passages compared. Invariant rows, evidence labels and the approval list are intact. Gesture and recovery detail grew; it did not shrink. No requirement was strengthened. The one weakness the editing preserved, not introduced, is IR2-004.

## Governance Assessment

An agent can find the right document from `AGENTS.md` → `OVERVIEW.md`/`GOVERNANCE.md` → topic page → source link, and it can tell which changes need Product Manager approval. The rules contain no platform-specific requirement. The long ai-memory block in `AGENTS.md` names harnesses, but it is about memory routing, not architecture. Approval scope ("applies to the concrete decision") is sensible, and the ADR template is light.

The weak points are maintenance, not authority:
- No trigger connects a code change to the page that describes it (IR2-002).
- Invariants are identified, but few are tied to a named test. INV-005, -006 and -008 to -011 are Proposed with "missing:" tests.
- The guidance checker validates links and source paths only. It cannot detect the stale claims found here.

None of this calls for more process. One search step and linking tests from invariant rows would cover most of it.

## Recommended Improvements

1. Fix `COMPONENTS.md`'s sidebar paragraph (IR2-001). This is a five-minute correction to the only verified factual error.
2. Link `ScrollingReceiverLifecycleTest` from `EVENTS.md`, `AUDIT.md` and INV-009, and change "not established" to the pinned behavior (IR2-002).
3. Add one sentence to `GOVERNANCE.md`: after changing code, search `docs/architecture/` for the changed type and file names (IR2-002).
4. Replace MUST with SHOULD under "Proposed" (IR2-004), and correct the owner and enforcement wording on INV-001 and INV-003 (IR2-003).
5. Mark `AUDIT.md`, `PM_REVIEW.md` and this review as dated records, and refresh the README's snapshot line (IR2-005, IR2-006).

## Product Manager Decision Brief

1. **Can I trust this architecture documentation?** Yes, for the overall design and for knowing when your approval is needed. One paragraph about the sidebar is wrong, and a few gesture and test notes are a day out of date. Check the linked code before relying on a page for an area changed in the last few commits.
2. **What are the most important risks?** First, the documents going stale without anyone noticing, as has already happened twice. Second, an agent treating a proposed rule as an approved one. Third, an agent trusting a duplicate-workspace guard in the wrong place.
3. **What should we correct first?** The sidebar paragraph, then the gesture test links, then the one-line "search the architecture docs after you change code" rule.
4. **Which changes require my approval?** None of the corrections above. They are factual documentation edits. Your one open decision is unchanged: should a workspace remember its Scrolling position across a restart when it was using another arrangement at shutdown? A related, optional question: should a horizontal swipe that started before a workspace moved to another display still act on that workspace? A test now pins "yes".
5. **What should we leave alone?** Selection versus explicit move, conservative restart matching, the separate restart and recovery stores, and per-arrangement state over one shared tree. These are sound. Don't add layout interfaces or new layers for symmetry.

## Final Verdict

**PASS WITH WARNINGS.** The central architecture is accurately documented and verified in source, the evidence labeling is honest, and the approval boundaries are clear and proportional. The warnings are one verified factual error (IR2-001), documentation that lags same-day code and test changes (IR2-002), and soft spots in invariant and normative wording (IR2-003, IR2-004). All of them can be fixed with small documentation edits, and none requires an architectural change or a Product Manager decision.
