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

The target builds `winmux-marketing-renderer` and writes:

| Output | Content | Typical use |
|---|---|---|
| `collage.png` (3200×1800) | Desktop with the sidebar, tabbed editor and Safari windows, Finder and the "Your workspace, in flow." card | Site hero `site/assets/overview.jpg` (resize to 1920×1080, JPEG), social preview |
| `safari-tabs.png` | One Safari window with WinMuxX tabs | Tabs feature pictures |
| `tiled-apps.png` | Helium, Ghostty and Finder tiled together | Layout pictures |
| `safari-plasticity.png` | Safari and Plasticity tiled with tabs | Layout and tabs pictures |
| `sidebar/*.png` | The sidebar in 14 appearances (light/dark, expanded/collapsed, reduced transparency, increased contrast, custom, no background, wallpaper samples) | Appearance docs, Settings review |

Review the images before copying any of them into `site/` or `resources/`.
`.release/` is gitignored.

## How it works

- Code: `Sources/MarketingRenderer/` (`main.swift` selects the mode with
  `--safari-proof`, `--apps-proof`, `--safari-plasticity-proof` or
  `--sidebar-appearance-proof`; no flag renders the collage).
- It is a separate executable: nothing in it ships in WinMuxX.app. It uses
  `@testable import AppBundle` to draw the real `WorkspaceSidebarView` and tab
  strip, so it only builds in debug, the default for `swift build`.
- Workspaces, tabs and window titles are fixed in `MarketingFixtures`; edit them
  there to change what the pictures show.
- Other apps' windows and the wallpaper are saved screenshots in
  `resources/marketing/captures/`, loaded relative to the repository root. The
  Xcode app build excludes `resources/marketing`.
- Each scene briefly opens a borderless window in the centre of the main display
  (about a second), so Liquid Glass is composed by WindowServer. The PNG contains
  only the renderer's own windows, never the desktop or other apps. Run it in a
  logged-in session and leave the screen alone while it runs.

## Refresh a captured app window

When an app's look changes, recapture its window with the capture tool, then
re-render:

```sh
swift build --product winmux-window-capture
"$(swift build --show-bin-path)/winmux-window-capture" \
  resources/marketing/captures/safari-current-retina.png com.apple.Safari \
  [title-filter] [--url <url>] [--settle-ms 1500] [--core-graphics]
```

It needs Screen Recording permission for the terminal and captures one window of
the given bundle ID.

## Publish

- **Site:** `site/index.html` and `site/assets/`. Pushing changes under `site/`
  to `main` deploys GitHub Pages (`.github/workflows/pages.yml`). Keep the hero at
  `assets/overview.jpg` because `og:image` points to it. Bump a `?v=` query when
  replacing a cached file.
- **README:** pictures live in `resources/screenshots/`.
- Remove superseded variants instead of adding numbered copies; keep
  `resources/marketing/` limited to captures and current outputs.
