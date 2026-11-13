# Working in WinMuxX

Read [core principles](docs/PRINCIPLES.md) and [CONTRIBUTING](CONTRIBUTING.md)
before substantive changes. Use the [task map](docs/CONTRIBUTOR_TASKS.md)
and [HACKING](HACKING.md) to find the relevant code and development setup.

Always build code cleanly and modularly, with proper architecture and separation of
concerns. Never bolt a feature on just because it was asked for. If there is no easy
way to build it naturally, and a refactor would make the whole thing clean, stop
before writing the feature and say so, recommending the refactor.

Ordinary workspace selection preserves display ownership. Explicit moves
change ownership and carry the workspace's project, identity, nested layouts
and tabs. For workspace lifecycle, selection, display assignment or movement,
read the [workspace skill](.agents/skills/winmuxx-workspaces/SKILL.md).

Follow [Testing](docs/TESTING.md) for the `make check` gate and report real
macOS validation separately. Preserve the fork's configuration, signing
identity and recovery data. See [fork maintenance](docs/FORK.md) for
submission and installation, and [marketing images](docs/MARKETING.md) for
generating project visuals.
