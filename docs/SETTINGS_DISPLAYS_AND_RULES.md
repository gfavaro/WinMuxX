# Displays and window rules

## Displays

Settings → Displays lists connected screens, their point resolution, UUID and
workspace ownership. Copy UUID produces a ready-to-use `uuid:…` selector.
Hardware selectors are offered when the display supplies nonzero vendor, model
and serial identifiers.

Choose a workspace and destination, then click **Bring Here…**. Confirmation shows
the destination and its current workspace. Cancel changes nothing. The operation
uses the existing move-workspace-to-monitor command. Secondary displays keep one
workspace; displaced workspaces return to main. Ordinary navigation continues to
focus workspaces on their owning display. A disconnected or changed destination
requires reviewing the move again.

**Configured assignments** edits `[workspace-to-monitor-force-assignment]` using
workspace and display pickers. Display labels retain their internal workspace IDs.
Advanced entry supports future workspace names and custom selectors or ordered
selector arrays. These are persistent placement constraints, including
after startup, not one-time moves. Existing assignments remain visible even when
their display is unavailable.
Choose Edit to change one, then Save changes. Merely opening the editor preserves
the original value and formatting, including ordered alternatives. External
assignment changes cause a conflict instead of being overwritten. Multiple saved
assignments to the same connected
secondary are rejected. Startup options remain in General; Bring Here does not
write an assignment or change those defaults.

UUID remains the preferred explicit selector. Existing commands also accept:

```sh
winmuxx focus-monitor hardware:123:456:789
winmuxx move-workspace-to-monitor --workspace 2 hardware:123:456:789
```

These example numbers stand for decimal vendor, model and serial values. Missing,
zero or ambiguous hardware identities fail rather than choosing a different
display. No UUID-to-hardware fallback or reconnect movement is introduced.

## Width and lone-window placement

Settings → Windows edits the global `fullscreen-width` percentage and
`single-window-alignment` (center, left or right), and displays the current
workspace's resolved width/alignment and monitor. Width applies to lone tiles and
WinMuxX fullscreen; fullscreen stays centered. The available width excludes
sidebar space and outer gaps. These values also support `[display.<selector>]`,
`[workspace.<internal-name>]` and nested workspace/display tables. Omitted keys
inherit through workspace/display → workspace → display → global. Changing the
global controls preserves override tables. See [configuration examples and
migration](DINKY_022_ADOPTION.md).

## Window rules

Settings → Automation → Rules provides app selection, app/title regex,
workspace matching, startup/runtime timing and continuation to later rules.
A Matches / Actions table shows rules in file order. The detail form appears
below the table in compact windows and beside it when the page has at least
720 points of width. Save and Revert remain available beneath the editor. Layout
and workspace actions are editable with guided
controls only when their existing order and options are representable.

Rules that send a window elsewhere (`move-node-to-workspace`, `move-node-to-monitor`,
`move-node-to-project`) apply only to an app's ordinary windows. Its dialogs (save
and print panels, format sheets) stay with the app, so a routing rule for a browser
cannot hide the browser behind a modal; floating and tiling actions still apply.

**Add rule** creates an unsaved draft. Save applies it to future window detections;
existing windows are not reclassified. Revert discards the draft. Save or revert
before switching rules. Move up/down changes rule order; deletion asks for
confirmation. An explicit `on-window-detected = []` is an ordinary empty rule
list. Adding a draft leaves the file unchanged; saving the first rule removes only
the empty assignment and appends its rule block, retaining comments and unrelated
settings. Nonempty inline/custom rule shapes still use the configuration editor.

Custom commands retain their original text and order. Use Configuration editor
for custom action editing or TOML shapes the form cannot safely represent.
Structured edits preserve other config content and use the shared validation,
private backups and conflict checks. If rules change externally during an edit,
the save is refused and the draft remains available. Unrelated changes outside
the rule blocks are preserved.

## Navigation and shortcuts

Settings remembers its last page and the Rules / Events selection in Automation.
These preferences are stored locally in app preferences, not TOML. Unknown saved
page identifiers fall back to General; unknown Automation sections fall back to
Rules. Existing settings drafts remain available while navigating pages.

Shortcuts offers search by action title, description, command or assigned shortcut
notation (for example, `alt-h`). Matching is case-insensitive. Results retain the
same action IDs and recorder behavior; clearing search restores the directional
controls and grouped layout. The query remains available while navigating within
Settings. This search covers the existing managed shortcut actions; it does not
add editing or searching of other modes.

## Cleanup evidence

A fresh SwiftPM index covering the app, tests and executable products was scanned
with the existing Periphery 3.6.0. Findings were checked against repository call
sites before removal. Removed components include the unused Settings-opening view,
drag-grid shape, shortcut-reader wrapper, old tab-selection state, unattached
project/tab gesture factories, ten unreachable marketing views, and the excluded
shell-language experiment/tooling. Active handlers, native callbacks, commands
and production marketing scenes remain.

The cached scan from the planning stage was not used as sole deletion evidence.
Remaining scanner findings are candidates, not automatically unused code. This
cleanup adds no packages and makes no measured swipe-latency claim.

Dinky 0.19 additions: the Rules editor also accepts an **App ID regex**, independently
of the exact App ID. All supplied conditions must match. Automation → Events adds
**On display connect/disconnect**, after the display topology settles, with
`WINMUX_DISPLAYS` and `WINMUX_PREV_DISPLAYS` available to shell commands.
Optional `[workspace.<internal-name>.display.<selector>]` layout/orientation defaults
are advanced configuration; see [the adoption notes](DINKY_019_ADOPTION.md).
