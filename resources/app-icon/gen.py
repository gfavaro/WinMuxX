# Generates the WinMuxX app icon sources. Run from this directory: python3 gen.py
# Round 4: a display showing the sidebar and a Dwindle layout of real-looking windows.
INK = "#151A1D"
DX, DY, DW, DH = 160, 228, 704, 568   # display, on the 1024 grid
COLOURS = ["#4CC9F0", "#FFB703", "#80ED99", "#F72585", "#C77DFF"]

def layout(g, rail):
    # Sidebar rail, then Dwindle: tall left window, top-right window, bottom-right split in two.
    x0 = g + rail + g; w = DW - x0 - g; h = DH - 2*g
    w1 = (w - g)//2; xr = x0 + w1 + g; wr = w - w1 - g
    h2 = (h - g)//2; yb = g + h2 + g; hb = h - h2 - g
    w3 = (wr - g)//2
    return [
        (x0, g, w1, h, COLOURS[0]),
        (xr, g, wr, h2, COLOURS[1]),
        (xr, yb, w3, hb, COLOURS[2]),
        (xr + w3 + g, yb, wr - w3 - g, hb, COLOURS[3]),
    ]

def window(i, x, y, w, h, col, small):
    r = 34 if small else 26
    clip = f'<clipPath id="w{i}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/></clipPath>'
    body = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{col}"/>']
    if not small:
        bar = 46
        body.append(f'<rect x="{x}" y="{y}" width="{w}" height="{bar}" fill="#000" fill-opacity="0.20"/>')
        for k in range(3):
            body.append(f'<circle cx="{x+26+k*22}" cy="{y+bar/2}" r="7" fill="#FFF" fill-opacity="0.85"/>')
        # Content lines: shorter on narrow windows, as many as the height allows.
        ly = y + bar + 26
        widths = [0.72, 0.52, 0.64, 0.40, 0.58, 0.46]
        n = 0
        while ly + 14 <= y + h - 22 and n < len(widths):
            body.append(f'<rect x="{x+22}" y="{ly}" width="{round((w-44)*widths[n])}" height="14" rx="7" fill="#FFF" fill-opacity="0.45"/>')
            ly += 32; n += 1
    return clip, f'<g clip-path="url(#w{i})">{"".join(body)}</g>'

def sidebar(g, rail, small):
    out = [f'<rect x="{g}" y="{g}" width="{rail}" height="{DH-2*g}" rx="{rail/2 if small else 22}" fill="#FFF" fill-opacity="0.12"/>']
    if not small:
        cx = g + rail/2
        out.append(f'<rect x="{cx-18}" y="{g+30}" width="36" height="14" rx="7" fill="{COLOURS[0]}"/>')
        for k, col in enumerate(COLOURS[1:]):
            out.append(f'<circle cx="{cx}" cy="{g+78+k*38}" r="8" fill="{col}" fill-opacity="0.85"/>')
    return "".join(out)

def display(small):
    g = 26 if small else 16
    rail = 64 if small else 60
    defs, body = [], []
    for i, cell in enumerate(layout(g, rail)):
        d, b = window(i, *cell, small)
        defs.append(d); body.append(b)
    content = f'<rect width="{DW}" height="{DH}" rx="{64 if small else 56}" fill="{INK}"/>{sidebar(g, rail, small)}{"".join(body)}'
    return "".join(defs), content

def foreground(small, effects=True):
    defs, content = display(small)
    shadow = ' filter="url(#lift)"' if effects else ""
    return defs, f'<g transform="translate({DX} {DY})"{shadow}>{content}</g>'

def legacy(small):
    rim = 8 if small else 4
    wdefs, fg = foreground(small)
    return f'''<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="512" y1="100" x2="512" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#46536B"/><stop offset="1" stop-color="#181D29"/></linearGradient>
    <radialGradient id="glow" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(330 200) scale(620)">
      <stop offset="0" stop-color="#FFF" stop-opacity="0.12"/><stop offset="1" stop-color="#FFF" stop-opacity="0"/></radialGradient>
    <linearGradient id="rim" x1="512" y1="100" x2="512" y2="924" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFF" stop-opacity="0.42"/><stop offset="0.5" stop-color="#FFF" stop-opacity="0.14"/><stop offset="1" stop-color="#FFF" stop-opacity="0.10"/></linearGradient>
    <filter id="icon" x="40" y="60" width="944" height="944" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">
      <feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#000" flood-opacity="0.32"/></filter>
    <filter id="lift" x="-20%" y="-20%" width="140%" height="150%" color-interpolation-filters="sRGB">
      <feDropShadow dx="0" dy="16" stdDeviation="14" flood-color="#05070A" flood-opacity="0.35"/></filter>
    <clipPath id="body"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
    {wdefs}
  </defs>
  <g filter="url(#icon)"><rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/></g>
  <g clip-path="url(#body)">
    <rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>
    {fg}
  </g>
  <!-- Rim stroke kept inside the body: inset by half the stroke width. -->
  <rect x="{100+rim/2}" y="{100+rim/2}" width="{824-rim}" height="{824-rim}" rx="{185-rim/2}" stroke="url(#rim)" stroke-width="{rim}"/>
</svg>
'''

def composer_background():
    return '''<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs><linearGradient id="bg" x1="512" y1="0" x2="512" y2="1024" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#46536B"/><stop offset="1" stop-color="#181D29"/></linearGradient></defs>
  <rect width="1024" height="1024" fill="url(#bg)"/>
</svg>
'''

open("winmux-icon.svg","w").write(legacy(False))
open("winmux-icon-small.svg","w").write(legacy(True))
open("composer-background.svg","w").write(composer_background())

def composer_layer(content, defs=""):
    s = 1024/824
    return (f'<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">'
            f'<defs>{defs}</defs><g transform="scale({s:.5f}) translate(-100 -100)">{content}</g></svg>\n')

wdefs, fg = foreground(False, effects=False)
open("composer-display.svg","w").write(composer_layer(fg, wdefs))
