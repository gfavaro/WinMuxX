# WinMuxX core principles

WinMuxX organizes work into projects and workspaces, with a sidebar for finding
and moving that work. Its defining capability is bringing an entire workspace
to another display while retaining its windows and layout. Contributors should
evaluate changes against that workflow.

## A workspace is a portable unit of work

Move the workspace with its tiled windows, floating windows, nested containers
and tab groups. Retain its identity and project membership. Adapt geometry to the
destination display's usable area and application minimum sizes without flattening
the layout or requiring the user to reconstruct it.

For example, a coding workspace on the laptop should be bringable to an external
display and back as one operation. Different display sizes can change pixel
positions; the organization of the work should survive.

## Selection and movement have different meanings

Ordinary selection preserves display ownership, including for hidden workspaces.
Selecting a workspace visible on another display focuses it there. Explicit move
and summon actions change ownership. A configured assignment (`workspace-to-monitor-force-assignment`)
holds while its display is connected, as in AeroSpace: the workspace shows only there, and moves elsewhere are refused.
The sidebar's existing bring-here confirmation is an explicit relocation path.
Do not make ordinary navigation silently exchange workspaces between displays.

Keep destination displacement and source fallback behavior consistent with
`WorkspaceMonitorAssignment.swift`. Test both displays, including the workspace
that was already at the destination, rather than checking only the moved windows.

## Preserve organization and user choices

Projects, persistent workspace identity, sidebar labels, nested layouts and tab
groups are part of the product. Display policies and new layout algorithms must
respect them. A sidebar label is not necessarily the internal command name.
Restart recovery should retain assignments and layout state; failures must not
silently discard the user's organization.

TOML owns behavior and appearance preferences. Settings edits the same configuration
that commands and reload consume. Session state and caches have separate ownership;
avoid a second preference store that can disagree with the configuration file.

## Native interaction, bounded work

Use the established AppKit/SwiftUI surfaces and accessible controls. Respect Reduce
Motion, Reduce Transparency and increased contrast. Validate UI changes through the
actual navigation destination, including keyboard use.

Prefer native events and coalesced, bounded work. Give asynchronous operations an
owner and cancellation or generation checks so old completions cannot affect a new
interaction. Keep geometry and policy testable separately from native side effects.
See [runtime efficiency](RUNTIME_EFFICIENCY.md) and [HACKING](../HACKING.md).

## The backend serves these behaviors

Today WinMuxX uses its own workspaces and parks hidden windows offscreen; these are
distinct from native macOS Spaces. That mechanism is the current implementation,
not the product's defining principle.

The experimental native Spaces backend moved to the separate SpaceMuxX project on
2026-11-06; WinMuxX has one backend.

## Evidence matters

Automated tests establish model and command behavior. Physical gestures, real
application Accessibility behavior, native compositing and display disconnects
need desktop validation. Report those separately and name what remains untested.
Preserve fork identity, user configuration and recovery data during development.

Start contributing with [CONTRIBUTING](../CONTRIBUTING.md). Implementation details
live in [HACKING](../HACKING.md), and test requirements in [Testing](TESTING.md).
