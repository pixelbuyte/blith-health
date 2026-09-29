"""Blith glyph set v4 — 24 pt grid, 1.75 stroke, round caps/joins, circle keyline r9, square keyline 3.5–20.5 r3."""
import math
from gl import *
from shapely.geometry import Point, Polygon

G = {}
def glyph(name):
    def deco(fn): G[name] = fn; return fn
    return deco

def disc(cx, cy, r): return Point(cx, cy).buffer(r, quad_segs=48)

# ------------------------------------------------------------------ tabs
@glyph('bl.today')
def today(fill=False):
    g = Glyph(); cx, by = 12, 17.4
    g.s(P((2.75, by), (21.25, by)))
    dome = Path().arc(cx, by, 6.9, 180, 360, move=True)
    if fill: g.fl(dome.Z())
    else: g.s(dome)
    g.s(Path().arc(cx, by, 10.3, 213, 327, move=True))
    return g

@glyph('bl.activity')
def activity(fill=False):
    g = Glyph(); bolt = P((13.5, 5.5), (9, 12), (15, 12), (10.5, 18.5))
    if fill:
        g.raw_fill(disc(12, 12, 9.875).difference(Glyph().s(bolt).geom()))
    else:
        g.circ(12, 12, 9); g.s(bolt)
    return g

@glyph('bl.walk')
def walk(fill=False):
    sw = 2.35 if fill else SW; g = Glyph(sw)
    if fill: g.dot(13.4, 4.1, 2.35)
    else: g.circ(13.4, 4.1, 1.95)
    g.s(P((12.85, 8.1), (11.45, 13.35)))
    g.s(P((9.1, 11.6), (12.55, 9.05), (15.6, 11.85)))
    g.s(P((7.2, 20.1), (9.9, 17.05), (11.45, 13.35), (13.8, 16.65), (14.6, 20.9)))
    return g

@glyph('bl.body')
def body(fill=False):
    g = Glyph()
    torso = P((8.4, 8.6), (15.6, 8.6), (14.4, 14.4), (9.6, 14.4), closed=True)
    if fill:
        g.dot(12, 4.2, 2.6); g.fl(torso); g.s(torso)
    else:
        g.circ(12, 4.2, 2.05); g.s(torso)
    g.s(P((8.4, 8.6), (5.4, 15.4))); g.s(P((15.6, 8.6), (18.6, 15.4)))
    g.s(P((10.3, 14.4), (9.7, 21))); g.s(P((13.7, 14.4), (14.3, 21)))
    return g

def crescent(cx=11, cy=13, r=8.25, bx=16.2, by=8.1, br=6.4):
    d = math.hypot(bx - cx, by - cy); a = math.atan2(by - cy, bx - cx)
    t = math.acos((r * r + d * d - br * br) / (2 * r * d))
    A = math.degrees(a - t); B = math.degrees(a + t)           # on outer circle
    pA = pol(cx, cy, r, A); pB = pol(cx, cy, r, B)
    aA = ang(bx, by, pA); aB = ang(bx, by, pB)
    # outer: from B the long way to A (increasing angle), inner: from A back to B around the bite circle (inside outer)
    p = Path().arc(cx, cy, r, B, A + 360, move=True)
    # bite arc from pA to pB passing through the point of the bite circle nearest the outer centre
    a1 = aA; a2 = aB
    while a2 > a1: a2 -= 360
    p.arc(bx, by, br, a1, a2)
    return p.Z()

@glyph('bl.sleep')
def sleep(fill=False):
    g = Glyph(); c = crescent()
    if fill: g.fl(c); g.s(c)
    else: g.s(c)
    g.fl(sparkle(18.6, 4.4, 2.55, .3))
    return g

def bubble():
    cx, cy, r = 12.6, 11.2, 8.4
    p = Path().arc(cx, cy, r, 152, 463, move=True)
    p.L(3.6, 20.4)
    return p.Z()

@glyph('bl.ask')
def ask(fill=False):
    g = Glyph(); b = bubble(); sp = sparkle(12.6, 11.2, 4.5, .27)
    if fill:
        base = Glyph().fl(bubble()).geom().union(Glyph().s(bubble()).geom())
        g.raw_fill(base.difference(Glyph().fl(sparkle(12.6, 11.2, 4.5, .27)).geom()))
    else:
        g.s(b); g.fl(sp)
    return g

# ------------------------------------------------------------------ metrics
@glyph('bl.readiness')
def readiness(fill=False):
    g = Glyph(); cx, cy, r = 12, 13.1, 8.9
    g.s(Path().arc(cx, cy, r, 145, 395, move=True))
    g.s(P((cx, cy), pol(cx, cy, 5.4, -52)))
    g.dot(cx, cy, 1.7)
    return g

@glyph('bl.load')
def load(fill=False):
    g = Glyph(); g.s(P((13.75, 2.75), (5.5, 13.25), (11.25, 13.25), (10.25, 21.25), (18.5, 10.75), (12.75, 10.75), closed=True))
    return g

@glyph('bl.hrv')
def hrv(fill=False):
    g = Glyph()
    g.s(P((2.75, 13.5), (5.5, 13.5), (7.4, 5.5), (9.3, 18.5), (10.6, 13.5), (13.9, 13.5), (15.8, 5.5), (17.7, 18.5), (19, 13.5), (21.25, 13.5)))
    return g

def heart_path(cx=12, cy=9.1, R=4.7, a=4.3, by=20.1, s=1.0):
    lc = (cx - a, cy); rc = (cx + a, cy); B = (cx, by)
    tl = circle_tangent(B[0], B[1], lc[0], lc[1], R, -1)
    tr = circle_tangent(B[0], B[1], rc[0], rc[1], +1 * 1, )if False else circle_tangent(B[0], B[1], rc[0], rc[1], R, +1)
    ny = cy - math.sqrt(R * R - a * a)
    p = Path().M(*B).L(*tl)
    a0 = ang(*lc, tl); a1 = ang(*lc, (cx, ny))
    while a1 < a0: a1 += 360
    p.arc(*lc, R, a0, a1)
    b0 = ang(*rc, (cx, ny)); b1 = ang(*rc, tr)
    while b1 < b0: b1 += 360
    p.arc(*rc, R, b0, b1)
    return p.Z()

@glyph('bl.heart')
def heart(fill=False):
    g = Glyph(); g.s(heart_path()); return g

@glyph('bl.rhr')
def rhr(fill=False):
    g = Glyph(); g.s(heart_path()); g.s(P((8.9, 11.6), (15.1, 11.6))); return g

def lobe(mirror=False):
    pts = lambda x, y: ((24 - x) if mirror else x, y)
    p = Path().M(*pts(9.9, 9.6)).V(17.6)
    p.Q(*pts(9.9, 20.1), *pts(7.5, 19.8)).L(*pts(5.9, 19.6))
    p.Q(*pts(3.7, 19.3), *pts(3.7, 17.0)).V(14.6)
    p.C(*pts(3.7, 10.6), *pts(5.5, 7.3), *pts(7.6, 7.3))
    p.Q(*pts(9.9, 7.3), *pts(9.9, 9.6))
    return p.Z()

@glyph('bl.resp')
def resp(fill=False):
    g = Glyph(); g.s(lobe()); g.s(lobe(True))
    g.s(P((12, 3.1), (12, 11.2))); g.s(P((9.9, 13.3), (12, 11.2), (14.1, 13.3)))
    return g

@glyph('bl.vo2')
def vo2(fill=False):
    g = Glyph(); g.s(lobe()); g.s(lobe(True))
    g.s(P((12, 14.6), (12, 3.4))); g.s(P((9.9, 5.5), (12, 3.4), (14.1, 5.5)))
    return g

@glyph('bl.spo2')
def spo2(fill=False):
    g = Glyph(); cx, cy, r, tip = 10.6, 14.3, 6.1, (10.6, 2.9)
    tr = circle_tangent(*tip, cx, cy, r, -1); tl = circle_tangent(*tip, cx, cy, r, +1)
    a0 = ang(cx, cy, tr); a1 = ang(cx, cy, tl)
    while a1 < a0: a1 += 360
    p = Path().M(*tip).L(*tr).arc(cx, cy, r, a0, a1).Z()
    g.s(p); g.circ(19.2, 19.1, 1.95)
    return g

@glyph('bl.temp')
def temp(fill=False):
    g = Glyph(); x0, x1, bc, br = 7.9, 12.1, 17.1, 3.85
    xc = (x0 + x1) / 2; hw = (x1 - x0) / 2
    yj = bc - math.sqrt(br * br - hw * hw)
    p = Path().M(x0, yj).V(5.0)
    p.arc(xc, 5.0, hw, 180, 360).V(yj)
    a0 = ang(xc, bc, (x1, yj)); a1 = ang(xc, bc, (x0, yj))
    while a1 < a0: a1 += 360
    p.arc(xc, bc, br, a0, a1).Z()
    g.s(p); g.s(P((xc, 10.2), (xc, 15.4))); g.dot(xc, bc, 1.55)
    for y, L in ((5.6, 3.6), (9.1, 2.4), (12.6, 3.6)):
        g.s(P((15.4, y), (15.4 + L, y)))
    return g

def foot(cx, cy, tilt=0.0, fill=False):
    g = Glyph()
    toe = Path(); earc(toe, cx, cy, 2.2, 3.15, -90, 270, move=True); toe.Z()
    hx, hy = cx + math.sin(math.radians(tilt)) * -5.1, cy + 5.1 * math.cos(math.radians(tilt))
    return toe, (hx, hy)


def rot(p, c, deg):
    a = math.radians(deg); x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + x * math.cos(a) - y * math.sin(a), c[1] + x * math.sin(a) + y * math.cos(a))

def foot(g, cx, cy, deg, s=1.0):
    """footprint: egg-shaped forefoot outline + filled heel pad, rotated about (cx, cy)."""
    R = lambda x, y: rot((cx + x * s, cy + y * s), (cx, cy), deg)
    p = Path().M(*R(0, -3.6))
    for c1, c2, e in [((1.75, -3.6), (2.55, -2.1), (2.55, -0.4)), ((2.55, 1.3), (1.5, 2.3), (0, 2.3)),
                      ((-1.5, 2.3), (-2.55, 1.3), (-2.55, -0.4)), ((-2.55, -2.1), (-1.75, -3.6), (0, -3.6))]:
        p.C(*R(*c1), *R(*c2), *R(*e))
    g.s(p.Z())
    hc = R(0, 5.35); g.dot(hc[0], hc[1], 1.5 * s)

@glyph('bl.steps')
def steps(fill=False):
    g = Glyph(); foot(g, 7.6, 6.9, -9); foot(g, 16.4, 11.9, 9)
    return g

@glyph('bl.steptrail')
def steptrail(fill=False):
    g = Glyph(); foot(g, 17.2, 6.6, 20, .95)
    for x, y in ((4.2, 20.0), (8.1, 18.6), (11.7, 16.3)):
        g.dot(x, y, 1.2)
    return g

@glyph('bl.energy')
def energy(fill=False):
    g = Glyph()
    o = Path().M(12, 21.1).C(8.2, 21.1, 5.6, 18.4, 5.6, 14.9).C(5.6, 10.6, 9.4, 8.7, 10.3, 2.9)
    o.C(14.4, 5.4, 18.4, 9.6, 18.4, 14.9).C(18.4, 18.4, 15.8, 21.1, 12, 21.1).Z()
    i = Path().M(12, 21.1).C(10.3, 21.1, 9.3, 19.8, 9.3, 18.3).C(9.3, 16.4, 11.1, 15.5, 12, 13.6).C(12.9, 15.5, 14.7, 16.4, 14.7, 18.3).C(14.7, 19.8, 13.7, 21.1, 12, 21.1)
    g.s(o); g.s(i)
    return g

@glyph('bl.stairs')
def stairs(fill=False):
    g = Glyph(); g.s(P((3, 20.25), (7.5, 20.25), (7.5, 15.75), (12, 15.75), (12, 11.25), (16.5, 11.25), (16.5, 6.75), (21, 6.75)))
    g.s(P((3.2, 12.6), (9.4, 6.4))); g.s(P((5.6, 6.4), (9.4, 6.4), (9.4, 10.2)))
    return g

@glyph('bl.distance')
def distance(fill=False):
    g = Glyph(); cx, cy, r, tip = 16.9, 6.6, 3.7, (16.9, 13.9)
    k = math.degrees(math.acos(r / (tip[1] - cy)))
    p = Path().M(*tip).L(*pol(cx, cy, r, 90 - k)).arc(cx, cy, r, 90 - k, 90 + k - 360).Z()
    g.s(p); g.dot(cx, cy, 1.25)
    g.circ(5.1, 18.9, 1.9)
    g.s(Path().M(7.0, 18.9).L(11.9, 18.9).C(14.9, 18.9, 16.9, 17.9, 16.9, 16.4))
    return g

@glyph('bl.stages')
def stages(fill=False):
    g = Glyph()
    g.s(P((2.75, 5.5), (6, 5.5), (6, 13.5), (9, 13.5), (9, 18.5), (12.5, 18.5), (12.5, 13.5), (15, 13.5), (15, 9.5), (18, 9.5), (18, 13.5), (21.25, 13.5)))
    return g

@glyph('bl.weight')
def weight(fill=False):
    g = Glyph()
    g.s(Path().M(6.5, 3.5).L(17.5, 3.5).arc(17.5, 6.5, 3, -90, 0).L(20.5, 17.5).arc(17.5, 17.5, 3, 0, 90).L(6.5, 20.5).arc(6.5, 17.5, 3, 90, 180).L(3.5, 6.5).arc(6.5, 6.5, 3, 180, 270).Z())
    g.s(Path().arc(12, 12.2, 4.6, 200, 340, move=True))
    g.s(P((12, 12.2), pol(12, 12.2, 3.4, -58)))
    return g

@glyph('bl.muscle')
def muscle(fill=False):
    g = Glyph()
    p = Path().M(3.3, 11.9).C(5.3, 9.6, 7.6, 8.1, 10.2, 8.1).C(12.5, 8.1, 14.2, 9.6, 14.9, 11.7)
    p.L(14.9, 9.1).C(13.2, 8.6, 12.3, 7.0, 12.8, 5.5).C(13.3, 3.9, 15.0, 3.1, 16.9, 3.3).C(19.0, 3.5, 20.4, 5.1, 20.4, 7.2)
    p.L(20.4, 15.3).C(20.4, 17.7, 18.5, 19.6, 16.1, 19.6).L(3.3, 19.6)
    g.s(p)
    g.s(Path().M(8.3, 13.5).C(10.0, 12.6, 12.0, 12.9, 13.2, 14.3))
    return g

@glyph('bl.target')
def target(fill=False):
    g = Glyph(); g.circ(12, 12, 9); g.circ(12, 12, 5); g.dot(12, 12, 1.45); return g

# ------------------------------------------------------------------ insight & interface
@glyph('bl.progress')
def progress(fill=False):
    g = Glyph()
    p = Path().M(3.1, 6.9).C(5.9, 11.4, 7.9, 17.3, 11.1, 17.3).C(14.1, 17.3, 16.2, 12.6, 19.9, 7.7)
    g.s(p); g.s(arrowhead((19.9, 7.7), math.degrees(math.atan2(7.7 - 12.6, 19.9 - 16.2)), 3.3, 40))
    return g

@glyph('bl.trend')
def trend(fill=False):
    g = Glyph()
    g.s(P((3, 20.25), (21, 20.25)))
    g.s(P((3.5, 15.5), (8.5, 10.5), (12.25, 13.75), (20, 6)))
    g.s(P((15.75, 6), (20, 6), (20, 10.25)))
    return g

@glyph('bl.streak')
def streak(fill=False):
    g = Glyph(); xs = [3.9, 9.3, 14.7, 20.1]; y = 12
    for i, x in enumerate(xs):
        if i < 3: g.dot(x, y, 1.85)
        else: g.circ(x, y, 1.65)
    for x0, x1 in zip(xs, xs[1:]):
        g.s(P((x0 + 2.75, y), (x1 - 2.75, y)))
    return g

@glyph('bl.sparkle')
def sparkle_g(fill=False):
    g = Glyph(); g.s(sparkle(10.4, 13.4, 7.6, .3)); g.fl(sparkle(18.7, 5.0, 3.0, .3)); return g

@glyph('bl.evidence')
def evidence(fill=False):
    g = Glyph(); c, r = (10.4, 10.4), 7.0
    g.circ(*c, r); e = pol(*c, r, 45)
    g.s(P((e[0] + 0.2, e[1] + 0.2), (20.6, 20.6)))
    g.s(P((7.9, 13.0), (7.9, 11.0))); g.s(P((10.4, 13.0), (10.4, 7.9))); g.s(P((12.9, 13.0), (12.9, 9.6)))
    return g

@glyph('bl.medal')
def medal(fill=False):
    g = Glyph()
    g.s(P((7.6, 2.9), (10.4, 10.4))); g.s(P((16.4, 2.9), (13.6, 10.4))); g.s(P((7.6, 2.9), (16.4, 2.9)))
    g.circ(12, 15.4, 5.35); g.circ(12, 15.4, 2.05)
    return g

@glyph('bl.calendar')
def calendar(fill=False):
    g = Glyph(); x0, y0, x1, y1, r = 3.5, 5, 20.5, 20.5, 3
    g.s(Path().M(x0 + r, y0).L(x1 - r, y0).arc(x1 - r, y0 + r, r, -90, 0).L(x1, y1 - r).arc(x1 - r, y1 - r, r, 0, 90).L(x0 + r, y1).arc(x0 + r, y1 - r, r, 90, 180).L(x0, y0 + r).arc(x0 + r, y0 + r, r, 180, 270).Z())
    g.s(P((x0, 9.9), (x1, 9.9))); g.s(P((8, 3), (8, 6.8))); g.s(P((16, 3), (16, 6.8)))
    g.dot(15.4, 15.4, 1.7)
    return g

@glyph('bl.journal')
def journal(fill=False):
    g = Glyph(); x0, y0, x1, y1, r = 4.75, 3, 19.25, 21, 2.5
    g.s(Path().M(x0 + r, y0).L(x1 - r, y0).arc(x1 - r, y0 + r, r, -90, 0).L(x1, y1 - r).arc(x1 - r, y1 - r, r, 0, 90).L(x0 + r, y1).arc(x0 + r, y1 - r, r, 90, 180).L(x0, y0 + r).arc(x0 + r, y0 + r, r, 180, 270).Z())
    g.s(P((8.9, 3), (8.9, 21))); g.s(P((12.25, 8.1), (15.75, 8.1))); g.s(P((12.25, 11.6), (15.75, 11.6)))
    return g

@glyph('bl.bodynote')
def bodynote(fill=False):
    g = Glyph(); ox = -2.6
    g.circ(12 + ox, 4.7, 1.9)
    g.s(P((8.9 + ox, 8.9), (15.1 + ox, 8.9), (14.0 + ox, 14.2), (10.0 + ox, 14.2), closed=True))
    g.s(P((8.9 + ox, 8.9), (6.4 + ox, 14.9))); g.s(P((15.1 + ox, 8.9), (17.0 + ox, 13.2)))
    g.s(P((10.7 + ox, 14.2), (10.2 + ox, 20.6))); g.s(P((13.3 + ox, 14.2), (13.8 + ox, 20.6)))
    g.dot(18.6, 5.6, 2.45)
    return g

@glyph('bl.rotate')
def rotate(fill=False):
    """3D rotate: an orbit around a vertical axis; the orbit breaks where the axis passes in front of it."""
    g = Glyph(); cx, cy, rx, ry = 12, 13.2, 9.0, 3.8
    p = Path(); earc(p, cx, cy, rx, ry, 100, 256, move=True); g.s(p)
    p = Path(); earc(p, cx, cy, rx, ry, 284, 428, move=True); g.s(p)
    t = math.radians(428); end = (cx + rx * math.cos(t), cy + ry * math.sin(t))
    tx, ty = -rx * math.sin(t), ry * math.cos(t)
    g.s(arrowhead(end, math.degrees(math.atan2(ty, tx)), 3.0, 42))
    g.s(P((12, 3.0), (12, 21.0)))
    return g

@glyph('bl.warning')
def warning(fill=False):
    g = Glyph(); g.circ(12, 12, 9); g.s(P((12, 7.1), (12, 12.9))); g.dot(12, 16.5, 1.25); return g

@glyph('bl.chevron')
def chevron(fill=False):
    g = Glyph(); g.s(P((9.25, 5.0), (16.25, 12), (9.25, 19.0))); return g


TABS = ['bl.today', 'bl.activity', 'bl.walk', 'bl.body', 'bl.sleep', 'bl.ask']
METRICS = ['bl.readiness', 'bl.load', 'bl.hrv', 'bl.rhr', 'bl.heart', 'bl.resp', 'bl.vo2', 'bl.spo2', 'bl.temp', 'bl.steps', 'bl.steptrail', 'bl.energy', 'bl.stairs', 'bl.distance', 'bl.stages', 'bl.weight', 'bl.muscle', 'bl.target']
INSIGHT = ['bl.progress', 'bl.trend', 'bl.streak', 'bl.sparkle', 'bl.evidence', 'bl.medal', 'bl.calendar', 'bl.journal', 'bl.bodynote', 'bl.rotate', 'bl.warning', 'bl.chevron']
