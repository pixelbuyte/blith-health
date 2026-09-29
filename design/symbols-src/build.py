"""Build Blith v4 symbols: writes Assets.xcassets/Symbols/<name>.imageset/<name>.svg and design/symbols-preview.html.

    pip install shapely && python3 design/symbols-src/build.py
Render the preview PNG with any headless browser (the PNG in the repo was made with Playwright/Chromium at 2240 px wide).
"""
import os, json
from glyphs import G, TABS, METRICS, INSIGHT

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SYM = os.path.join(ROOT, 'ios/Blith/Resources/Assets.xcassets/Symbols')
CONTENTS = {"images": [{"filename": None, "idiom": "universal"}], "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"}}

def variants():
    for n in TABS + METRICS + INSIGHT:
        yield n, G[n](False)
        if n in TABS:
            yield n + '.fill', G[n](True)

def write_assets():
    names = []
    for name, g in variants():
        d = os.path.join(SYM, f'{name}.imageset'); os.makedirs(d, exist_ok=True)
        open(os.path.join(d, f'{name}.svg'), 'w').write(g.svg('#000000') + '\n')
        cj = os.path.join(d, 'Contents.json')
        if not os.path.exists(cj):
            c = json.loads(json.dumps(CONTENTS)); c['images'][0]['filename'] = f'{name}.svg'
            open(cj, 'w').write(json.dumps(c, indent=2) + '\n')
        names.append(name)
    return names

TAB_BAR = [('bl.today', 'Today'), ('bl.activity', 'Activity'), ('bl.sleep', 'Sleep'), ('bl.body', 'Body'), ('bl.ask', 'Ask')]
SECTIONS = [('Tabs', 'outline at rest, .fill when selected', TABS), ('Metrics', 'one glyph per signal', METRICS),
            ('Insight & interface', 'cards, eyebrows, rows', INSIGHT)]

def cell(name, g):
    return (f'<div class="cell"><div class="g">{g.svg("currentColor", 36)}{g.svg("currentColor", 22)}{g.svg("currentColor", 17)}</div>'
            f'<div class="nm">{name.replace(".fill", "<span>.fill</span>")}</div></div>')

def panel(theme):
    tabs = ''.join(f'<div class="ti{" sel" if i == 0 else ""}">{G[n](i == 0).svg("currentColor", 25)}<span>{t}</span></div>'
                   for i, (n, t) in enumerate(TAB_BAR))
    secs = ''
    for title, sub, names in SECTIONS:
        cells = ''
        count = 0
        for n in names:
            cells += cell(n, G[n](False)); count += 1
            if n in TABS: cells += cell(n + '.fill', G[n](True)); count += 1
        secs += f'<section><header><h2>{title}</h2><p>{sub}</p><b>{count}</b></header><div class="grid">{cells}</div></section>'
    label = 'Dark' if theme == 'dark' else 'Light'
    return f'<div class="panel {theme}"><div class="ph"><div class="eb">{label}</div><div class="tabbar">{tabs}</div></div>{secs}</div>'

def write_preview(path):
    total = sum(1 for _ in variants())
    html = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Blith Symbols v4</title>
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600&family=Geist+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
* {{ box-sizing:border-box; }}
body {{ margin:0; background:#05070A; color:#F4F6FA; width:2240px; font:14px/1.4 Geist, -apple-system, "Helvetica Neue", sans-serif; }}
.top {{ display:flex; align-items:flex-end; justify-content:space-between; padding:48px 48px 32px; }}
.eb {{ font:500 12px/1 "Geist Mono", ui-monospace, Menlo, monospace; letter-spacing:.16em; text-transform:uppercase; color:#55D8E8; }}
h1 {{ font-weight:500; font-size:40px; letter-spacing:-.02em; margin:12px 0 0; }}
.spec {{ font:400 13px/1.7 "Geist Mono", ui-monospace, Menlo, monospace; color:#7C8594; text-align:right; }}
.panels {{ display:flex; gap:0; }}
.panel {{ width:1120px; padding:36px 48px 48px; }}
.panel.dark {{ --bg:#080B10; --surface:#0F131A; --hair:rgba(255,255,255,.08); --ink:#F4F6FA; --dim:#A7AFBC; --faint:#7C8594; --sig:#4F8EFF; --glass:rgba(22,27,36,.72); background:var(--bg); }}
.panel.light {{ --bg:#F2F4F7; --surface:#FFFFFF; --hair:rgba(11,18,32,.09); --ink:#0B1220; --dim:#48505F; --faint:#6A7282; --sig:#2563EB; --glass:rgba(255,255,255,.8); background:var(--bg); color:var(--ink); }}
.panel .eb {{ color:var(--faint); }}
.ph {{ display:flex; align-items:center; justify-content:space-between; margin-bottom:8px; }}
.tabbar {{ display:flex; gap:4px; background:var(--glass); border:1px solid var(--hair); border-radius:32px; padding:8px 12px; box-shadow:0 10px 30px rgba(0,0,0,.18); }}
.ti {{ width:78px; display:flex; flex-direction:column; align-items:center; gap:4px; color:var(--ink); font:500 11px Geist, sans-serif; padding:6px 0; border-radius:22px; }}
.ti.sel {{ color:var(--sig); background:var(--hair); }}
section {{ margin-top:28px; }}
header {{ display:flex; align-items:baseline; gap:12px; margin-bottom:12px; }}
h2 {{ margin:0; font:500 12px/1 "Geist Mono", ui-monospace, monospace; letter-spacing:.14em; text-transform:uppercase; color:var(--ink); }}
header p {{ margin:0; color:var(--dim); font-size:13px; }}
header b {{ margin-left:auto; font:400 12px "Geist Mono", monospace; color:var(--faint); }}
.grid {{ display:grid; grid-template-columns:repeat(6, 1fr); gap:8px; }}
.cell {{ background:var(--surface); border:1px solid var(--hair); border-radius:14px; padding:16px 16px 12px; color:var(--ink); }}
.g {{ display:flex; align-items:center; gap:18px; height:40px; }}
.nm {{ margin-top:12px; font:400 12px "Geist Mono", ui-monospace, monospace; color:var(--dim); white-space:nowrap; }}
.nm span {{ color:var(--faint); }}
svg {{ display:block; flex:none; }}
</style></head>
<body>
<div class="top"><div><div class="eb">Blith / symbols / v4 Signal</div><h1>Instrument glyphs</h1></div>
<div class="spec">24 &times; 24 grid &middot; 1.75 stroke &middot; round caps + joins &middot; keylines: circle r9, square 17 r3<br>
template SVG &middot; {total} glyphs &middot; shown at 36, 22 and 17 px</div></div>
<div class="panels">{panel('dark')}{panel('light')}</div>
</body></html>
'''
    open(path, 'w').write(html)

if __name__ == '__main__':
    names = write_assets()
    write_preview(os.path.join(ROOT, 'design/symbols-preview.html'))
    print(len(names), 'glyphs')
