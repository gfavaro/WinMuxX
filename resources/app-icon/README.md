# App icon sources

`gen.py` generates every SVG here; edit it rather than the SVGs and run `python3 gen.py`.
The icon shows a display with the sidebar rail and a Dwindle layout: a tall window
on the left, one at top right and two side by side below it. Windows use the
menu-bar colours and have title bars with traffic lights and content lines.

| File | Use |
|---|---|
| `winmux-icon.svg` | App icon at 64 px and larger: 824 px body on the 1024 px macOS grid |
| `winmux-icon-small.svg` | 16 and 32 pt slots at 1x and 2x: no title bars, content or sidebar dots, wider gutters |
| `composer-background.svg` | Icon Composer layer 1: opaque full-bleed background |
| `composer-display.svg` | Icon Composer layer 2: the display and its windows |

`../Assets.xcassets/AppIcon.appiconset` holds PNGs rendered from the two `winmux-icon*` SVGs.
Re-render them with a renderer that supports SVG filters (for example WebKit) after
changing the artwork.

Not yet done: an Icon Composer `.icon` for macOS 26 appearances, and replacing the
circular-arc `rx=185` body with Apple's template silhouette.
