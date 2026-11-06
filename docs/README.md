# Documentation

## Current guides

- [Contributor task map](CONTRIBUTOR_TASKS.md) and [workspace behavior examples](WORKSPACE_BEHAVIOR.md): entry points, acceptance criteria and verification.
- [Agent evaluation](AGENT_EVALUATION.md): optional isolated trials and evidence from the initial Luna evaluation.

- [Core principles](PRINCIPLES.md): product behavior to preserve, especially whole-workspace display moves.
- [Contributing](../CONTRIBUTING.md) and [agent guidance](../AGENTS.md): contributor workflow and repository-local skills.

- [Project README](../README.md): features and current settings.
- [Quick start](QUICK_START.md), [concepts](CONCEPTS.md), [layouts](LAYOUTS.md), [recipes](RECIPES.md) and [commands](COMMANDS.md): learn and use WinMuxX.
- [Configuration and migration](CONFIGURATION.md): TOML preferences, persistent workspace names and legacy preference import.
- [Configuration schema inventory](CONFIGURATION_SCHEMA_INVENTORY.md): parser-backed field map for editor completion maintenance.
- [Configuration reload](CONFIG_RELOAD.md): file watching, debounce and what a failed reload keeps.
- [Accessory windows](ACCESSORY_WINDOWS.md): how menu-bar apps' windows are classified and floated.
- [Displays and window rules](SETTINGS_DISPLAYS_AND_RULES.md): live placement, startup assignments and rule editing.
- [Native Spaces](NATIVE_SPACES.md): the optional macOS Spaces backend, its tiling, limits and rollback; [workspace backend architecture](WORKSPACE_BACKEND_ARCHITECTURE.md), [technical assessment](NATIVE_SPACES_ASSESSMENT.md) and [decision record](NATIVE_SPACES_ADR.md).
- [Workspace overview](WORKSPACE_OVERVIEW.md): behavior, resource limits and validation.
- [Dinky 0.22 width and alignment](DINKY_022_ADOPTION.md): width percentages, display/workspace overrides and legacy configuration migration.
- [Dinky 0.21 command migration](DINKY_021_ADOPTION.md): workspace/container commands and format output.
- [HACKING](../HACKING.md): architecture, development, checks, builds and installation.
- [Marketing images](MARKETING.md): rendering site, README and promotional pictures, and publishing the GitHub Pages site.
- [Dependencies](DEPENDENCIES.md): package inventory, removal decisions and Swift toolchain.
- [Reliability](RELIABILITY.md): AX failures, retries, UUID targeting, config backups and IPC limits.
- [Runtime efficiency](RUNTIME_EFFICIENCY.md): persistence, native notifications, queries, subscribers and capture limits.
- [Window management internals](WINDOW_MANAGEMENT_INTERNALS.md): opt-in AX measurements, private-path diagnostics and pure tree geometry.
- [Release validation](RELEASE_VALIDATION.md): completed checks, long observation and remaining native/energy gaps.
- [Testing](TESTING.md): test design, isolation, asynchronous coordination and CI reports.
- [Swipe performance](SWIPE_PERFORMANCE.md): stage timings, local surface benchmarks and physical validation requirements.
- [Runtime state cleanup](archive/RUNTIME_STATE_CLEANUP_PLAN.md): scope, ownership decisions and acceptance results.
- [Fork maintenance](FORK.md): identity, upstream workflow, configuration ownership and signing.
- [Roadmap](ROADMAP.md): progress, deferred work and manual validation.

## Open plans

- [Screen-sharing picker compatibility](SCREEN_SHARING_PICKER_PLAN.md): investigation and plan; no runtime changes yet.

## Archive

Dated reviews, investigations and completed plans live in [`archive/`](archive/).
They preserve observations and experiments. Earlier sections may refer
to controls, filenames or implementations subsequently replaced. Use the current
guides above for today's settings and development workflow.

- [Window handling comparison](archive/WINDOW_HANDLING_COMPARISON.md): WinMuxX, the original WinMux and Dinky on window and app identity, AX isolation, frame writes, hiding and failure visibility.
- [Dinky native implementation comparison](archive/NATIVE_SPACES_DINKY_COMPARISON.md): coordinator, lifecycle, event reliability, frame scheduling and policies to retain or change.
- [Dinky fit and implementation plan](archive/DINKY_FIT_PLAN.md): 2026-10-22 evaluation, existing adaptations, documentation, configuration completion and reliability priorities.
- [Dinky execution checklist](archive/DINKY_EXECUTION_PLAN.md): ordered implementation tasks, exact starting files, validation and completion evidence for an implementation agent.
- [Robustness plan](archive/ROBUSTNESS_PLAN.md), shipped in build 121, with its [validation](archive/ROBUSTNESS_VALIDATION.md).
- [Scrolling workspaces validation](archive/SCROLLING_WORKSPACES_COMPLETION.md)
- [AeroSpork comparison](archive/AEROSPORK_REVIEW.md) and the [Settings ideas it led to](archive/SETTINGS_AND_CLEANUP_PLAN.md), shipped in build 73.
- [prateek/winmux fork review](archive/PRATEEK_FORK_REVIEW.md)
- [Shoji review](SHOJI_REVIEW.md): hands-on notes, pill tab strips and other ideas; not yet reviewed.
- [Test suite review](archive/TEST_SUITE_REVIEW.md)
- [Appearance settings review](archive/APPEARANCE_SETTINGS_REVIEW.md)
- [Menu-bar appearance investigation](archive/MENU_BAR_APPEARANCE_INVESTIGATION.md)
- [Dinky 0.20 adaptations](archive/DINKY_020_ADOPTION.md)
- [Dwindle comparison with Dinky](archive/DWINDLE_DINKY_COMPARISON.md)
- [Simplification review](archive/SIMPLIFY_REVIEW.md)
- [Window motion](archive/WINDOW_MOTION.md)
- [Plano de limpeza e controles nativos](archive/CODE_HEALTH_NATIVE_UI_PLAN.md)
