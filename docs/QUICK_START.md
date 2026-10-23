# Quick start

Install WinMuxX from the [releases page](https://github.com/gfavaro/WinMuxX/releases)
using the steps in [HACKING.md](../HACKING.md#build-and-check), then open
WinMuxX and grant Accessibility access when macOS asks. WinMuxX uses that access
to read and position app windows. Screen Recording is optional and is used for
workspace previews; tiling works without it.

Open two ordinary windows. WinMuxX places them in the current workspace. Use the
sidebar to switch workspaces or projects, and open Settings from the WinMuxX
menu to adjust layouts, appearance and shortcuts. The current commands and
configuration are in the [CLI help](COMMANDS.md) and
[configuration guide](CONFIGURATION.md).

Run `winmuxx doctor` in Terminal to see the config path, permissions, displays
and other window managers. For a guided overview, read
[concepts](CONCEPTS.md), then [layouts](LAYOUTS.md) and
[recipes](RECIPES.md). See [recovery](RELIABILITY.md) if an interrupted session
left windows out of place.
