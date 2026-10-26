# Documentation

## Current guides

- [Project README](../README.md): features and current settings.
- [Quick start](QUICK_START.md), [concepts](CONCEPTS.md), [layouts](LAYOUTS.md), [recipes](RECIPES.md) and [commands](COMMANDS.md): learn and use WinMuxX.
- [HACKING](../HACKING.md): architecture, development, checks, builds and installation.
- [Displays and window rules](SETTINGS_DISPLAYS_AND_RULES.md): live placement, saved constraints and rule editing.
- [Dependencies](DEPENDENCIES.md): package inventory, removal decisions and Swift toolchain.
- [Reliability](RELIABILITY.md): AX failures, retries, UUID targeting, config backups and IPC limits.
- [Runtime efficiency](RUNTIME_EFFICIENCY.md): persistence, native notifications, queries, subscribers and capture limits.
- [Window management internals](WINDOW_MANAGEMENT_INTERNALS.md): opt-in AX measurements, private-path diagnostics and pure tree geometry.
- [Release validation](RELEASE_VALIDATION.md): completed checks, long observation and remaining native/energy gaps.
- [Testing](TESTING.md): test design, isolation, asynchronous coordination and CI reports.
- [Swipe performance](SWIPE_PERFORMANCE.md): stage timings, local surface benchmarks and physical validation requirements.
- [Runtime state cleanup](RUNTIME_STATE_CLEANUP_PLAN.md): scope, ownership decisions and acceptance results.
- [Fork maintenance](FORK.md): identity, upstream workflow, configuration ownership and signing.
- [Roadmap](ROADMAP.md): progress, deferred work and manual validation.

- [Dinky 0.22 width and alignment](DINKY_022_ADOPTION.md): width percentages, display/workspace overrides and legacy configuration migration.
- [Dinky 0.21 command migration](DINKY_021_ADOPTION.md): workspace/container commands and format output.
- [Workspace overview](WORKSPACE_OVERVIEW.md): behavior, resource limits and validation.

## Reviews and investigations

- [Native Spaces](NATIVE_SPACES.md): experimental read-only backend, opt-in and rollback; [technical assessment](NATIVE_SPACES_ASSESSMENT.md) and [decision record](NATIVE_SPACES_ADR.md).
- [Dinky native implementation comparison](NATIVE_SPACES_DINKY_COMPARISON.md): coordinator, lifecycle, event reliability, frame scheduling and policies to retain or change.

- [Dinky fit and implementation plan](DINKY_FIT_PLAN.md): 2026-10-22 evaluation, existing adaptations, documentation, configuration completion and reliability priorities.
- [Dinky execution checklist](DINKY_EXECUTION_PLAN.md): ordered implementation tasks, exact starting files, validation and completion evidence for an implementation agent.

These documents preserve observations and experiments. Earlier sections may refer
to controls, filenames or implementations subsequently replaced. Use the current
guides above for today's settings and development workflow.

- [Appearance settings review](APPEARANCE_SETTINGS_REVIEW.md)
- [Menu-bar appearance investigation](MENU_BAR_APPEARANCE_INVESTIGATION.md)
- [Dinky 0.20 adaptations](DINKY_020_ADOPTION.md)
- [Dwindle comparison with Dinky](DWINDLE_DINKY_COMPARISON.md)
- [Simplification review](SIMPLIFY_REVIEW.md)
- [Window motion](WINDOW_MOTION.md)
- [Plano de limpeza e controles nativos](CODE_HEALTH_NATIVE_UI_PLAN.md)

- [Configuration and migration](CONFIGURATION.md): TOML preferences, persistent workspace names and legacy preference import.
- [Configuration schema inventory](CONFIGURATION_SCHEMA_INVENTORY.md): parser-backed field map for editor completion maintenance.
