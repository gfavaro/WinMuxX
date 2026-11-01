# Working in WinMuxX

Read [core principles](docs/PRINCIPLES.md) and [CONTRIBUTING](CONTRIBUTING.md) before
substantive changes. [HACKING](HACKING.md) owns architecture and development details;
[Testing](docs/TESTING.md) owns verification requirements. No external memory service
or personal skill installation is required to contribute.

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

Use the [task map](docs/CONTRIBUTOR_TASKS.md) for code owners, completion criteria
and failure handling. Read [workspace examples](docs/WORKSPACE_BEHAVIOR.md) when
selection or movement is affected. [Agent evaluation](docs/AGENT_EVALUATION.md)
is only for an explicitly requested model/guidance trial, not routine work.

The default backend uses WinMuxX workspaces and parks hidden windows. An
experimental native Spaces backend is opt-in ([native Spaces](docs/NATIVE_SPACES.md));
keep virtual behavior working and validate native changes separately. Treat dated
adoption documents as historical scope and validate their assumptions against
current code and the requested change.

Use the checks specified in CONTRIBUTING and report native manual validation
separately. Preserve the fork's configuration, bundle/signing identity and recovery
data; follow [fork maintenance](docs/FORK.md) for the commit workflow and installation.
