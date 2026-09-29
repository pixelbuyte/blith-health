"""Blith app icon v4 — concept + production generator.

Writes design/icon-concepts/*.svg (three concepts), design/app-icon{,-dark,-tinted}.svg (shipped: Horizon).
Rasterise with any SVG renderer at 1024 px; the shipped PNGs must be flattened to RGB (no alpha).
"""
import math, os

INK = '#080B10'; SIGNAL = '#4F8EFF'; BRIGHT = '#7DB2FF'; ICE = '#B9DAFF'; DEEP = '#1B3A8C'
HERE = os.path.dirname(os.path.abspath(__file__)); DESIGN = os.path.dirname(HERE)

def pal(variant):
    if variant == 'tinted':   # grayscale; iOS maps luminance to the user's tint
        return dict(bg='#000000', sig='#FFFFFF', bright='#E6E6E6', ice='#FFFFFF', deep='#FFFFFF', core='#FFFFFF', surf='#161616', surf2='#000000', atm=.35)
    if variant == 'dark':     # pure black field for the iOS dark home screen
        return dict(bg='#000000', sig=SIGNAL, bright=BRIGHT, ice=ICE, deep=DEEP, core='#F4F8FF', surf='#121A2A', surf2='#000000', atm=.85)
    return dict(bg=INK, sig=SIGNAL, bright=BRIGHT, ice=ICE, deep=DEEP, core='#F4F8FF', surf='#141D2F', surf2=INK, atm=1.0)

def wrap(body, defs, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
            f'  <title>{title}</title>\n  <defs>{defs}\n  </defs>\n{body}\n</svg>\n')

def horizon(variant='any', r=440, top=500, t=56, bw=84, sky=.45, band=(.46, .22), edge=.5):
    """Signal emerging from darkness: the lit edge of a body (crisp crescent = the line),
    wrapped in its usual range (translucent band with a crisp outer edge)."""
    p = pal(variant); cx = 512; cy = top + r
    defs = f'''
    <radialGradient id="sky" cx="{cx}" cy="{top}" r="600" gradientUnits="userSpaceOnUse" gradientTransform="translate({cx} {top}) scale(1.2 .75) translate({-cx} {-top})">
      <stop offset="0" stop-color="{p['deep']}" stop-opacity="{sky*p['atm']:.2f}"/><stop offset=".5" stop-color="{p['deep']}" stop-opacity="{sky*.3*p['atm']:.2f}"/><stop offset="1" stop-color="{p['deep']}" stop-opacity="0"/></radialGradient>
    <radialGradient id="band" cx="{cx}" cy="{cy}" r="{r+bw}" gradientUnits="userSpaceOnUse">
      <stop offset="{r/(r+bw):.4f}" stop-color="{p['sig']}" stop-opacity="{band[0]}"/><stop offset="1" stop-color="{p['sig']}" stop-opacity="{band[1]}"/></radialGradient>
    <linearGradient id="arcfade" x1="0" y1="{top-bw}" x2="0" y2="{cy}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#fff"/><stop offset=".34" stop-color="#fff" stop-opacity=".85"/><stop offset=".78" stop-color="#fff" stop-opacity=".12"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
    <mask id="fade" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="url(#arcfade)"/></mask>
    <linearGradient id="body" x1="0" y1="{top}" x2="0" y2="{top+360}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{p['surf']}"/><stop offset="1" stop-color="{p['surf2']}"/></linearGradient>
    <linearGradient id="rim" x1="0" y1="{top}" x2="0" y2="{top+280}" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{p['core']}"/><stop offset=".5" stop-color="{p['bright']}"/><stop offset="1" stop-color="{p['sig']}"/></linearGradient>'''
    body = f'''  <rect width="1024" height="1024" fill="{p['bg']}"/>
  <rect width="1024" height="1024" fill="url(#sky)"/>
  <g mask="url(#fade)">
    <circle cx="{cx}" cy="{cy}" r="{r+bw}" fill="url(#band)"/>
    <circle cx="{cx}" cy="{cy}" r="{r+bw-3}" fill="none" stroke="{p['ice']}" stroke-opacity="{edge}" stroke-width="6"/>
  </g>
  <circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#body)"/>
  <g mask="url(#fade)">
    <path d="M{cx-r},{cy} A{r},{r} 0 0 1 {cx+r},{cy} L{cx+r},{cy+t} A{r},{r} 0 0 0 {cx-r},{cy+t} Z" fill="url(#rim)"/>
  </g>'''
    return wrap(body, defs, f'Blith app icon — Horizon ({variant})')

def baseline(variant='any'):
    """The person is the baseline: one breath of signal held inside the usual range."""
    p = pal(variant); y0 = 512; A = 64; x0, x1 = 244, 780
    pts = [(x0 + (x1 - x0) * i / 160, y0 - A * math.sin(2 * math.pi * i / 160)) for i in range(161)]
    d = 'M' + ' L'.join(f'{x:.1f},{y:.1f}' for x, y in pts)
    defs = f'''
    <radialGradient id="atm" cx="512" cy="512" r="600" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{p['deep']}" stop-opacity="{.42*p['atm']:.2f}"/><stop offset="1" stop-color="{p['deep']}" stop-opacity="0"/></radialGradient>
    <linearGradient id="band" x1="0" y1="0" x2="1024" y2="0" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{p['sig']}" stop-opacity="0"/><stop offset=".2" stop-color="{p['sig']}" stop-opacity=".2"/><stop offset=".8" stop-color="{p['sig']}" stop-opacity=".2"/><stop offset="1" stop-color="{p['sig']}" stop-opacity="0"/></linearGradient>
    <linearGradient id="edge" x1="0" y1="0" x2="1024" y2="0" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{p['ice']}" stop-opacity="0"/><stop offset=".25" stop-color="{p['ice']}" stop-opacity=".3"/><stop offset=".75" stop-color="{p['ice']}" stop-opacity=".3"/><stop offset="1" stop-color="{p['ice']}" stop-opacity="0"/></linearGradient>
    <linearGradient id="ln" x1="{x0}" y1="0" x2="{x1}" y2="0" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{p['sig']}"/><stop offset=".55" stop-color="{p['bright']}"/><stop offset="1" stop-color="{p['core']}"/></linearGradient>'''
    body = f'''  <rect width="1024" height="1024" fill="{p['bg']}"/><rect width="1024" height="1024" fill="url(#atm)"/>
  <rect x="0" y="{y0-116}" width="1024" height="232" fill="url(#band)"/>
  <rect x="0" y="{y0-118}" width="1024" height="4" fill="url(#edge)"/><rect x="0" y="{y0+114}" width="1024" height="4" fill="url(#edge)"/>
  <path d="{d}" fill="none" stroke="url(#ln)" stroke-width="50" stroke-linecap="round" stroke-linejoin="round"/>'''
    return wrap(body, defs, f'Blith app icon concept — Baseline ({variant})')

def monogram(variant='any'):
    """A precise instrument mark: a monoline b whose bowl is the usual-range band with its line."""
    p = pal(variant); w = 36; top = 222; bcx, bcy, br = 552, 592, 184; sx = bcx - br
    defs = f'''
    <radialGradient id="atm" cx="{bcx}" cy="{bcy}" r="600" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{p['deep']}" stop-opacity="{.42*p['atm']:.2f}"/><stop offset="1" stop-color="{p['deep']}" stop-opacity="0"/></radialGradient>'''
    body = f'''  <rect width="1024" height="1024" fill="{p['bg']}"/><rect width="1024" height="1024" fill="url(#atm)"/>
  <circle cx="{bcx}" cy="{bcy}" r="{br}" fill="none" stroke="{p['sig']}" stroke-opacity=".34" stroke-width="124"/>
  <circle cx="{bcx}" cy="{bcy}" r="{br}" fill="none" stroke="{p['core']}" stroke-width="{w}"/>
  <line x1="{sx}" y1="{top}" x2="{sx}" y2="{bcy}" stroke="{p['core']}" stroke-width="{w}" stroke-linecap="round"/>'''
    return wrap(body, defs, f'Blith app icon concept — Monogram ({variant})')

CONCEPTS = [('horizon', 'Horizon', horizon), ('baseline', 'Baseline', baseline), ('monogram', 'Monogram', monogram)]

if __name__ == '__main__':
    for key, _, fn in CONCEPTS:
        open(os.path.join(HERE, f'{key}.svg'), 'w').write(fn('any'))
    for v, suffix in (('any', ''), ('dark', '-dark'), ('tinted', '-tinted')):
        open(os.path.join(DESIGN, f'app-icon{suffix}.svg'), 'w').write(horizon(v))
    print('ok')
