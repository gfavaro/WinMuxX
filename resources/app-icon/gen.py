# Generates the WinMuxX app icon sources. Run from this directory: python3 gen.py
# Round 3: a tiled workspace (five logo windows in one carrier) lifted from its origin.
INK = "#151A1D"
CW, CH = 600, 470            # carrier (workspace) size
ORIGIN = (172, 334)          # where the workspace was
MOVED = (252, 226)           # where it is going: +80, -108
TILT = -5

def windows(gutter, bar, small=False):
    # Tiled layout inside the carrier: tall left, two stacked middle, two stacked right.
    g = gutter; iw, ih = CW - 2*g, CH - 2*g
    # Small sizes give the narrow right column more room so five panes survive at 16/32 px.
    c1 = round(iw*(0.33 if small else 0.36)); c2 = round(iw*(0.30 if small else 0.34)); c3 = iw - c1 - c2 - 2*g
    h2 = (ih - g)//2
    cells = [
        (g, g, c1, ih, "#4CC9F0"),
        (g+c1+g, g, c2, h2, "#FFB703"),
        (g+c1+g, g+h2+g, c2, ih-h2-g, "#80ED99"),
        (g+c1+g+c2+g, g, c3, h2+20, "#F72585"),
        (g+c1+g+c2+g, g+h2+g+20, c3, ih-h2-g-20, "#C77DFF"),
    ]
    out = []
    for i,(x,y,w,h,col) in enumerate(cells):
        out.append(f'<clipPath id="w{i}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="30"/></clipPath>')
    defs = "".join(out); body = []
    for i,(x,y,w,h,col) in enumerate(cells):
        band = f'<rect x="{x}" y="{y}" width="{w}" height="{bar}" fill="#000" fill-opacity="0.18"/>' if bar else ""
        body.append(f'<g clip-path="url(#w{i})"><rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{col}"/>{band}</g>')
    return defs, "".join(body)

def origin_shape(small, opacity):
    ox, oy = ORIGIN; tilt = 0 if small else TILT
    return (f'<rect x="{ox}" y="{oy}" width="{CW}" height="{CH}" rx="64" transform="rotate({tilt} {ox+CW/2} {oy+CH/2})" '
            f'fill="#FFFFFF" fill-opacity="{opacity}" stroke="#FFFFFF" stroke-opacity="{opacity+0.08}" stroke-width="{10 if small else 6}"/>')

def foreground(small, effects=True):
    gutter = 26 if small else 18
    wdefs, wbody = windows(gutter, 0 if small else 40, small)
    tilt = 0 if small else TILT
    shadow = ' filter="url(#lift)"' if effects else ""
    ox, oy = ORIGIN; mx, my = MOVED
    origin_op = 0.20 if small else 0.13
    return wdefs, f'''
    {origin_shape(small, origin_op)}
    <g transform="translate({mx} {my}) rotate({tilt} {CW/2} {CH/2})"{shadow}>
      <rect width="{CW}" height="{CH}" rx="64" fill="{INK}"/>
      {wbody}
    </g>'''

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
    <rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>{fg}
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

# Opacity of the origin is set in Composer, so the layer is exported opaque.
open("composer-origin.svg","w").write(composer_layer(origin_shape(False, 1.0).replace('stroke-opacity="1.08"', 'stroke-opacity="1"')))
wdefs, wbody = windows(18, 40)
mx, my = MOVED
open("composer-workspace.svg","w").write(composer_layer(
    f'<g transform="translate({mx} {my}) rotate({TILT} {CW/2} {CH/2})"><rect width="{CW}" height="{CH}" rx="64" fill="{INK}"/>{wbody}</g>', wdefs))
