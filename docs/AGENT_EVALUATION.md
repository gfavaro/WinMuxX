# Reusable agent evaluation

Use this to evaluate a model or substantial guidance change, not as a routine
contribution gate. Record the model, reasoning setting, checkout commit and guidance
version, including uncommitted instructions. A successful task does not establish
general model reliability.

When using an agent, pass an explicit isolated working directory and no parent chat
history. The candidate reads normal repository instructions but should not read this
evaluation document or prior trial answers. Supply only the selected candidate prompt
and the trial boundaries. Specify the model and reasoning setting explicitly rather
than assuming a label selected the intended model.

## Trial setup

Use a disposable checkout with its own build directory and the guidance under test.
Do not share writable build caches, install or launch the app, use real user config
as a fixture, commit, push or edit the original checkout. Retain patches and logs
for review; do not automatically merge trial changes.

From a checkout with committed guidance, a minimal setup is:

```sh
trial_dir=$(mktemp -d /tmp/winmuxx-agent-trial.XXXXXX)
git worktree add --detach "$trial_dir" HEAD
```

Run these sequentially and stop if either fails. If evaluating uncommitted guidance,
copy only the intended guide/script changes into the trial and record that input diff
before the candidate edits anything. Do not omit untracked skills or copy live user
configuration. Build and test from the trial directory with its own `.build` and
`.deps`. Keep the checkout until the patch and logs are reviewed; removing it early
can discard evidence. Subsequent trials use a fresh session and reset task inputs.

Give the candidate the task and ordinary repository guidance. Keep evaluator criteria
out of the initial prompt so the answer must come from investigation. These prompts
work in a separate model session; subagents are optional when available and authorized.

## Candidate task A: investigate

> Read AGENTS.md and use the relevant guidance. Investigate adding Bring Workspace
> Here to the sidebar. Do not edit files. Report whether equivalent behavior exists,
> its exact code path, the smallest appropriate plan, relevant tests and desktop
> validation. Distinguish selection from movement. Do not assume the feature is missing.

## Candidate task B: implement

> In this isolated checkout, add meaningful regression coverage for moving a populated
> workspace to another display and back. Check identity, project, nested tiles/tabs,
> floating windows, source/destination ownership and an unaffected third display.
> Inspect existing coverage first. Keep production behavior unchanged, run relevant
> checks and report exact results/blockers. Do not install or launch the app, commit or push.

If equivalent coverage exists, request an uncovered case rather than a duplicate.
For a harder trial, authorize a temporary production mutation that corrupts layout
while movement still occurs. Require failure at the relevant new assertion,
restoration and a final passing run. Mutation testing is optional, not a routine
cost for every small change.

## Evaluator criteria

| Dimension | Evidence |
| --- | --- |
| Understanding | Finds existing Bring Here; separates current no-swap behavior from a requested swap; identifies assignment/fallback rules |
| Scope | Reuses owners and fixtures; does not alter production to satisfy a mistaken preservation test |
| Tests | Checks live tree reachability and both displays; relevant mutation fails the intended assertion |
| Execution | Compiles, executes nonzero selected tests serially, preserves exit codes and handles documented setup |
| Honesty | Separates full-suite, focused and desktop checks; reports errors/skips |
| Independence | Distinguishes correct first pass, self-correction and corrections prompted by review |

For a fresh follow-up to task B, test assignment rejection instead of repeating the
same round-trip case: a rejected move should preserve the populated workspace's
organization, project and all three displays. This avoids grading recall of the
previous patch. Add further trials only for a specific unresolved capability;
repeated full-suite runs without new changes or failures are unnecessary.

Review the patch and independently rerun the focused test. Verify production
mutations are gone. Passing movement assertions does not prove layout retention.
Record reviewer hints, commands/counts/exit status, remaining limitations and
guidance changes. Do not assign universal numeric capability scores from a few tasks.

## Initial trial: 2026-10-23

`gpt-6-luna`, medium reasoning, used base `19e894c5` with the new contributor guidance
copied into an isolated checkout. Task A found the existing action. Task B produced
a real test, but initially expected swapping and used an invalid Swift identity
comparison against the Monitor protocol. It corrected those after compiler/test
feedback. Review prompted stronger live-tree and source/displaced-owner assertions.

The revised test caught temporary tab-layout corruption. After restoration the
focused test passed, including an independent rerun. Logs showed 1,368 Swift tests
and Python/schema stages passing. Initial setup lacked the schema virtualenv;
installing pinned dependencies resolved that. A reporting wrapper later used zsh's
read-only `status` variable and failed after the check command returned; its exit
was not evidence of a clean full run. No desktop validation occurred. The test patch
remained in the disposable checkout.

This supports bounded tasks with executable checks and review, not an unattended
backend migration. Behavior examples, setup and live-state assertion guidance were
strengthened afterward.

## Fresh follow-up: 2026-10-24

A fresh `gpt-6-luna` session at medium reasoning used base `19e894c5` with revised
guidance, no parent chat history and no access to this evaluation's answers. The
task was rejection of a forced-assignment move while preserving populated workspace
organization and all three displays. It produced a test without production edits.
Its report recorded 28 focused navigation tests and 1,368 full Swift tests passing,
plus the Python/schema/dependency checks. It initially missed the schema environment
setup again, then used the documented pinned requirements and reran successfully.

The patch used live-root and membership assertions without prompting, but omitted
the tab layout mode. Review requested that correction; the model then hit its usage
limit, so the reviewer completed this part. The reviewer temporarily changed a tab
container to tiles before assignment rejection: the original test still passed.
After adding explicit tab and nested layout assertions, the same mutation failed
at the tab-mode assertion. Restoring production made the focused test pass. This
was reviewer-assisted validation, not an independently completed Luna retry.

The resulting guidance explicitly distinguishes membership from layout mode. The
full check now fails early with setup instructions when the schema environment is
missing, and validates schema before compiling/testing Swift. The main checkout's
`make check` passed with 1,367 Swift tests plus Python/schema checks and the new
guidance checker tests; trial tests remain isolated. No app was installed or native
desktop validation performed. Latest wording changes were locally validated but
have not received another model trial; further trials are not justified merely to
obtain an unqualified success label.

Practical conclusion: the guidance improved some first-pass behavior, but review
still found an omitted acceptance condition. Use small tasks, observable acceptance
criteria and checks; do not promise that instructions eliminate model mistakes.
