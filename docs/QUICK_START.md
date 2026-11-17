# Quick start

Five minutes from download to a tiled desktop.

## 1. Install

Download WinMuxX from the [releases page](https://github.com/gfavaro/WinMuxX/releases)
and move it to `/Applications`, or build it as described in
[HACKING.md](../HACKING.md#build-and-check).

## 2. Grant access

Open WinMuxX and allow **Accessibility** when macOS asks. WinMuxX uses it to read
and position app windows. It never asks for Screen Recording.

## 3. Try it

1. Open two ordinary windows. WinMuxX tiles them in the current workspace.
2. Click a workspace or project in the sidebar to switch.
3. Open **Settings** from the WinMuxX menu to adjust layouts, appearance and
   shortcuts.

## 4. If something looks wrong

- Settings → General → **Setup Check** looks for missing Accessibility access,
  other window managers and trackpad gestures that clash with WinMuxX (in native
  mode, Spaces settings instead). It opens once on first launch if something needs
  attention.
- `winmuxx doctor` prints the config path, permissions, displays and conflicting
  window managers.
- After an interrupted session, see [recovery](MENU_BAR.md#recovery) and
  [reliability](RELIABILITY.md).

## Next

[Concepts](CONCEPTS.md), then [layouts](LAYOUTS.md) and [recipes](RECIPES.md).
Keep the [command guide](COMMANDS.md) and [configuration](CONFIGURATION.md) nearby.
