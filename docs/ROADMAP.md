# WinMuxX roadmap

## Current baseline — 2026-10-17

Workspace/configuration ownership cleanup is complete in signed build 76; see
[RUNTIME_STATE_CLEANUP_PLAN.md](RUNTIME_STATE_CLEANUP_PLAN.md). Settings, display
assignments/rules, the retained AeroSpork adaptations and dependency cleanup are
implemented. Accessibility and screen capture were granted in the latest diagnostics.
The latest local check passes **1,078 Swift + 13 Python tests**. Signed build 78
is installed and verified. Capture runs off-main and the preview surface is reused;
aggregate stage timings are available. Build 77's physical run measured 23 warm
submissions at p95 47.6 ms, still above target. At least 30 completed warm submissions
are needed with the expanded diagnostics; the latency goal remains open.

## Remaining work, in priority order

| Priority | Work | Completion criteria |
| --- | --- | --- |
| 1 | Swipe latency | Capture runs off-main and the surface is reused; collect 30+ warm physical gestures, compare stage timings and pursue <=16.7 ms submission p95. See [performance record](SWIPE_PERFORMANCE.md). Target is not yet established. |
| 2 | Display topology | Real dock/undock/reconnection and three-display tests preserve explicit ownership and one secondary workspace per display; ordinary navigation never relocates workspaces. |
| 3 | Recovery and sizing | Exercise crash recovery with real windows, delayed restoration, learned minima, nested dwindle/tab/accordion groups and overflow. Algorithms and automated regressions already exist. |
| 4 | Native Settings and sidebar | Manual keyboard/accessibility, save/conflict, compact-layout, appearance and Bring Here checks. Offscreen geometry and persistence tests do not certify interaction or appearance. |
| 5 | App/system compatibility | Windows App and Electron AX behavior, Cmd-Tab/Dock with multiple app windows, Mission Control, focus-follows-mouse and isolated permission transitions. |
| 6 | Remaining process adapters | Isolate native window registries, UI singletons and refresh/persistence test adapters where needed. The completed runtime ownership scope does not make the whole suite parallel-safe. |

Remote CI and physical runtime checks must be recorded separately from local suite
results. No fixed grids or scrolling workspace layouts are planned. Accordion and
tabbed layouts already exist. Do not revive rejected feature ideas as backlog items.

## Implemented reliability and UI work

- Native menu-bar action catalog and shared GUI/CLI diagnostics.
- Crash-recovery journal with identity/readback checks and retained failures.
- Learned minimum sizes with evidence, delayed readbacks, persistence and nested fitting.
- Display Settings, window-rule editor, UUID/hardware selectors and Settings save queue.
- Explicit workspace moves, ownership-preserving navigation and complete restart trees.
- Runtime ownership, scoped bindings and fresh test fixtures.

The sections below retain implementation details and outstanding manual checks;
older test totals and permission observations have been superseded by the baseline above.

## Dwindle follow-up

- [x] Adjustable dwindle split ratios: keyboard and mouse resize, shared live/preview geometry, 50/50 reset through `balance-sizes`, gap-aware minimum reservation and frozen-world persistence. The balance crash is fixed; nine new tests cover these paths.
- [x] Redistribute ratios after close/move/insertion and preserve slot shares on swaps/replacements.
- [x] Aggregate nested dwindle minimums, tab chrome and per-monitor gaps; share tile fitting with previews.
- [x] Structural movement across containers, preserving whole tab groups and explicit swap semantics.
- [x] Physical-geometry insertion and matching-axis tiles parent reuse.
- [x] Explicit/automatic orientation, persistence and live default-setting updates.
- [x] Virtual directional focus with overlap, active-tab spatial targets and geometric workspace wrap.
- [x] Sequential corner resize with automatic-axis changes and matching live geometry.
- [x] Flatten resets ratios/default orientation and preserves order, floating windows and logical focus.

See [the detailed Dinky comparison](DWINDLE_DINKY_COMPARISON.md) for behavior and validation. Tabbed and accordion layouts are both supported. Fixed grids and scrolling workspace layouts are excluded by the product scope.

## Ideas to revisit

- [x] **Denser frost for the expanded sidebar:** the expanded sidebar now shares the Background toggle’s translucent glass surface with a lighter tint veil, retaining native blur, wallpaper-derived automatic tint, manual color choices, and the current compact rail. Reduce Transparency still overrides it with an opaque surface.
- [x] **Optional short animations:** sidebar and tab-strip state transitions now disable animation when Reduce Motion is enabled. State-driven SwiftUI transitions retarget to the latest value; monitor reflow remains responsible for settling geometry after display changes. Runtime interruption checks remain useful follow-up validation. [Reference](https://github.com/mikker/Dinky/blob/main/Sources/dinky/Animator.swift).
- [x] **Focus follows mouse:** off by default, configurable dwell, ignores dragging and button presses, and protects focus after pointer changes. Runtime validation remains pending. [Reference](https://github.com/mikker/Dinky/blob/main/Sources/dinky/FocusFollowsMouse.swift).
- [x] **Mission Control / Exposé:** border overlays are suppressed when macOS exposes the display-sized WindowManager layer, while workspace visibility and activation remain untouched. Runtime validation remains pending. [Reference](https://github.com/mikker/Dinky/blob/main/Sources/dinky/MissionControl.swift).
- [x] **Comparar o algoritmo dwindle:** revisão concluída. O Dinky mantém mínimos no modelo de layout, calcula `minimumExtent` recursivamente e usa `fit` para redistribuir espaço. O WinMux agora usa slots virtuais com sobreposição para foco, movimento estrutural entre containers e preservação de proporções nas trocas. A criação de janelas divide a área focada pelo maior eixo em ambos, com regras adicionais do WinMux para tab groups e janelas não convencionais. [Dinky](https://github.com/mikker/Dinky).

Future items need a detailed implementation plan and tests before execution. The current delivery does not change the TOML format, create additional global hotkeys, alter macOS preferences or stop other apps.

## Electron Accessibility compatibility

- [x] Discover windows through `AXWindows`, `AXMainWindow` and `AXFocusedWindow`, deduplicating by window ID. Resolve uncached operation targets through the same fallback and use it for window existence and counts. An unanswered window list without a fallback remains unknown rather than reporting zero windows. Six regression tests cover empty/unsupported/partial lists, duplicate elements, lookup priority and mismatched IDs.

Adapted from [Dinky 0.11's Electron fix](https://github.com/mikker/Dinky/commit/0fd853017eb6afca01126bf0f1011b09c5c7a614). Manual validation with Obsidian/Electron remains pending.

Revisão de cada controle de aparência e suas dependências: [APPEARANCE_SETTINGS_REVIEW.md](APPEARANCE_SETTINGS_REVIEW.md). Modos de sidebar unificados, controles sem efeito removidos/condicionados e overrides de gaps preservados; validação visual pendente.

## Dinky 0.12 / 0.13 follow-up

Dinky 0.13 uses the same fullscreen-button classification and title-bar exceptions already present in WinMuxX. Mocked AX regression coverage now checks missing/disabled controls, terminal/editor exceptions, Chrome, Ghostty and native dialogs. Existing `on-window-detected` layout rules remain the per-app override; no global floating setting is added.

Dinky 0.12's selected-window raise already existed here. Activation context now survives heavier coalesced refresh events and cancellation by light sessions, retaining the originating workspace and latest activated PID. Raising remains restricted to a matching native/logical window on another workspace whose app is still frontmost. Scheduler tests cover creation, destruction and wake event merges in both orders.

References: [classification](https://github.com/mikker/Dinky/blob/main/Sources/dinky/WindowRules.swift), [activation](https://github.com/mikker/Dinky/blob/main/Sources/dinky/ActivationFollower.swift). Manual Cmd-Tab/Dock checks with multiple windows and one/two monitors, Finder copy progress, Calculator and hidden-titlebar terminals remain pending.

Historical validation: the then-current Swift suite passed (803 tests), followed by all nine focus regression tests including two added checks for superseding activation during refresh and native selection across workspaces. The Debug `WinMuxApp` product build and `git diff --check` passed. The runtime checks listed above have not been performed.
