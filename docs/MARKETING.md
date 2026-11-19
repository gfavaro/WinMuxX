# Marketing images, site and README pictures

Use this guide when updating the product site (GitHub Pages), README pictures, the
social preview or any promotional image. Pictures of WinMuxX itself come from the
marketing renderer, not from screen recordings, so they always show the current
sidebar and tab strip.

## Render

```sh
make marketing-images                 # writes .release/marketing/
make marketing-images MARKETING_DIR=/tmp/shots
```

The target builds `winmux-marketing-renderer` and writes one 3200×1800 PNG per scene
(`ultrawide.png` is 3200×1280):

| Output | Content | Typical use |
|---|---|---|
| `overview.png` | Expanded sidebar beside a Dwindle workspace: an editor tab group with its tab bar, a browser and notes | Site hero `site/assets/overview.jpg` (resize to 1920×1080, JPEG), README, social preview |
| `dwindle.png` | Four windows split by Dwindle beside the collapsed sidebar | Layout pictures |
| `tabbed.png` | A Tabbed workspace: its bar of window tabs above one window | Tabbed pictures |
| `scrolling.png` | A Scrolling workspace whose columns run past both display edges | Scrolling pictures |
| `ultrawide.png` | One window at a comfortable width in the middle of an ultrawide display | Lone-window pictures |
| `sidebar/*.png` | The sidebar in 14 appearances (light/dark, expanded/collapsed, reduced transparency, increased contrast, custom, no background, wallpaper samples) | Appearance docs, Settings review |

Render one scene with `winmux-marketing-renderer --scene <name> <file.png>`. Review
the images before copying any of them into `site/`. `.release/` is gitignored.

## How it works

- Code: `Sources/MarketingRenderer/`. `MarketingScenes.swift` lays out each scene,
  `MarketingWindows.swift` draws the app windows, the desktop and the menu bar, and
  `MarketingFixtures.swift` holds the projects, workspaces, tabs and titles.
- It is a separate executable: nothing in it ships in WinMuxX.app. It uses
  `@testable import AppBundle` to draw the real `WorkspaceSidebarView`, tab bar and
  tab group frame, so it only builds in debug, the default for `swift build`.
- App windows (editor, browser, notes, terminal) and the desktop are drawn in code
  with made-up content. Nothing is captured from other apps, websites or anyone's
  documents, so the pictures need no Screen Recording permission and come out the
  same on every run.
- Each scene briefly opens a borderless window in the centre of the main display
  (about a second), so Liquid Glass is composed by WindowServer. The PNG contains
  only the renderer's own windows, never the desktop or other apps. Run it in a
  logged-in session and leave the screen alone while it runs.

## Publish

- **Site:** `site/index.html` and `site/assets/`. Pushing changes under `site/`
  to `main` deploys GitHub Pages (`.github/workflows/pages.yml`). Keep the hero at
  `assets/overview.jpg` because `og:image` points to it. Bump a `?v=` query when
  replacing a cached file.
- **README:** the top picture is the site hero, `site/assets/overview.jpg`.
- Remove superseded variants instead of adding numbered copies.
