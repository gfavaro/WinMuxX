# Shoji review

Status: notes from a hands-on session on 2026-11-04, for later review. No runtime
changes. Shoji 1.5 (`com.ankursehrawat.shoji`, shojimac.com) was tried on the
built-in display while WinMuxX was not running. Screenshots of Shoji's panel, hover
bar, pills and Settings pages are kept locally in `~/Documents/WinMuxX Shoji review`,
not in this repository.

Shoji is a paid automatic tiler. Each screen holds 1 to 5 tiles in Grid, Columns,
Rows or Side; when a screen is full, a new window joins the active tile as a stack.
It has up to four workspaces, Setups (saved app arrangements), Clean Space (a plain
screen for sharing) and No peek mode.

## Already in WinMuxX

- The hover bar on a window's top edge with Main, Focus and Float
  (`Sources/AppBundle/ui/WindowHoverBar.swift`).
- Dimming of inactive windows and No peek (`Sources/AppBundle/ui/InactiveWindowDimmer.swift`).
- Borders, focus follows pointer, tab groups with swap/stack by drag, learned
  application minimum sizes, floating rules and a window switcher.
- A menu warning when some keyboard shortcuts are unavailable.
- Tab groups inside Dwindle and Master: `stack-with`, `layout tab-group` or dragging
  a window onto another; Dwindle keeps the group whole and Master treats it as one unit.

## Stacks: pills and the hover bar

Shoji has no tabs in WinMuxX's sense. A tile holds a stack of windows, and its top
edge shows a thin rail of pills, one per window. The visible window's pill is wider
and uses the accent colour. The rail is drawn in the gap and costs no layout height.

Resting the pointer on the pills opens one bar over the tile's top edge:

- a tab row, one entry per stacked window, with ‹ › scroll arrows;
- an action row: Primary ⌃⌥↩, Focus ⌃⌥Z, Next screen and Float ⌃⌥F, each with
  its shortcut printed below.

Clicking a tab shows that window immediately without resizing, and the bar closes.
Entries show only the app icon and name, so several Finder windows all read "Finder".

### Proposal for WinMuxX tab strips

Not yet agreed; review before building.

- At rest, a tab group shows only the pill rail on its top edge. Windows regain
  most of the strip's height (`window-tabs.height`, minimum 36 pt).
- After resting on the rail (350 ms, as the hover bar), the existing strip opens
  over the active window's top edge with titles, reordering and close buttons. The
  hover bar actions join it as a second row.
- During a window drag and after keyboard tab switching, the full strip shows so
  drop targets and the new tab remain visible.
- A default, not a new setting.

Code to change: the reserved height in `layoutTabGroup`
(`Sources/AppBundle/layout/layoutRecursive.swift`), tab bar geometry in
`Sources/AppBundle/ui/tabs/TilingContainer+WindowTabs.swift` and
`Sources/AppBundle/ui/tabs/WindowTabFrameGeometry.swift`, drop and resize geometry under
`Sources/AppBundle/mouse/`, the strip panels in
`Sources/AppBundle/ui/tabs/WindowTabStripPanelController.swift`, and the group frame
shape. Double-sided windows keep their own chrome.

Open questions:

- What is missing when using strips in Dwindle or Master? They already work there.
  One option is a Stack action in the hover bar, so stacking does not need a command.
- Should the pill rail sit in the gap above the group, or inside the group frame?

## Other ideas

In rough order of value:

1. **Menu-bar panel.** A popover instead of a plain menu: a live mini-map of the
   current screen (tiles as cards with app icon and name, focused one outlined),
   layout and window-count pictograms, large toggles for Retile, Borders and Hover
   focus, and a switch to stop tiling the frontmost app. WinMuxX uses
   `Sources/AppBundle/ui/menubar/NativeActionMenu.swift`.
2. **Settings search with synonyms.** Typing "gap" finds "Space between windows ·
   Layout"; every setting carries extra keywords. WinMuxX searches only Shortcuts.
3. **Live previews with a caption.** Layout and Highlight pages open with a mock
   arrangement captioned "3 windows · 8 pt apart · border on the active window".
4. **Per-shortcut conflicts.** Shoji names the owner of a clashing key (macOS, an
   open app's menus, another copy of itself), suggests free keys nearby, draws
   shortcuts as keycaps, and has one prefix choice (⌃⌥, ⌥⌘ or ⌃⇧) for all of them.
5. **Switcher details.** Tab View (⌥Tab) groups windows by screen, shows titles, has
   a "Nothing minimized" section and a footer: "Tab next · ⇧Tab back · arrows move ·
   let go of ⌥ to switch · Esc". WinMuxX groups by workspace.
6. **Teaching.** The Mouse page lists the gestures that always work; Activity shows
   a "Try next" card for an unused feature; Apps lists built-in exclusions with a
   "Default" label that can be removed.
7. **Fit explanations.** From Shoji's strings, not observed: "Xcode needs more room
   than 3 windows leave here", "can't be narrower than 900 pt, so it floats",
   "Screen 2 has room for it", with learned minimum sizes listed per app.
8. **Clean Space and Setups.** Locked during the trial. Clean Space makes the current
   screen plain (Graphite, Stone or Mist background) with one key; Setups saves the
   open apps and their arrangement and reopens them, hiding other apps.

Smaller ideas, not yet checked against WinMuxX:

- **Stack instead of shrinking.** When another window would push a tile below an
  application's learned minimum size, stack it in the active tile rather than floating
  it or overflowing. Shoji's equivalent is "When a screen is full: stack in the active tile".
- **One-click "always float".** Option-clicking Float in the hover bar adds a rule for
  windows like this one (same app and title prefix); the app's other windows still tile.
- **Frontmost-app switch.** "Tile Rex Beta" in the menu stops tiling the current app
  without opening Settings.
- **Retile feedback.** Retile reports "3 windows were put back in their places" or
  "Everything was already in place".
- **Pause without moving.** Turning Shoji off leaves windows where they are; turning
  it on again rearranges them.
- **Edge space for other apps' bars.** Per-screen space kept free for third-party docks,
  set by dragging an edge while a blue strip marks it.
- **Portrait monitors.** Columns become rows, and Grid puts one window on top with the
  others below, when a screen is taller than wide.
- **Hover focus delay.** A short delay so passing over windows does not change focus.
- **Gap-only highlights.** Borders and glows are drawn in the gap, never over content.
- **Private diagnostics.** The problem report names apps "App A, App B" and omits
  monitor and Mac model names.

Not worth copying: activity counts, "time saved" and alternative app icons.

## Trying another window manager

Quit WinMuxX first. Screenshots from Claude Code need its sandbox disabled. Rex
Server must hold Accessibility and Screen Recording; after granting them, restart it
and run scripted clicks from a new Rex session, since earlier processes keep the old
permission.
