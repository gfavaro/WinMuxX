# Screen-sharing picker compatibility

Status: investigation and implementation plan; no runtime changes yet.

## Goal

Keep WinMuxX's borders and navigation usable while avoiding duplicate helper-window entries in screen-sharing choosers. Treat a presentation mode as a fallback, not as the assumed solution.

## Evidence collected on 2026-10-21

- Teams' own Window chooser visibly lists repeated untitled WinMuxX entries.
- An earlier live ScreenCaptureKit inventory found eight border surfaces and two sidebar edge-trigger surfaces on screen. This inventory is not a one-to-one count of the later Teams list.
- `Sources/PrivateApi/border.m` creates four WindowServer surfaces per border. The thin surfaces avoid allocating a full-window backing buffer. Their level follows the target application window.
- `Sources/AppBundle/ui/hud/NSPanelHud.swift` creates borderless nonactivating panels. Exclusion from the Window menu does not establish exclusion from a sharing picker.
- A temporary AppKit fixture tested sharing-none, transient/ignores-cycle, ignore-Expose, avoid-capture, floating level, and combined flags. All variants remained in ScreenCaptureKit enumeration. This does not establish how every picker filters them, or prove the same result for raw SkyLight windows.
- Teams Settings > General > Screen sharing offers Teams content sharing and macOS content sharing. Enabling the latter successfully opened Apple's native picker with direct window selection and Show All Windows controls.
- Native Show All Windows inspection was inconclusive: accessibility did not expose the expanded choices and subsequent Control Center reads timed out. Do not claim that the native picker excludes WinMuxX.
- No screen or window was selected for sharing. The original Teams content-sharing preference was restored after the test.

## 1. Complete a controlled comparison

1. Record macOS and Teams versions and the original sharing preference.
2. Use a private test session. Open the chooser without starting a broadcast.
3. Record only WinMuxX window metadata: ID, surface role, visibility, level, and owning controller. Avoid saving unrelated titles or screen content.
4. Compare Teams' chooser and Apple's direct-selection and Show All Windows views. Check both monitors and hidden/expanded sidebar states.
5. Reopen each chooser between variants to rule out cached entries. Restore the original preference afterward.

Acceptance: a documented result for both pickers, including whether helper surfaces are individually selectable or interfere with selecting real application windows.

## 2. Test a rendering-preserving fix

1. Extend a temporary diagnostic fixture to include a raw SkyLight border surface created like `border.m`, alongside an `NSPanelHud`-equivalent panel and a normal control window.
2. Test only classification or ownership changes with an understood API contract and a concrete reason to affect the observed picker. Do not repeat the unsuccessful AppKit flag matrix without new evidence.
3. Check actual chooser behavior as well as ScreenCaptureKit enumeration. A black thumbnail, renamed entry, or unchanged helper count is not success.
4. If a variant works, isolate its native implementation in `Sources/PrivateApi/border.m` and its AppKit equivalent at the narrowest relevant panel factory. Keep optional native symbol lookup and existing rendering fallbacks.
5. Verify occlusion, focus, input passthrough, tab-group outlines, dragging, workspace transitions, Mission Control, and mixed-scale displays.

Acceptance: helper entries disappear in the targeted chooser while borders and navigation retain their current behavior. Preserve four-piece border allocation; do not raise borders above unrelated windows or replace them with a full-screen overlay to manipulate picker filtering.

If the native picker alone works, document that compatibility option and its loss of Teams annotation and give/take-control features. Do not describe this as a WinMuxX rendering fix.

## 3. Optional fallback if visible helpers cannot be excluded

Implement a user-controlled presentation mode only after recording the failure of phase 2:

1. Introduce one runtime state for suppression of helper UI, exposed through a menu action and a bindable command. Default off; do not persist a temporary presentation session or overwrite appearance preferences.
2. Reuse border-controller teardown to release native border windows. Audit sidebar triggers, tab chrome, previews, palette, and overview lifecycles. Merely making panels transparent or ordering them out is insufficient unless the chooser test proves otherwise.
3. Gate creation and deferred refresh paths while suppression is active, including display changes, config reload, hover, and animation callbacks. Cancel pending visual work.
4. Preserve workspace and focus commands. Make the menu action available to leave the mode even when sidebar and palette are suppressed.
5. Recreate required surfaces from current model/configuration state on exit. Do not restore stale window frames or change tiling geometry when tab chrome is suppressed.
6. Avoid background capture polling or automatic Teams meeting detection.

Acceptance: reopening the chooser shows no decorative WinMuxX targets while suppression is active; toggling off restores current visuals without duplicates, stale focus, or changed workspace assignments. A deliberately open Settings window remains a legitimate window target.

## 4. Validation and delivery

- Add lifecycle tests only for implemented behavior: repeated enable/disable, refresh while suppressed, pending callbacks, display changes, and restoration from updated config.
- Verify native and fallback border teardown with live window IDs; confirm window counts return to baseline over repeated cycles.
- Measure idle CPU, memory, and window allocations against the current build.
- Run relevant tests, then required repository checks for the final code change.
- Document the verified picker/OS combinations and remaining limitations. Build, install, and publish only the selected implementation, not unsuccessful experimental flags.

## References

- [Apple: NSWindow sharing types](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum)
- [Microsoft: Native macOS screen sharing in Teams](https://techcommunity.microsoft.com/blog/microsoft365insiderblog/native-macos-screen-sharing-in-teams-meetings/4475544)
