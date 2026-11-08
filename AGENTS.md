# Working in WinMuxX

Read [core principles](docs/PRINCIPLES.md) and [CONTRIBUTING](CONTRIBUTING.md) before
substantive changes. [HACKING](HACKING.md) owns architecture and development details;
[Testing](docs/TESTING.md) owns verification requirements. No external memory service
or personal skill installation is required to contribute.

Always build code cleanly and modularly, with proper architecture and separation of
concerns. Never bolt a feature on just because it was asked for. If there is no easy
way to build it naturally, and a refactor would make the whole thing clean, stop
before writing the feature and say so, recommending the refactor.

Before editing, inspect `git status --short` and preserve unrelated changes. Use
the user's requested outcome to choose scope; current docs describe the baseline,
not authority to override an explicit behavior change. If code and docs disagree,
trace the relevant test and report the mismatch before choosing new semantics.

Whole-workspace display movement is a defining capability. Ordinary workspace
selection preserves ownership; explicit movement changes it. Preserve projects,
workspace identity, nested layouts and tabs when changing the implementation.

For workspace lifecycle, display assignment, selection, summon or whole-workspace
movement, read [.agents/skills/winmuxx-workspaces/SKILL.md](.agents/skills/winmuxx-workspaces/SKILL.md).
For unrelated tasks, use the relevant subsystem guidance in HACKING.

For the product site (GitHub Pages), README pictures or promotional images, read
[marketing images](docs/MARKETING.md): render with `make marketing-images`, not
screen recordings.

Use the [task map](docs/CONTRIBUTOR_TASKS.md) for code owners, completion criteria
and failure handling. Read [workspace examples](docs/WORKSPACE_BEHAVIOR.md) when
selection or movement is affected. [Agent evaluation](docs/AGENT_EVALUATION.md)
is only for an explicitly requested model/guidance trial, not routine work.

WinMuxX uses its own workspaces and parks hidden windows. The experimental native
Spaces backend moved to the separate SpaceMuxX project on 2026-11-06. Treat dated
adoption documents as historical scope and validate their assumptions against
current code and the requested change.

Use the checks specified in CONTRIBUTING and report native manual validation
separately. Preserve the fork's configuration, bundle/signing identity and recovery
data; follow [fork maintenance](docs/FORK.md) for the commit workflow and installation.
