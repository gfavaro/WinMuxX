# WinMuxX roadmap

## Current delivery

- [x] Native menu-bar action catalog: categorized clickable commands, current-mode shortcuts, custom bindings, taps and sequences.
- [x] Shared CLI and GUI diagnostics: loaded config path, validation, permissions, displays, AX latency and potentially conflicting window managers; refresh/copy without changing system settings.

Verified with the Swift test suite, a Debug app build, and runtime checks of the native menu and the GUI/CLI diagnostics. Automated menu-action tests cover routing on two monitors. Display topology handling and learned minimum-size persistence are now implemented and covered by targeted tests.

## Next priorities

Crash-recovery journal and manual menu action are implemented and covered by journal tests. Runtime validation with real windows remains pending. Original geometry is recorded atomically before frame changes; recovery pauses tiling, verifies app identity and readback, skips disconnected displays/native fullscreen/minimized windows, and retains failures. No native Space manipulation is included.

Learned minimum sizes now have per-window evidence, two delayed readbacks, conservative rounding tolerance, cancellation on changed requests/closure/recovery, diagnostics, manual reset, persistence through the frozen-world state, distribution in tile containers, guarded distribution in dwindle, and pure tests for proportional fitting and overflow. Nested dwindle, tab chrome and per-monitor gaps now share contextual minimum aggregation; remaining work is interactive runtime validation.

Validation update: the Debug build completed after rebuilding the stale SwiftPM cache, and the full Swift suite passes (716 tests). Targeted monitor navigation, recovery, dwindle, focus, movement, minimum redistribution and Mission Control suppression suites also pass. Live CLI diagnostics and recovery behavior remain separate from manual runtime validation. Screen-capture permission is currently reported missing for this build and may require reauthorization.

1. **Runtime validation.** Exercise crash recovery and display reconnection with real windows and dock/undock arrangements. [Recovery reference](https://github.com/mikker/Dinky/blob/main/Sources/dinky/Recovery.swift), [display reference](https://github.com/mikker/Dinky/blob/main/Sources/dinky/Display.swift).
2. **Learned minimum sizes.** Validate and refine dwindle, nested containers, tab groups and overflow behavior. [Dinky reference](https://github.com/mikker/Dinky/blob/main/Sources/dinky/FrameApplier.swift).

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

See [the detailed Dinky comparison](DWINDLE_DINKY_COMPARISON.md) for behavior and validation. Accordion is excluded: our tab interface remains the product choice. Fixed layouts remain deferred.

## Ideas to revisit

- [x] **Denser frost for the expanded sidebar:** the frosted effect now uses a more opaque AppKit surface and a stronger tint veil, retaining native blur, wallpaper-derived automatic tint, manual color choices, and the current compact rail. Reduce Transparency still overrides it with an opaque surface.
- **Fixed workspace layouts (deferred):** reserve grid cells, preserve empty slots, define overflow expansion without rearranging existing placements. This remains outside the current delivery scope. [Reference](https://github.com/mikker/Dinky/blob/main/docs/configuration.md#workspacenumber).
- [x] **Optional short animations:** sidebar and tab-strip state transitions now disable animation when Reduce Motion is enabled. State-driven SwiftUI transitions retarget to the latest value; monitor reflow remains responsible for settling geometry after display changes. Runtime interruption checks remain useful follow-up validation. [Reference](https://github.com/mikker/Dinky/blob/main/Sources/dinky/Animator.swift).
- [x] **Focus follows mouse:** off by default, configurable dwell, ignores dragging and button presses, and protects focus after pointer changes. Runtime validation remains pending. [Reference](https://github.com/mikker/Dinky/blob/main/Sources/dinky/FocusFollowsMouse.swift).
- [x] **Mission Control / Exposé:** border overlays are suppressed when macOS exposes the display-sized WindowManager layer, while workspace visibility and activation remain untouched. Runtime validation remains pending. [Reference](https://github.com/mikker/Dinky/blob/main/Sources/dinky/MissionControl.swift).
- [x] **Comparar o algoritmo dwindle:** revisão concluída. O Dinky mantém mínimos no modelo de layout, calcula `minimumExtent` recursivamente e usa `fit` para redistribuir espaço. O WinMux agora usa slots virtuais com sobreposição para foco, movimento estrutural entre containers e preservação de proporções nas trocas. A criação de janelas divide a área focada pelo maior eixo em ambos, com regras adicionais do WinMux para tab groups e janelas não convencionais. [Dinky](https://github.com/mikker/Dinky).

Future items need a detailed implementation plan and tests before execution. The current delivery does not change the TOML format, create additional global hotkeys, alter macOS preferences or stop other apps.

## Electron Accessibility compatibility

- [x] Discover windows through `AXWindows`, `AXMainWindow` and `AXFocusedWindow`, deduplicating by window ID. Resolve uncached operation targets through the same fallback and use it for window existence and counts. An unanswered window list without a fallback remains unknown rather than reporting zero windows. Six regression tests cover empty/unsupported/partial lists, duplicate elements, lookup priority and mismatched IDs.

Adapted from [Dinky 0.11's Electron fix](https://github.com/mikker/Dinky/commit/0fd853017eb6afca01126bf0f1011b09c5c7a614). Manual validation with Obsidian/Electron remains pending.

Revisão de cada controle de aparência e suas dependências: [APPEARANCE_SETTINGS_REVIEW.md](APPEARANCE_SETTINGS_REVIEW.md). Modos de sidebar unificados, controles sem efeito removidos/condicionados e overrides de gaps preservados; validação visual pendente.
