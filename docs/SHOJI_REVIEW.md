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

## Shoji's weak point: workspaces

Shoji arranges each screen well but organizes work poorly. Its workspaces are at most
four numbered sets of windows ("A separate set of windows, like Coding or Writing.
Up to 4."), switched with ⌃⌥1–4 or receiving a window with "Send to workspace". It
ignores macOS Spaces beyond the current one ("Apps on other desktops can't be seen
from here"), pauses under Stage Manager, and has no projects, no per-display
ownership and no way to bring a workspace to another display with its layout.

That is WinMuxX's defining capability ([core principles](PRINCIPLES.md)). Adopt
Shoji's presentation (pills, panel, Settings style) on top of WinMuxX's workspace
model, not its model.

## Compared with WinMuxX

Checked against the code and WinMuxX's running menu and Settings window on the same day.

| Area | Shoji | WinMuxX | Take |
| --- | --- | --- | --- |
| Workspaces and displays | Four numbered sets, current Space only | Projects, persistent workspaces, display ownership, whole-workspace moves | Keep WinMuxX |
| Stacks and tabs | Pill rail at rest, tabs in the hover bar | Full strip with titles, reordering and two-sided windows; new windows can join the current tab group | Pill rail at rest (proposal below) |
| Hover bar | Tabs plus Primary, Focus, Next screen, Float; ⌥-click Float adds a rule | Main, Focus, Float | Merge with the tab strip; ⌥-click Float |
| Menu bar | Panel with state, mini-map, toggles, frontmost-app switch | Long command menu, Enabled, warnings, recovery | Panel |
| Settings layout | About 25 options on intent pages, pictogram choices | Nine pages with effect descriptions, deep display and workspace controls; many menus | Pictograms; move workspace layout mode out of Displays |
| Settings search | Every setting, with synonyms | Shortcuts only | Add |
| Previews | Captioned layout and highlight previews | Spacing preview | Extend and caption |
| Setup and permissions | One "Allowed" row | Setup Check with Check Again, Diagnostics | WinMuxX is ahead |
| Shortcuts | Keycaps, named owner of a conflict, free-key suggestions, one prefix | Search, modes, modifier sides, presets, focus direction pad, workspace modifier pattern, shortcut diagnostics | Show conflicts per shortcut |
| Learned minimum sizes | Listed with Forget | Listed with Forget on Windows | Equal |
| Floating rules | Built-in exclusions shown as Default; always-float list | Always Float This App, title-prefix rule from the menu | Equal |
| Retile | Reports what moved | Reports what moved ("Put 2 windows back") | Equal |
| Dimming and No peek | Yes | Yes | Equal |
| Space for other bars | Drag editor per screen | Per-display outer gaps in TOML | Optional UI |
| Portrait displays | Special layouts | Dwindle splits along the longer axis | Not needed |
| Switcher | By screen, minimized section, key-hint footer | Palette grouped by workspace with search | Key-hint footer |
| Teaching | Mouse gestures page, Try next, tour | None | Mouse gestures list |

Found while comparing: the menu header reads "WinMuxX · Workspace Workspace 3".
`Sources/AppBundle/ui/menubar/NativeActionMenu.swift` prefixes "Workspace " to
`workspaceDisplayName`, whose default for a numbered persistent workspace is already
"Workspace 3" (`Sources/AppBundle/tree/WorkspaceSidebarLabels.swift`). The minimum-size
issues on Settings → Windows did the same. Both now use the display name alone.

WinMuxX Settings expose some configuration shapes directly: persistent workspaces as a
comma-separated list, the workspace layout mode as a "Choose workspace, Save workspace
mode" form under Displays, and UUID and hardware-selector buttons for each display.
These could move behind disclosures, with the common choice as pictograms.

Tab groups already work inside Dwindle and Master: `stack-with`, `layout tab-group` or
dragging a window onto another; Dwindle keeps the group whole and Master treats it as one unit.

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

## Settings and menu bar

These are the most polished part of Shoji, more than its tiling.

### Settings

- Pages follow intent rather than configuration structure: Layout, Highlight, Mouse,
  Keyboard, Apps. No key names appear.
- Main choices are pictogram cards (layout, window count, highlight style, Clean
  Space background). Menus are kept for secondary policies.
- Each control states its effect, often with the shortcut in the sentence: "A new
  window joins the tile you're in, on top. Switch with ⌃⌥` or the grip."
- Layout and Highlight open with a captioned preview of the current choices.
- Search matches synonyms, and the Mouse page documents the gestures that always work.

It works because there are about 25 options. WinMuxX has displays, per-workspace
overrides, projects, automation and a TOML editor, so the structure does not transfer;
the style does: pictogram pickers, effect descriptions, captioned previews and synonym
search. Activity, License and About are clutter.

### Menu-bar panel

- Status at a glance: "Tiling 2 windows", a master switch, and a mini-map of the
  current screen with the focused tile outlined. Its strings say tiles can be dragged
  there to move windows; not tried.
- One click for frequent changes: layout, window count, Retile, Borders, Hover focus
  and No peek.
- "Tile Rex Beta" follows the frontmost app and replaces a visit to the Apps page.
- Weaknesses: the trial notice takes the top, it covers one screen only, and Clean
  Space and Setups appear as upgrade prompts.

For WinMuxX, the sidebar already owns workspaces and displays, so a panel should
cover the current workspace: a mini-map with tab groups drawn as pills, a pictogram
choice of Dwindle, Master or Scrolling, toggles for borders, dimming and No peek,
pointer focus and tab strips, a "Stop tiling" switch for the frontmost app, and the
shortcut and window-manager warnings the native menu already shows. Keep every action
reachable from the keyboard.

First picks: the mini-map with the frontmost-app switch, and pictogram pickers in
Settings. WinMuxX already describes the effect of most controls.

### Simplified native menu (proposal)

Preferred over a drawn panel: keep `NSMenu`, but let the top level show state and
quick switches while commands move into one submenu. Agreed and built; the status
line and a front-app tiling checkbox were left out (the header already names the
workspace and the layout items show it; floating rules cannot be read back reliably),
so the floating row is "Always Float “App”…" with the title rule on Option.

```
Workspace 3 · Dwindle · 4 windows          status line
⚠ warnings, only when present
● Dwindle / Master / Scrolling             workspace layout
  layout-specific items                    Swap with Master; scrolling items
Retile · Balance Sizes · Fullscreen
✓ Tile "<front app>"                       off adds Always Float This App;
                                           ⌥ alternate: Float Windows Titled "…"
✓ No Peek · ✓ Borders · Focus Follows Pointer
Commands ▸                                 Focus, Move, Join, Resize, workspaces,
                                           displays, Reload Config
Recover N Windows… (only when present)
About WinMuxX · Settings… · ✓ Tiling Enabled · Quit
```

"Clear Saved Minimum Sizes…" leaves the menu; Settings → Windows already has Forget.
Borders and Focus Follows Pointer write the configuration as Settings does, and the
layout items keep their small icons.

About WinMuxX shipped first: it opens the standard About panel (name, icon, version,
build) with credits for the fork, upstream WinMux and the repository link.

## Backlog, sorted

Ordered by value for the effort. Effort: S is a day or less, M a few days, L a week
or more with layout or new UI surfaces.

| # | Feature | Effort | Why |
| --- | --- | --- | --- |
| 1 | **Pill tab strip:** pills at rest, full strip with hover actions on hover (proposal above) | L | The Shoji idea that was liked most; returns about 26 pt to every tab group |
| 2 | **⌥-click Float in the hover bar** adds the title-prefix rule the menu already offers | S | Reuses `Sources/AppBundle/ui/settings/QuickFloatingRule.swift`; removes a trip to the menu |
| 3 | **Switcher key-hint footer:** "Tab next · ⇧Tab back · arrows move · Esc" | S | Teaches the palette without documentation |
| 4 | **Settings search across all pages,** with synonym keywords | M | Nine deep pages; search exists only on Shortcuts |
| 5 | **Workspace layout as pictograms on Windows** (Dwindle, Master, Scrolling), replacing the form under Displays; UUIDs and hardware selectors behind a disclosure | M | The most used choice is hard to find today |
| 6 | **Menu-bar panel:** mini-map of the current workspace with tab groups as pills, layout pictograms, toggles for borders, dimming, No peek, pointer focus and tab strips, a float switch for the frontmost app, existing warnings | L | Shows state the command menu cannot; keep the command menu reachable from the keyboard |
| 7 | **Per-shortcut conflicts** on Shortcuts: name the owner, suggest free keys | M | Builds on the existing shortcut diagnostics |
| 8 | **Captioned previews** for borders and tab strips, next to the spacing preview | M | Makes appearance choices visible before they apply |
| 9 | **Stack instead of shrinking:** when a tile would fall below an app's learned minimum size, join the active tab group | M | Pairs with pill strips; needs a policy decision before code |
| 10 | **Mouse gestures list** in Settings (drag to swap, stack, resize, move between displays) | S | Gestures exist but are undiscoverable |

Later or uncertain:

- **Fit explanations.** From Shoji's strings, not observed: "Xcode needs more room
  than 3 windows leave here", "Screen 2 has room for it". WinMuxX already lists
  minimum-size issues on Settings → Windows.
- **Clean Space.** One key makes the current screen plain for sharing; overlaps the
  [screen-sharing plan](SCREEN_SHARING_PICKER_PLAN.md).
- **Setups.** Saved app sets reopened in one click; projects already cover part of it.
- **Private diagnostics.** Name apps "App A, App B" in shared reports; no redaction
  was found in WinMuxX's diagnostics.
- **Edge space editor.** Per-display outer gaps already exist in TOML.
- Pointer focus already waits before switching (`focus-follows-mouse-dwell`).
- Not checked: whether borders stay in
  the gap, and what disabling WinMuxX does to window positions.

Not worth copying: activity counts, "time saved" and alternative app icons.

## Trying another window manager

Quit WinMuxX first. Screenshots from Claude Code need its sandbox disabled. Rex
Server must hold Accessibility and Screen Recording; after granting them, restart it
and run scripted clicks from a new Rex session, since earlier processes keep the old
permission.
