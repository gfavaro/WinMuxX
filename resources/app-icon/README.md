# App icon sources

`gen.py` generates every SVG here; edit it rather than the SVGs and run `python3 gen.py`.
The icon shows a tiled workspace (the five menu-bar colours) lifted from a matching
origin silhouette, because WinMuxX moves whole workspaces between displays.

| File | Use |
|---|---|
| `winmux-icon.svg` | App icon at 64 px and larger: 824 px body on the 1024 px macOS grid |
| `winmux-icon-small.svg` | 16 and 32 pt slots at 1x and 2x: untilted, no title bars, wider gutters |
| `composer-background.svg` | Icon Composer layer 1: opaque full-bleed background |
| `composer-origin.svg` | Icon Composer layer 2: origin silhouette, exported opaque; set about 15% opacity in Composer |
| `composer-workspace.svg` | Icon Composer layer 3: the workspace |

`../Assets.xcassets/AppIcon.appiconset` holds PNGs rendered from the two `winmux-icon*` SVGs.
Re-render them with a renderer that supports SVG filters (for example WebKit) after
changing the artwork.

Not yet done: an Icon Composer `.icon` for macOS 26 appearances, and replacing the
circular-arc `rx=185` body with Apple's template silhouette.
