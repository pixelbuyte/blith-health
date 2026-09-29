"""Tiny glyph DSL: every primitive yields SVG path data and a shapely geometry (for knockouts)."""
import math
from shapely.geometry import LineString, Polygon, Point, MultiPolygon
from shapely.ops import unary_union
from shapely import affinity

SW = 1.75
def f(v):
    s = f'{v:.2f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s

def pol(cx, cy, r, a):  # svg angle convention: degrees, 0=+x, 90=down
    return (cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))

class Path:
    def __init__(self):
        self.d = []; self.subs = []; self.cur = None; self.pts = None; self.closed = []
    def M(self, x, y):
        self._flush(); self.d.append(f'M{f(x)},{f(y)}'); self.cur = (x, y); self.pts = [(x, y)]; return self
    def L(self, x, y):
        self.d.append(f'L{f(x)},{f(y)}'); self.cur = (x, y); self.pts.append((x, y)); return self
    def H(self, x): return self.L(x, self.cur[1])
    def V(self, y): return self.L(self.cur[0], y)
    def arc(self, cx, cy, r, a0, a1, move=False):
        """circular arc about (cx,cy) from angle a0 to a1 (degrees, sweep sign = direction)."""
        p0 = pol(cx, cy, r, a0); p1 = pol(cx, cy, r, a1)
        if move: self.M(*p0)
        elif self.cur is None or math.dist(self.cur, p0) > 1e-3: self.L(*p0)
        sweep = 1 if a1 > a0 else 0; large = 1 if abs(a1 - a0) > 180 else 0
        if abs(abs(a1 - a0) - 360) < 1e-6:
            mid = pol(cx, cy, r, (a0 + a1) / 2)
            self.d.append(f'A{f(r)},{f(r)} 0 1 {sweep} {f(mid[0])},{f(mid[1])} A{f(r)},{f(r)} 0 1 {sweep} {f(p1[0])},{f(p1[1])}')
        else:
            self.d.append(f'A{f(r)},{f(r)} 0 {large} {sweep} {f(p1[0])},{f(p1[1])}')
        n = max(8, int(abs(a1 - a0) / 3))
        for i in range(1, n + 1):
            self.pts.append(pol(cx, cy, r, a0 + (a1 - a0) * i / n))
        self.cur = p1; return self
    def C(self, x1, y1, x2, y2, x, y):
        p0 = self.cur; self.d.append(f'C{f(x1)},{f(y1)} {f(x2)},{f(y2)} {f(x)},{f(y)}')
        for i in range(1, 25):
            t = i / 24; u = 1 - t
            self.pts.append((u**3*p0[0] + 3*u*u*t*x1 + 3*u*t*t*x2 + t**3*x, u**3*p0[1] + 3*u*u*t*y1 + 3*u*t*t*y2 + t**3*y))
        self.cur = (x, y); return self
    def Q(self, x1, y1, x, y):
        p0 = self.cur; self.d.append(f'Q{f(x1)},{f(y1)} {f(x)},{f(y)}')
        for i in range(1, 17):
            t = i / 16; u = 1 - t
            self.pts.append((u*u*p0[0] + 2*u*t*x1 + t*t*x, u*u*p0[1] + 2*u*t*y1 + t*t*y))
        self.cur = (x, y); return self
    def Z(self):
        self.d.append('Z'); self.closed.append(True); self.subs.append((self.pts, True)); self.pts = None; self.cur = None; return self
    def _flush(self):
        if self.pts:
            self.subs.append((self.pts, False))
        self.pts = None
    def data(self):
        self._flush(); return ' '.join(self.d)

def P(*pts, closed=False):
    p = Path().M(*pts[0])
    for q in pts[1:]: p.L(*q)
    return p.Z() if closed else p

def circle_path(cx, cy, r):
    return Path().arc(cx, cy, r, -90, 270, move=True).Z()

class Glyph:
    def __init__(self, sw=SW):
        self.sw = sw; self.items = []   # (kind, Path|elem, extra)
    def s(self, path, sw=None):           # stroked path
        self.items.append(('stroke', path, sw or self.sw)); return self
    def fl(self, path, evenodd=False):    # filled path
        self.items.append(('fill', path, evenodd)); return self
    def circ(self, cx, cy, r, sw=None):    # stroked circle
        self.items.append(('circle', (cx, cy, r), sw or self.sw)); return self
    def dot(self, cx, cy, r=1.15):        # filled circle
        self.items.append(('dot', (cx, cy, r), None)); return self
    def raw_fill(self, geom):             # shapely polygon(s) -> filled path, evenodd
        self.items.append(('geom', geom, None)); return self

    # ---- geometry for knockouts
    def geom(self, extra=0.0):
        gs = []
        for kind, it, x in self.items:
            if kind == 'stroke':
                it.data()
                for pts, closed in it.subs:
                    ln = LineString(pts + ([pts[0]] if closed else []))
                    gs.append(ln.buffer(x / 2 + extra, quad_segs=16))
            elif kind == 'circle':
                cx, cy, r = it; gs.append(Point(cx, cy).buffer(r + x / 2 + extra, quad_segs=32).difference(Point(cx, cy).buffer(max(r - x / 2 - extra, 0), quad_segs=32)))
            elif kind == 'dot':
                cx, cy, r = it; gs.append(Point(cx, cy).buffer(r + extra, quad_segs=32))
            elif kind == 'fill':
                it.data()
                polys = [Polygon(pts) for pts, _ in it.subs]
                g = polys[0]
                for q in polys[1:]: g = g.symmetric_difference(q)
                gs.append(g.buffer(extra) if extra else g)
            elif kind == 'geom':
                gs.append(it.buffer(extra) if extra else it)
        return unary_union(gs)

    def svg(self, color='#000000', size=24, cls=''):
        out = []
        for kind, it, x in self.items:
            if kind == 'stroke':
                out.append(f'<path d="{it.data()}" fill="none" stroke="{color}" stroke-width="{f(x)}" stroke-linecap="round" stroke-linejoin="round"/>')
            elif kind == 'circle':
                cx, cy, r = it
                out.append(f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}" fill="none" stroke="{color}" stroke-width="{f(x)}"/>')
            elif kind == 'dot':
                cx, cy, r = it
                out.append(f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}" fill="{color}"/>')
            elif kind == 'fill':
                out.append(f'<path d="{it.data()}" fill="{color}"' + (' fill-rule="evenodd"' if x else '') + '/>')
            elif kind == 'geom':
                out.append(f'<path d="{geom_d(it)}" fill="{color}" fill-rule="evenodd"/>')
        c = f' class="{cls}"' if cls else ''
        return f'<svg xmlns="http://www.w3.org/2000/svg"{c} width="{size}" height="{size}" viewBox="0 0 24 24">\n  ' + '\n  '.join(out) + '\n</svg>'

def geom_d(g):
    g = g.simplify(0.012, preserve_topology=True)
    polys = [g] if isinstance(g, Polygon) else list(getattr(g, 'geoms', []))
    d = []
    for p in polys:
        if p.is_empty or p.area < 1e-3: continue
        for ring in [p.exterior] + list(p.interiors):
            cs = list(ring.coords)[:-1]
            d.append('M' + ' L'.join(f'{f(x)},{f(y)}' for x, y in cs) + 'Z')   # explicit L for strict SVG parsers
    return ''.join(d)

def knock(base, cut, gap):
    """base geometry minus (cut geometry grown by gap)."""
    return base.difference(cut.buffer(gap, quad_segs=16))

def sparkle(cx, cy, r, w=0.28):
    """4-point star with concave sides (quadratic curves through a waist)."""
    k = r * w
    p = Path().M(cx, cy - r)
    p.Q(cx + k, cy - k, cx + r, cy).Q(cx + k, cy + k, cx, cy + r).Q(cx - k, cy + k, cx - r, cy).Q(cx - k, cy - k, cx, cy - r).Z()
    return p

def earc(path, cx, cy, rx, ry, a0, a1, move=False):
    """elliptical arc (parametric angles, degrees)."""
    p0 = (cx + rx * math.cos(math.radians(a0)), cy + ry * math.sin(math.radians(a0)))
    p1 = (cx + rx * math.cos(math.radians(a1)), cy + ry * math.sin(math.radians(a1)))
    if move: path.M(*p0)
    sweep = 1 if a1 > a0 else 0; large = 1 if abs(a1 - a0) > 180 else 0
    if abs(abs(a1 - a0) - 360) < 1e-6:
        am = math.radians((a0 + a1) / 2); pm = (cx + rx * math.cos(am), cy + ry * math.sin(am))
        path.d.append(f'A{f(rx)},{f(ry)} 0 1 {sweep} {f(pm[0])},{f(pm[1])} A{f(rx)},{f(ry)} 0 1 {sweep} {f(p1[0])},{f(p1[1])}')
    else:
        path.d.append(f'A{f(rx)},{f(ry)} 0 {large} {sweep} {f(p1[0])},{f(p1[1])}')
    n = max(12, int(abs(a1 - a0) / 3))
    for i in range(1, n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        path.pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
    path.cur = p1
    return path

def circle_tangent(px, py, cx, cy, r, side):
    """tangent point on circle (cx,cy,r) from external point p; side=+1/-1 picks which."""
    dx, dy = cx - px, cy - py; d = math.hypot(dx, dy)
    a = math.atan2(dy, dx); b = math.asin(r / d)
    t = a + side * b; L = math.sqrt(d * d - r * r)
    return (px + L * math.cos(t), py + L * math.sin(t))

def ang(cx, cy, p):
    return math.degrees(math.atan2(p[1] - cy, p[0] - cx))

def arrowhead(tip, direction_deg, length=3.1, spread=42):
    a = math.radians(direction_deg + 180)
    l = (tip[0] + length * math.cos(a + math.radians(spread)), tip[1] + length * math.sin(a + math.radians(spread)))
    r = (tip[0] + length * math.cos(a - math.radians(spread)), tip[1] + length * math.sin(a - math.radians(spread)))
    return P(l, tip, r)
