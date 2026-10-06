# Accessory application windows

WinMuxX reads the application's `LSUIElement` bundle declaration once when it registers the process. Boolean and numeric property-list values are supported, as are the strings `true`, `false`, `1` and `0` (case-insensitive, ignoring surrounding whitespace). Missing or unsupported values mean the application has not declared itself accessory.

Real windows from an accessory application float by default even if its current activation policy temporarily becomes regular. Popup filtering still happens first: menus, excluded utility popups and Ghostty Quick Terminal remain outside the workspace window list. Applications without the declaration retain the existing classification heuristics.

This only sets the initial binding of newly discovered windows. Existing restart restoration and explicit `on-window-detected` layout rules retain their precedence. Changing configuration does not reclassify all open windows. There is no new configuration key; use the existing layout rules or manual layout commands to tile a utility window when desired.

`debug-windows` includes `WinMux.App.LSUIElement` alongside the live activation policy to explain the classification.
