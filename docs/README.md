# Documentation

Start with the [project README](../README.md), then pick a path.

## Learn

| Guide | What you get |
| --- | --- |
| [Quick start](QUICK_START.md) | Install, grant access, first windows |
| [Concepts](CONCEPTS.md) | Projects, workspaces, displays and how they relate |
| [Layouts](LAYOUTS.md) | Dwindle, master, tabbed, strip and containers |
| [Recipes](RECIPES.md) | Copy-paste setups for common needs |
| [Commands](COMMANDS.md) | The CLI, grouped by what each command affects |

## Configure

| Guide | What you get |
| --- | --- |
| [Configuration](CONFIGURATION.md) | TOML preferences, persistent names, legacy import |
| [Windows](WINDOWS.md) | Lone-window width, tab groups, stacks, tiling and floating |
| [Workspaces and displays](WORKSPACES.md) | Persistent slots, navigation, monitors, swipes |
| [Sidebar](SIDEBAR.md) | Placement, appearance, auto-hide, clock |
| [Borders and spacing](APPEARANCE.md) | Window borders and gaps |
| [Shortcuts and launching](SHORTCUTS.md) | Launching apps, modifier sides, the palette |
| [Menu bar and recovery](MENU_BAR.md) | Indicator, menu, `doctor`, restart and crash recovery |
| [Displays and window rules](SETTINGS_DISPLAYS_AND_RULES.md) | Live placement, startup assignments, rules |
| [Configuration reload](CONFIG_RELOAD.md) | File watching and what a failed reload keeps |
| [Accessory windows](ACCESSORY_WINDOWS.md) | How menu-bar apps' windows are classified |

## Migrate

- [Dinky 0.22 width and alignment](DINKY_022_ADOPTION.md)
- [Dinky 0.21 command migration](DINKY_021_ADOPTION.md)

## Contribute

Read [principles](PRINCIPLES.md) and [CONTRIBUTING](../CONTRIBUTING.md) first.

| Guide | What you get |
| --- | --- |
| [Contributor task map](CONTRIBUTOR_TASKS.md) | Entry points, acceptance criteria, verification |
| [Workspace behavior](WORKSPACE_BEHAVIOR.md) | Worked examples of display ownership |
| [HACKING](../HACKING.md) | Architecture, builds, checks, installation |
| [Testing](TESTING.md) | Test design, isolation, CI reports |
| [Atlas GUI testing](ATLAS.md) | Helper setup and isolated GUI checks |
| [Agent guidance](../AGENTS.md) | Repository-local skills for agents |
| [Agent evaluation](AGENT_EVALUATION.md) | Optional isolated trials |
| [Marketing images](MARKETING.md) | Site, README and promotional pictures |
| [Fork maintenance](FORK.md) | Identity, upstream workflow, signing |
| [Dependencies](DEPENDENCIES.md) | Package inventory and toolchain |

## Reference

- [Reliability](RELIABILITY.md): AX failures, retries, UUID targeting, config backups, IPC limits.
- [Runtime efficiency](RUNTIME_EFFICIENCY.md): persistence, notifications, queries, subscribers.
- [Window management internals](WINDOW_MANAGEMENT_INTERNALS.md): AX measurements and tree geometry.
- [Release validation](RELEASE_VALIDATION.md): completed checks and remaining gaps.
- [State API](STATE_API.md)
- [Roadmap](ROADMAP.md): progress, deferred work, manual validation.

## Open plans

- [Screen-sharing picker compatibility](SCREEN_SHARING_PICKER_PLAN.md): investigation and plan; no runtime changes yet.
- [Shoji review](SHOJI_REVIEW.md): hands-on notes, pill tab strips and other ideas.

## Archive

Dated reviews, investigations and completed plans live in [`archive/`](archive/).
They preserve observations and experiments. Earlier sections may refer
to controls, filenames or implementations subsequently replaced. Use the current
guides above for today's settings and development workflow.

- [Window handling comparison](archive/WINDOW_HANDLING_COMPARISON.md): WinMuxX, the original WinMux and Dinky on window and app identity, AX isolation, frame writes, hiding and failure visibility.
- [Dinky fit and implementation plan](archive/DINKY_FIT_PLAN.md): 2026-10-22 evaluation, existing adaptations, documentation, configuration completion and reliability priorities.
- [Dinky execution checklist](archive/DINKY_EXECUTION_PLAN.md): ordered implementation tasks, exact starting files, validation and completion evidence for an implementation agent.
- [Robustness plan](archive/ROBUSTNESS_PLAN.md), shipped in build 121, with its [validation](archive/ROBUSTNESS_VALIDATION.md).
- [AeroSpork comparison](archive/AEROSPORK_REVIEW.md) and the [Settings ideas it led to](archive/SETTINGS_AND_CLEANUP_PLAN.md), shipped in build 73.
- [prateek/winmux fork review](archive/PRATEEK_FORK_REVIEW.md)
- [Test suite review](archive/TEST_SUITE_REVIEW.md)
- [Appearance settings review](archive/APPEARANCE_SETTINGS_REVIEW.md)
- [Menu-bar appearance investigation](archive/MENU_BAR_APPEARANCE_INVESTIGATION.md)
- [Dinky 0.20 adaptations](archive/DINKY_020_ADOPTION.md)
- [Dwindle comparison with Dinky](archive/DWINDLE_DINKY_COMPARISON.md)
- [Simplification review](archive/SIMPLIFY_REVIEW.md)
- [Window motion](archive/WINDOW_MOTION.md)
- [Plano de limpeza e controles nativos](archive/CODE_HEALTH_NATIVE_UI_PLAN.md)
