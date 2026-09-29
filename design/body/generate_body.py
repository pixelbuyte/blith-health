#!/usr/bin/env python3
"""Generates Blith's interim body figure (front + back SVGs) and the region anchor map.

Everything is parametric: one right-half contour mirrored around x=200, arms as separate smooth
shapes that share user-space gradients (so overlaps are seamless), and anchors computed from the
same landmarks. Only SVG features Xcode's CoreSVG renders are used (paths, ellipses, linear and
radial gradients, opacity) — no filters, masks or CSS.

    python3 design/body/generate_body.py   # writes the asset catalog SVGs, the JSON and a preview
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "ios/Blith/Resources/Assets.xcassets/Body")
REGIONS = os.path.join(ROOT, "ios/Blith/Resources/body-regions.json")
CX = 200.0


def smooth(points, closed=False, tension=1.0):
    """Catmull-Rom through points → cubic Bézier path data."""
    pts = points[:]
    n = len(pts)
    if n < 2:
        return ""
    d = [f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"]
    rng = range(n if closed else n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if (closed or i > 0) else pts[i]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if (closed or i + 2 < n) else p2
        c1 = (p1[0] + (p2[0] - p0[0]) / 6 * tension, p1[1] + (p2[1] - p0[1]) / 6 * tension)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6 * tension, p2[1] - (p3[1] - p1[1]) / 6 * tension)
        d.append(f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}")
    if closed:
        d.append("Z")
    return " ".join(d)


def mirror(p):
    return (2 * CX - p[0], p[1])


# ---- Right-half contour (viewer's right), head top → crotch. Tall, lean, ~8 heads. ----
HALF = [
    (200, 30), (222, 34), (238, 50), (243, 76), (242, 100),   # cranium
    (247, 104), (247, 118), (240, 124),                        # ear hint
    (236, 138), (226, 152), (214, 160),                        # jaw → chin side
    (216, 172), (220, 184),                                    # neck
    (240, 192), (264, 198), (281, 209),                        # trapezius → shoulder
    (290, 229), (290, 249),                                    # deltoid cap (arm overlaps)
    (272, 265), (265, 292),                                    # armpit
    (261, 332), (257, 372), (252, 412),                        # ribs → waist
    (254, 448), (260, 478), (263, 506),                        # iliac crest → hip
    (265, 548), (262, 600), (256, 650), (248, 700),            # outer thigh
    (249, 724), (247, 746),                                    # knee
    (251, 790), (248, 836), (238, 884), (230, 922),            # calf → ankle
    (234, 944), (242, 962), (238, 974), (214, 976),            # foot
    (208, 962), (209, 932),                                    # inner ankle
    (214, 880), (218, 820), (216, 772), (214, 740),            # inner calf → knee
    (216, 700), (213, 650), (209, 600), (204, 566),            # inner thigh
    (200, 560),                                                # crotch (smooth, understated)
]

# Arm, viewer's right. Relaxed A-pose, ~14° from vertical, palms facing in.
ARM_OUT = [(276, 204), (296, 224), (304, 262), (305, 310), (310, 360), (318, 400),
           (326, 440), (333, 480), (338, 516), (344, 540), (350, 566), (350, 596), (342, 616)]
ARM_IN = [(334, 618), (326, 600), (322, 572), (318, 540), (312, 512), (302, 470),
          (292, 420), (284, 388), (276, 344), (270, 300), (264, 262)]


def body_path():
    right = HALF
    left = [mirror(p) for p in reversed(HALF[1:-1])]
    return smooth(right + left, closed=True)


def arm_path(side):
    pts = ARM_OUT + ARM_IN
    if side == "left":
        pts = [mirror(p) for p in pts]
    return smooth(pts, closed=True)


def defs(view):
    return f"""<defs>
  <linearGradient id="skin" gradientUnits="userSpaceOnUse" x1="60" y1="0" x2="340" y2="0">
    <stop offset="0" stop-color="#8FD2FF"/>
    <stop offset="0.16" stop-color="#4C8DFF"/>
    <stop offset="0.36" stop-color="#2459EE"/>
    <stop offset="0.5" stop-color="#1D4BDB"/>
    <stop offset="0.64" stop-color="#2459EE"/>
    <stop offset="0.84" stop-color="#4C8DFF"/>
    <stop offset="1" stop-color="#8FD2FF"/>
  </linearGradient>
  <linearGradient id="depth" gradientUnits="userSpaceOnUse" x1="0" y1="30" x2="0" y2="980">
    <stop offset="0" stop-color="#9ED8FF" stop-opacity="0.22"/>
    <stop offset="0.45" stop-color="#0B2A9E" stop-opacity="0"/>
    <stop offset="1" stop-color="#061A6B" stop-opacity="0.35"/>
  </linearGradient>
  <radialGradient id="sheen" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#CFEFFF" stop-opacity="0.5"/>
    <stop offset="1" stop-color="#CFEFFF" stop-opacity="0"/>
  </radialGradient>
</defs>"""


def glow(d):
    return (f'<path d="{d}" fill="none" stroke="#3FA9FF" stroke-opacity="0.07" stroke-width="22" stroke-linejoin="round"/>'
            f'<path d="{d}" fill="none" stroke="#6CC4FF" stroke-opacity="0.12" stroke-width="10" stroke-linejoin="round"/>')


def part(d):
    return f'<path d="{d}" fill="url(#skin)"/>'


def overlay(d):
    return f'<path d="{d}" fill="url(#depth)"/>'


def rim(d):
    return f'<path d="{d}" fill="none" stroke="#BDE6FF" stroke-opacity="0.75" stroke-width="1.6" stroke-linejoin="round"/>'


def line(points, opacity=0.28, width=1.4, color="#CFEFFF"):
    return (f'<path d="{smooth(points)}" fill="none" stroke="{color}" stroke-opacity="{opacity}" '
            f'stroke-width="{width}" stroke-linecap="round"/>')


def both(points, **kw):
    return line(points, **kw) + line([mirror(p) for p in points], **kw)


def sheen(cx, cy, rx, ry, opacity=1.0, mirrored=True):
    s = f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="url(#sheen)" opacity="{opacity}"/>'
    if mirrored and cx != CX:
        s += f'<ellipse cx="{2 * CX - cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="url(#sheen)" opacity="{opacity}"/>'
    return s


def definition(view):
    dark = "#0A2A9A"
    out = []
    if view == "front":
        out.append(both([(205, 200), (232, 198), (262, 204)], opacity=0.35))                   # clavicle
        out.append(both([(206, 288), (232, 293), (256, 284), (266, 266)], opacity=0.16))        # lower pec, flat and soft
        out.append(line([(200, 318), (200, 372), (200, 430)], opacity=0.2))                     # midline only
        out.append(f'<ellipse cx="200" cy="446" rx="2.4" ry="3.6" fill="{dark}" fill-opacity="0.35"/>')  # navel
        out.append(both([(236, 452), (224, 500), (210, 536)], opacity=0.16))                    # iliac line, understated
        out.append(both([(282, 232), (286, 262), (288, 290)], opacity=0.2))                     # deltoid edge
        out.append(both([(300, 300), (298, 344), (302, 378)], opacity=0.16))                    # biceps
        out.append(both([(250, 560), (240, 640), (236, 700)], opacity=0.16))                    # outer quad
        out.append(both([(222, 610), (224, 670), (230, 706)], opacity=0.14))                    # inner quad teardrop
        out.append(f'<ellipse cx="231" cy="728" rx="11" ry="13" fill="none" stroke="#CFEFFF" stroke-opacity="0.2" stroke-width="1.2"/>')
        out.append(f'<ellipse cx="169" cy="728" rx="11" ry="13" fill="none" stroke="#CFEFFF" stroke-opacity="0.2" stroke-width="1.2"/>')
        out.append(both([(236, 770), (234, 830), (228, 890)], opacity=0.14))                    # shin
        out.append(line([(200, 96), (199, 112), (203, 116)], opacity=0.25, width=1.2))          # nose hint
        out.append(sheen(200, 244, 72, 20, 0.4, mirrored=False))                                 # upper chest plane
        out.append(sheen(276, 226, 16, 22, 0.9))                                                # shoulders
        out.append(sheen(245, 600, 18, 60, 0.6))                                                # thighs
        out.append(sheen(200, 70, 30, 34, 0.7, mirrored=False))                                 # face plane
    else:
        out.append(line([(200, 186), (200, 300), (200, 420), (200, 470)], opacity=0.26, width=1.6))  # spine groove
        out.append(both([(214, 236), (238, 226), (256, 250), (246, 300), (222, 312)], opacity=0.2))  # scapula
        out.append(both([(262, 290), (254, 340), (238, 400)], opacity=0.16))                    # lats
        out.append(both([(222, 460), (238, 470), (252, 486)], opacity=0.16))                    # lower back dimple area
        out.append(both([(206, 560), (230, 566), (252, 556)], opacity=0.14))                    # gluteal fold, understated
        out.append(both([(236, 600), (232, 660), (230, 706)], opacity=0.14))                    # hamstring
        out.append(both([(230, 750), (240, 790), (234, 840)], opacity=0.18))                    # calf
        out.append(both([(300, 320), (304, 360), (308, 392)], opacity=0.16))                    # triceps
        out.append(both([(314, 416), (318, 422)], opacity=0.3, width=2))                        # elbow point
        out.append(sheen(236, 250, 30, 44, 0.4))                                                # shoulder blades
        out.append(sheen(238, 790, 12, 38, 0.6))                                                # calves
        out.append(sheen(200, 80, 32, 40, 0.6, mirrored=False))
    return "".join(out)


def svg(view):
    b = body_path()
    ar, al = arm_path("right"), arm_path("left")
    parts = [glow(ar), glow(al), glow(b)]
    # Arms first, including their rims, so the torso covers the seams at the shoulders.
    parts += [part(ar), part(al), overlay(ar), overlay(al), rim(ar), rim(al)]
    parts += [part(b), overlay(b)]
    parts.append(definition(view))
    parts.append(rim(b))
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="400" height="1000" viewBox="0 0 400 1000">'
            f'{defs(view)}{"".join(parts)}</svg>')


# ---- Region anchors (viewBox units). Front: person's right = viewer's left. ----
def anchors():
    # Coordinates on the viewer's LEFT half (x < 200) for the FRONT view = person's right.
    right_side = {
        "Shoulder": (132, 224, 22), "UpperArm": (113, 300, 20), "Elbow": (102, 398, 16),
        "Forearm": (88, 452, 18), "Wrist": (74, 522, 12), "Hand": (62, 584, 20),
        "Hip": (156, 512, 22), "Thigh": (165, 610, 28), "Knee": (169, 730, 18),
        "Shin": (167, 820, 18), "Calf": (164, 800, 20), "Ankle": (180, 928, 13), "Foot": (175, 962, 16),
    }
    front, back = {}, {}
    center_front = {"head": (200, 80, 42), "neck": (200, 170, 18), "chest": (200, 262, 44),
                    "abdomen": (200, 400, 40), "hips": (200, 520, 40)}
    center_back = {"head": (200, 80, 42), "neck": (200, 170, 18), "upperBack": (200, 262, 48),
                   "lowerBack": (200, 440, 40)}
    front.update(center_front)
    back.update(center_back)
    for part_name, (x, y, r) in right_side.items():
        mirrored_x = 2 * CX - x
        if part_name not in ("Calf",):
            front["right" + part_name] = (x, y, r)
            front["left" + part_name] = (mirrored_x, y, r)
        if part_name not in ("Shin",):
            # From behind the person's right is on the viewer's right.
            back["right" + part_name] = (mirrored_x, y, r)
            back["left" + part_name] = (x, y, r)
    as_dict = lambda m: {k: {"x": v[0], "y": v[1], "r": v[2]} for k, v in m.items()}
    return {"viewBox": [400, 1000], "front": as_dict(front), "back": as_dict(back)}


def imageset(name, content):
    folder = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, f"{name}.svg"), "w") as f:
        f.write(content)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": f"{name}.svg", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1},
                   "properties": {"preserves-vector-representation": True, "template-rendering-intent": "original"}},
                  f, indent=2)


def main():
    os.makedirs(ASSETS, exist_ok=True)
    with open(os.path.join(ASSETS, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}}, f, indent=2)
    front, back = svg("front"), svg("back")
    imageset("body.front", front)
    imageset("body.back", back)
    regions = anchors()
    with open(REGIONS, "w") as f:
        json.dump(regions, f, indent=2)
    # Preview with anchors.
    def dots(view):
        return "".join(f'<circle cx="{v["x"]}" cy="{v["y"]}" r="4" fill="#FF7A59"/>'
                       f'<text x="{v["x"] + 6}" y="{v["y"] + 3}" font-size="9" fill="#FFD2C4" font-family="monospace">{k}</text>'
                       for k, v in regions[view].items())
    html = f"""<html><body style="margin:0;background:#050B24;display:flex;gap:10px">
{front}{back}
<svg width="400" height="1000" viewBox="0 0 400 1000">{front[front.index('<defs>'):-6]}{dots('front')}</svg>
<svg width="400" height="1000" viewBox="0 0 400 1000">{back[back.index('<defs>'):-6]}{dots('back')}</svg>
</body></html>"""
    out = os.path.join(ROOT, "design/body/body-preview.html")
    with open(out, "w") as f:
        f.write(html)
    print("ok", out)


if __name__ == "__main__":
    main()
