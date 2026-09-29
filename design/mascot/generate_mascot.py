#!/usr/bin/env python3
"""Blith mascot model sheet ("Bli"). Mirrors the geometry in ios/Blith/DesignSystem/Mascot.swift
exactly (120 × 140 design box), so the sheet is the reference for the animated SwiftUI rig.

    python3 design/mascot/generate_mascot.py   # writes model-sheet.html next to this file
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

BODY = "M60,36 C86,36 100,58 100,84 C100,108 84,124 60,124 C36,124 20,108 20,84 C20,58 34,36 60,36 Z"
CURL = "M60,38 C57,27 63,17 76,14 C74,23 69,32 60,38 Z"
COLORS = dict(top="#5B8CFF", bottom="#2447E8", limb="#2146DD", foot="#1A34B0", ink="#0B1230",
              cyan="#3FD0FF", coral="#FF8A7A", amber="#FFB23F", belly="#8FB8FF")
SHOULDER = {"left": (24, 90), "right": (96, 90)}
HIP = {"left": (47, 118), "right": (73, 118)}

# angle 0 = hanging down; positive = outward/up away from the body.
POSES = {
    "idle":        dict(arms=(18, 18), legs=(0, 0), eyes="open"),
    "waving":      dict(arms=(18, 150), legs=(0, 0), eyes="open"),
    "walking":     dict(arms=(-22, 26), legs=(20, -16), eyes="open", bob=-2),
    "thinking":    dict(arms=(14, -150), legs=(0, 0), eyes="up", extra="dots"),
    "listening":   dict(arms=(14, 14), legs=(0, 0), eyes="side", tilt=-8, extra="waves"),
    "sleeping":    dict(arms=(6, 6), legs=(0, 0), eyes="closed", squash=0.96, extra="z"),
    "noticing":    dict(arms=(18, 60), legs=(0, 0), eyes="wide", extra="spark"),
    "celebrating": dict(arms=(150, 150), legs=(8, 8), eyes="happy", extra="confetti", bob=-4),
    "pointing":    dict(arms=(16, 92), legs=(0, 0), eyes="right"),
}


def limb(pivot, angle, side, length, width, color):
    a = math.radians(angle)
    dx = math.sin(a) * (1 if side == "right" else -1)
    dy = math.cos(a)
    x2, y2 = pivot[0] + dx * length, pivot[1] + dy * length
    return (f'<line x1="{pivot[0]}" y1="{pivot[1]}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{color}" '
            f'stroke-width="{width}" stroke-linecap="round"/>')


def eyes(kind):
    c = COLORS
    out = []
    for x in (47, 73):
        if kind == "closed":
            out.append(f'<path d="M{x - 5},77 Q{x},81 {x + 5},77" stroke="{c["ink"]}" stroke-width="2.4" fill="none" stroke-linecap="round"/>')
        elif kind == "happy":
            out.append(f'<path d="M{x - 5},79 Q{x},72 {x + 5},79" stroke="{c["ink"]}" stroke-width="2.6" fill="none" stroke-linecap="round"/>')
        else:
            ry = 8.5 if kind == "wide" else 7
            gx, gy = {"up": (0.8, -4.2), "side": (-1.6, -2.4), "right": (2.6, -2.2)}.get(kind, (1.6, -2.6))
            out.append(f'<ellipse cx="{x}" cy="76" rx="5.5" ry="{ry}" fill="{c["ink"]}"/>')
            out.append(f'<circle cx="{x + gx}" cy="{76 + gy}" r="1.9" fill="#FFFFFF"/>')
    return "".join(out)


def extra(kind):
    c = COLORS
    if kind == "dots":
        return "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c["cyan"]}"/>' for x, y, r in [(98, 40, 2.5), (106, 30, 3.2), (112, 18, 4)])
    if kind == "waves":
        return (f'<path d="M104,70 Q110,78 104,86" stroke="{c["cyan"]}" stroke-width="2.4" fill="none" stroke-linecap="round"/>'
                f'<path d="M110,64 Q119,78 110,92" stroke="{c["cyan"]}" stroke-width="2.4" fill="none" stroke-linecap="round" opacity="0.6"/>')
    if kind == "z":
        return (f'<text x="96" y="44" font-family="SF Pro Rounded, Arial Rounded MT Bold, sans-serif" font-weight="700" font-size="14" fill="{c["cyan"]}">z</text>'
                f'<text x="106" y="30" font-family="SF Pro Rounded, Arial Rounded MT Bold, sans-serif" font-weight="700" font-size="10" fill="{c["cyan"]}" opacity="0.7">z</text>')
    if kind == "spark":
        return f'<path d="M100,30 L103,38 L111,41 L103,44 L100,52 L97,44 L89,41 L97,38 Z" fill="{c["amber"]}"/>'
    if kind == "confetti":
        pts = [(18, 34, c["cyan"]), (104, 30, c["coral"]), (12, 60, c["amber"]), (110, 58, c["cyan"]), (30, 22, c["amber"]), (90, 18, c["top"])]
        return "".join(f'<rect x="{x}" y="{y}" width="5" height="5" rx="1.5" fill="{col}" transform="rotate(25 {x} {y})"/>' for x, y, col in pts)
    return ""


def mascot(pose):
    p = POSES[pose]
    c = COLORS
    la, ra = p["arms"]
    ll, rl = p["legs"]
    bob = p.get("bob", 0)
    tilt = p.get("tilt", 0)
    squash = p.get("squash", 1)
    body = f"""
  <g transform="translate(0 {bob}) rotate({tilt} 60 124) translate(60 124) scale(1 {squash}) translate(-60 -124)">
    {limb(HIP['left'], ll, 'left', 13, 12, c['foot'])}{limb(HIP['right'], rl, 'right', 13, 12, c['foot'])}
    {limb(SHOULDER['left'], la, 'left', 22, 10, c['limb']) if la >= 0 else ''}{limb(SHOULDER['right'], ra, 'right', 22, 10, c['limb']) if ra >= 0 else ''}
    <path d="{BODY}" fill="url(#g)"/>
    <ellipse cx="60" cy="100" rx="22" ry="17" fill="{c['belly']}" opacity="0.28"/>
    <ellipse cx="42" cy="54" rx="10" ry="5.5" fill="#FFFFFF" opacity="0.35" transform="rotate(-32 42 54)"/>
    <path d="{CURL}" fill="{c['cyan']}"/>
    <ellipse cx="37" cy="89" rx="5" ry="3" fill="{c['coral']}" opacity="0.5"/>
    <ellipse cx="83" cy="89" rx="5" ry="3" fill="{c['coral']}" opacity="0.5"/>
    {eyes(p['eyes'])}
    {'' if p['eyes'] in ('closed',) else f'<path d="M54,91 Q60,97 66,91" stroke="{c["ink"]}" stroke-width="2.4" fill="none" stroke-linecap="round"/>'}
    {'<ellipse cx="60" cy="93" rx="2.4" ry="1.6" fill="' + c['ink'] + '"/>' if p['eyes'] == 'closed' else ''}
    {limb(SHOULDER['left'], la, 'left', 22, 10, c['limb']) if la < 0 else ''}{limb(SHOULDER['right'], ra, 'right', 22, 10, c['limb']) if ra < 0 else ''}
  </g>{extra(p.get('extra', ''))}"""
    return (f'<svg width="180" height="210" viewBox="0 0 120 140"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{c["top"]}"/><stop offset="1" stop-color="{c["bottom"]}"/></linearGradient></defs>{body}</svg>')


def main():
    cells = "".join(f'<div class="cell">{mascot(k)}<div>{k}</div></div>' for k in POSES)
    swatches = "".join(f'<div class="sw" style="background:{v}"><span>{k}<br>{v}</span></div>' for k, v in COLORS.items())
    html = f"""<html><head><style>
body{{margin:0;padding:28px;background:#F3F6FF;font-family:-apple-system,Helvetica,sans-serif;color:#0B1230}}
h1{{font-family:Georgia,serif;font-weight:600;margin:0 0 4px}} p{{margin:0 0 18px;color:#4A5580}}
.grid{{display:grid;grid-template-columns:repeat(5,190px);gap:14px}}
.cell{{background:#fff;border-radius:22px;padding:8px;text-align:center;font:600 12px ui-monospace,monospace;letter-spacing:1px;text-transform:uppercase;color:#4A5580}}
.dark .cell{{background:#0F1733;color:#9FB2E8}}
.sw{{width:110px;height:64px;border-radius:14px;display:inline-flex;align-items:flex-end;margin:10px 8px 0 0}}
.sw span{{font:600 10px ui-monospace,monospace;color:#fff;padding:6px;text-shadow:0 1px 2px #0006}}
</style></head><body>
<h1>Bli — model sheet</h1><p>One silhouette, one face. Proportions: 120 × 140 box, egg body 80 × 88, eyes at y 76, curl on the crown. Poses change limbs, eyes and props only.</p>
<div class="grid">{cells}</div>
<div class="grid dark" style="margin-top:14px;padding:14px;background:#060B1F;border-radius:26px">{cells}</div>
<div>{swatches}</div></body></html>"""
    with open(os.path.join(HERE, "model-sheet.html"), "w") as f:
        f.write(html)


if __name__ == "__main__":
    main()
