#!/usr/bin/env python3
"""Builds Blith's 3D body assets (mesh, region map, anatomy-line and muscle textures, previews).

Source: the MakeHuman 1.x base mesh (hm08), macro-detail targets, default skeleton and skin weights,
downloaded from github.com/makehumancommunity/makehuman. Those assets were released under CC0 1.0
(see LICENSE.md sections C/D in that repository), so the generated files carry no attribution
requirement; we credit MakeHuman anyway in body3d.json ("source").

Pipeline: base mesh -> male/young/muscular/ideal-proportion targets -> linear-blend-skinned relaxed
pose (arms lowered, elbows and fingers relaxed) -> body + eyeballs only -> one Catmull-Clark pass ->
metres, y up, feet on y=0, facing +z, person's left at +x -> per-triangle BodyRegion + muscle ids ->
textures baked per texel from 3D position (seam-free) -> body.bin / body3d.json / PNG / JPG -> previews.

    pip install numpy scipy Pillow
    MH_CACHE=/some/cache/dir python3 design/body3d/build_body.py

Everything is deterministic (fixed noise seeds); downloads are cached in $MH_CACHE.
"""
import json
import os
import struct
import sys
import urllib.request

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'ios', 'Blith', 'Resources', 'Body3D')
DESIGN = os.path.join(ROOT, 'design', 'body3d')
CACHE = os.environ.get('MH_CACHE', os.path.join(os.path.expanduser('~'), '.cache', 'blith-makehuman'))
BASE_URL = 'https://raw.githubusercontent.com/makehumancommunity/makehuman/master/makehuman/'

# ----------------------------------------------------------------------------------------------
# Figure parameters
HEIGHT = 1.80            # metres
MUSCLE = 0.80            # 0 = average, 1 = MakeHuman max muscle
WEIGHT = 0.40            # 0.5 = average (slightly lean for definition)
EXTRA_TARGETS = [        # (target, weight) — subtle athletic shaping
    ('data/targets/torso/torso-vshape-incr.target', 0.5),
    ('data/targets/torso/torso-muscle-dorsi-incr.target', 0.3),
    ('data/targets/torso/torso-muscle-pectoral-incr.target', 0.2),
    ('data/targets/stomach/stomach-pregnant-decr.target', 0.5),
    ('data/targets/neck/neck-scale-horiz-incr.target', 0.2),
    ('data/targets/hip/hip-scale-horiz-decr.target', 0.2),
]
ARM_LOWER_DEG = 20.0     # rotate arms down from MakeHuman's A-pose (~42deg -> ~22deg from torso)
ELBOW_STRAIGHTEN_DEG = 28.0
FINGER_CURL_DEG = 20.0
FINGER_CLOSE_DEG = 10.0
TEX = 2048

REGION_IDS = ['head', 'neck', 'rightShoulder', 'leftShoulder', 'chest', 'abdomen', 'upperBack', 'lowerBack',
              'rightUpperArm', 'leftUpperArm', 'rightElbow', 'leftElbow', 'rightForearm', 'leftForearm',
              'rightWrist', 'leftWrist', 'rightHand', 'leftHand', 'hips', 'rightHip', 'leftHip',
              'rightThigh', 'leftThigh', 'rightKnee', 'leftKnee', 'rightShin', 'leftShin', 'rightCalf', 'leftCalf',
              'rightAnkle', 'leftAnkle', 'rightFoot', 'leftFoot']
RI = {r: i for i, r in enumerate(REGION_IDS)}

MUSCLES = [
    ('neck', 'Neck (sternocleidomastoid)'),
    ('trapezius', 'Upper back (trapezius)'),
    ('deltoids', 'Shoulders (deltoids)'),
    ('pectorals', 'Chest (pectorals)'),
    ('biceps', 'Front of upper arm (biceps)'),
    ('triceps', 'Back of upper arm (triceps)'),
    ('forearmFlexors', 'Inner forearm (flexors)'),
    ('forearmExtensors', 'Outer forearm (extensors)'),
    ('abdominals', 'Abs (rectus abdominis)'),
    ('obliques', 'Sides of waist (obliques)'),
    ('serratus', 'Side of ribs (serratus anterior)'),
    ('lats', 'Mid back (latissimus dorsi)'),
    ('erectors', 'Lower back (spinal erectors)'),
    ('glutes', 'Buttocks (glutes)'),
    ('quadriceps', 'Front of thigh (quadriceps)'),
    ('adductors', 'Inner thigh (adductors)'),
    ('hamstrings', 'Back of thigh (hamstrings)'),
    ('calves', 'Calves (gastrocnemius & soleus)'),
    ('tibialis', 'Front of shin (tibialis anterior)'),
]
MI = {m: i for i, (m, _) in enumerate(MUSCLES)}
NONE = 255


# ----------------------------------------------------------------------------------------------
# MakeHuman data
def fetch(rel):
    dst = os.path.join(CACHE, rel)
    if not os.path.exists(dst):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        print('  downloading', rel)
        with urllib.request.urlopen(BASE_URL + rel, timeout=120) as r:
            data = r.read()
        with open(dst + '.part', 'wb') as f:
            f.write(data)
        os.replace(dst + '.part', dst)
    return dst


def load_obj():
    V, VT, F, FT, G = [], [], [], [], []
    g = None
    for line in open(fetch('data/3dobjs/base.obj')):
        if line.startswith('v '):
            V.append([float(x) for x in line.split()[1:4]])
        elif line.startswith('vt '):
            VT.append([float(x) for x in line.split()[1:3]])
        elif line.startswith('g '):
            g = line.split()[1]
        elif line.startswith('f '):
            p = line.split()[1:]
            F.append([int(x.split('/')[0]) - 1 for x in p])
            FT.append([int(x.split('/')[1]) - 1 for x in p])
            G.append(g)
    return np.array(V), np.array(VT), np.array(F), np.array(FT), np.array(G)


def load_target(rel):
    idx, d = [], []
    for line in open(fetch(rel)):
        s = line.split()
        if len(s) == 4 and not line.startswith('#'):
            idx.append(int(s[0]))
            d.append([float(x) for x in s[1:]])
    return np.array(idx, int), np.array(d).reshape(-1, 3)


def morph(V):
    md = 'data/targets/macrodetails/'
    spec = [(md + f'{r}-male-young.target', 1 / 3) for r in ('caucasian', 'african', 'asian')]
    mw = {'max': MUSCLE, 'average': 1 - MUSCLE}
    ww = {'min': max(0.0, (0.5 - WEIGHT) * 2), 'average': 1 - abs(WEIGHT - 0.5) * 2, 'max': max(0.0, (WEIGHT - 0.5) * 2)}
    for m in mw:
        for w in ww:
            if mw[m] * ww[w] > 0:
                spec.append((md + f'universal-male-young-{m}muscle-{w}weight.target', mw[m] * ww[w]))
                if w != 'max':
                    spec.append((md + f'proportions/male-young-{m}muscle-{w}weight-idealproportions.target', mw[m] * ww[w]))
    spec += EXTRA_TARGETS
    V = V.copy()
    for rel, w in spec:
        i, d = load_target(rel)
        if len(i):
            np.add.at(V, i, w * d)
    return V


def skeleton(V):
    sk = json.load(open(fetch('data/rigs/default.mhskel')))
    J = {n: V[ids].mean(0) for n, ids in sk['joints'].items()}
    return {b: dict(head=J[i['head']], tail=J[i['tail']], parent=i['parent']) for b, i in sk['bones'].items()}


def skin_weights(nv):
    w = json.load(open(fetch('data/rigs/default_weights.mhw')))['weights']
    names = sorted(w.keys())
    Wm = np.zeros((nv, len(names)), np.float32)
    for j, b in enumerate(names):
        a = np.array(w[b])
        if len(a):
            Wm[a[:, 0].astype(int), j] = a[:, 1]
    s = Wm.sum(1, keepdims=True)
    return names, np.where(s > 0, Wm / np.maximum(s, 1e-9), Wm)


def rot(axis, ang):
    axis = np.asarray(axis, float)
    x, y, z = axis / np.linalg.norm(axis)
    c, s = np.cos(ang), np.sin(ang)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def pose(V, bones, names, Wm):
    """Relaxed stance via linear-blend skinning: arms down, elbows/fingers relaxed."""
    local = {}
    for s, sg in (('L', 1), ('R', -1)):
        sh = bones[f'upperarm01.{s}']['head']; el = bones[f'lowerarm01.{s}']['head']; wr = bones[f'wrist.{s}']['head']
        local[f'shoulder01.{s}'] = (rot([0, 0, 1], -sg * np.radians(ARM_LOWER_DEG * 0.3)), bones[f'shoulder01.{s}']['head'])
        local[f'upperarm01.{s}'] = (rot([0, 0, 1], -sg * np.radians(ARM_LOWER_DEG * 0.7)), sh)
        local[f'lowerarm01.{s}'] = (rot(np.cross(el - sh, wr - el), -np.radians(ELBOW_STRAIGHTEN_DEG)), el)
        I = bones[f'finger2-1.{s}']['head']; K = bones[f'finger5-1.{s}']['head']; M = bones[f'finger3-1.{s}']['head']
        pn = np.cross(K - I, M - wr)
        for fi in range(2, 6):
            for seg in range(1, 4):
                b = f'finger{fi}-{seg}.{s}'
                R = rot(K - I, sg * np.radians(FINGER_CURL_DEG * (0.6 if seg == 1 else 1.0)))
                if seg == 1:
                    R = rot(pn, sg * np.radians({2: 1.0, 3: 0.2, 4: -0.5, 5: -1.0}[fi] * FINGER_CLOSE_DEG)) @ R
                local[b] = (R, bones[b]['head'])
    Gx = {}

    def glob(b):
        if b not in Gx:
            par = bones[b]['parent']
            Rp, tp = glob(par) if par else (np.eye(3), np.zeros(3))
            R, p = local.get(b, (np.eye(3), np.zeros(3)))
            Gx[b] = (Rp @ R, Rp @ (p - R @ p) + tp)
        return Gx[b]

    out = np.zeros_like(V)
    for j, b in enumerate(names):
        nz = Wm[:, j] > 0
        if nz.any():
            R, t = glob(b)
            out[nz] += Wm[nz, j, None] * (V[nz] @ R.T + t)
    joints = {}
    for b in bones:
        R, t = glob(b)
        joints[b] = (R @ bones[b]['head'] + t, R @ bones[b]['tail'] + t)
    return out, joints


BONE_GROUPS = ['head', 'neck', 'torso', 'pelvis.L', 'pelvis.R'] + [f'{g}.{s}' for s in 'LR' for g in ('shoulder', 'uarm', 'farm', 'hand', 'thigh', 'shank', 'foot')]
GI = {g: i for i, g in enumerate(BONE_GROUPS)}


def bone_group(b):
    s = b[-1] if b[-2:] in ('.L', '.R') else None
    base = b[:-2] if s else b
    if base.startswith(('neck',)):
        return 'neck'
    if base.startswith(('spine', 'root', 'clavicle', 'breast')):
        return 'torso'
    if base == 'pelvis':
        return f'pelvis.{s}'
    if base == 'shoulder01':
        return f'shoulder.{s}'
    if base.startswith('upperarm'):
        return f'uarm.{s}'
    if base.startswith('lowerarm'):
        return f'farm.{s}'
    if base.startswith(('wrist', 'metacarpal', 'finger')):
        return f'hand.{s}'
    if base.startswith('upperleg'):
        return f'thigh.{s}'
    if base.startswith('lowerleg'):
        return f'shank.{s}'
    if base.startswith(('foot', 'toe')):
        return f'foot.{s}'
    return 'head'


# ----------------------------------------------------------------------------------------------
# Geometry helpers
def catmull_clark(P, Q, UV, QT, W):
    """One Catmull-Clark step on a quad mesh. UVs are subdivided linearly on their own topology;
    per-vertex attributes W are averaged linearly."""
    nF, nV = len(Q), len(P)
    E, FE = np.unique(np.sort(np.stack([Q, np.roll(Q, -1, 1)], 2).reshape(-1, 2), 1), axis=0, return_inverse=True)
    FE = FE.reshape(nF, 4)
    nE = len(E)
    fp = P[Q].mean(1)
    cnt = np.bincount(FE.ravel(), minlength=nE)
    fsum = np.zeros((nE, 3)); np.add.at(fsum, FE.ravel(), np.repeat(fp, 4, 0))
    mid = (P[E[:, 0]] + P[E[:, 1]]) / 2
    bnd = cnt == 1
    ep = mid.copy()
    ep[~bnd] = (P[E[~bnd, 0]] + P[E[~bnd, 1]] + fsum[~bnd]) / 4
    val = np.bincount(Q.ravel(), minlength=nV).astype(float)
    Fav = np.zeros((nV, 3)); np.add.at(Fav, Q.ravel(), np.repeat(fp, 4, 0)); Fav /= np.maximum(val, 1)[:, None]
    ec = np.bincount(E.ravel(), minlength=nV).astype(float)
    Rav = np.zeros((nV, 3)); np.add.at(Rav, E[:, 0], mid); np.add.at(Rav, E[:, 1], mid); Rav /= np.maximum(ec, 1)[:, None]
    vp = (Fav + 2 * Rav + (val - 3)[:, None] * P) / np.maximum(val, 1)[:, None]
    be = E[bnd]
    isb = np.zeros(nV, bool); isb[be.ravel()] = True
    nb = np.zeros((nV, 3)); np.add.at(nb, be[:, 0], P[be[:, 1]]); np.add.at(nb, be[:, 1], P[be[:, 0]])
    vp[isb] = (6 * P[isb] + nb[isb]) / 8
    newP = np.concatenate([vp, ep, fp])
    newW = np.concatenate([W, (W[E[:, 0]] + W[E[:, 1]]) / 2, W[Q].mean(1)])
    ei = nV + FE
    fi = nV + nE + np.arange(nF)
    newQ = np.stack([np.stack([Q[:, i], ei[:, i], fi, ei[:, (i - 1) % 4]], 1) for i in range(4)], 1).reshape(-1, 4)
    ET, FET = np.unique(np.sort(np.stack([QT, np.roll(QT, -1, 1)], 2).reshape(-1, 2), 1), axis=0, return_inverse=True)
    FET = FET.reshape(nF, 4)
    nT = len(UV)
    newUV = np.concatenate([UV, (UV[ET[:, 0]] + UV[ET[:, 1]]) / 2, UV[QT].mean(1)])
    eti = nT + FET
    fti = nT + len(ET) + np.arange(nF)
    newQT = np.stack([np.stack([QT[:, i], eti[:, i], fti, eti[:, (i - 1) % 4]], 1) for i in range(4)], 1).reshape(-1, 4)
    return newP, newQ, newUV, newQT, newW


def vertex_normals(P, T):
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    N = np.zeros_like(P)
    for i in range(3):
        np.add.at(N, T[:, i], fn)
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)


def rasterize(P2, Z, tris, W, H, chunk=60000):
    """Vectorised triangle rasteriser. P2 (N,2) pixel coords (x right, y down); Z (N,) depth, smaller wins
    (None = no depth test). Returns triangle id per pixel (-1 = empty) and barycentrics."""
    A, B, C = P2[tris[:, 0]], P2[tris[:, 1]], P2[tris[:, 2]]
    lo = np.maximum(np.floor(np.minimum(np.minimum(A, B), C) - 0.5).astype(np.int64), 0)
    hi = np.ceil(np.maximum(np.maximum(A, B), C) - 0.5).astype(np.int64)
    hi[:, 0] = np.minimum(hi[:, 0], W - 1); hi[:, 1] = np.minimum(hi[:, 1], H - 1)
    size = np.maximum(hi - lo + 1, 0).max(1)
    den = (B[:, 0] - A[:, 0]) * (C[:, 1] - A[:, 1]) - (B[:, 1] - A[:, 1]) * (C[:, 0] - A[:, 0])
    ok = (size > 0) & (np.abs(den) > 1e-12)
    out = []
    k, prev = 1, 0
    maxs = size[ok].max() if ok.any() else 0
    while prev < maxs:
        sel = np.nonzero(ok & (size > prev) & (size <= k))[0]
        step = max(1, chunk // (k * k) + 1)
        ar = np.arange(k)
        for s in range(0, len(sel), step):
            idx = sel[s:s + step]
            gx = np.broadcast_to(lo[idx, 0, None, None] + ar[None, None, :], (len(idx), k, k))
            gy = np.broadcast_to(lo[idx, 1, None, None] + ar[None, :, None], (len(idx), k, k))
            px, py = gx + 0.5, gy + 0.5
            a, b, c = A[idx][:, None, None, :], B[idx][:, None, None, :], C[idx][:, None, None, :]
            d = den[idx][:, None, None]
            w0 = ((b[..., 0] - px) * (c[..., 1] - py) - (b[..., 1] - py) * (c[..., 0] - px)) / d
            w1 = ((c[..., 0] - px) * (a[..., 1] - py) - (c[..., 1] - py) * (a[..., 0] - px)) / d
            w2 = 1.0 - w0 - w1
            m = (w0 >= -1e-7) & (w1 >= -1e-7) & (w2 >= -1e-7) & (gx <= hi[idx, 0, None, None]) & (gy <= hi[idx, 1, None, None])
            if not m.any():
                continue
            ti = np.broadcast_to(idx[:, None, None], m.shape)[m]
            bc = np.stack([w0[m], w1[m], w2[m]], 1)
            dep = (bc * Z[tris[ti]]).sum(1) if Z is not None else np.zeros(len(ti))
            out.append((gy[m] * W + gx[m], dep, ti, bc))
        prev, k = k, k * 2
    tid = np.full(H * W, -1, np.int64)
    bary = np.zeros((H * W, 3), np.float32)
    if out:
        pix, dep, ti, bc = (np.concatenate(x) for x in zip(*out))
        order = np.lexsort((dep, pix))
        ps = pix[order]
        first = np.ones(len(ps), bool); first[1:] = ps[1:] != ps[:-1]
        sel = order[first]
        tid[ps[first]] = ti[sel]
        bary[ps[first]] = bc[sel]
    return tid.reshape(H, W), bary.reshape(H, W, 3)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def unit(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)


# ----------------------------------------------------------------------------------------------
# Mesh
class Body:
    pass


def build_mesh():
    V0, VT, F, FT, G = load_obj()
    V = morph(V0)
    bones = skeleton(V)
    names, Wm = skin_weights(len(V))
    V, joints = pose(V, bones, names, Wm)
    GW = np.zeros((len(V), len(BONE_GROUPS)), np.float32)
    for j, b in enumerate(names):
        GW[:, GI[bone_group(b)]] += Wm[:, j]
    eye = (G == 'helper-l-eye') | (G == 'helper-r-eye')
    keep = (G == 'body') | eye
    iseye = np.zeros((len(V), 1), np.float32)
    iseye[F[eye].ravel()] = 1
    P, Q, UV, QT, A = catmull_clark(V, F[keep], VT, FT[keep], np.concatenate([GW, iseye], 1))
    used = np.unique(Q)
    remap = np.full(len(P), -1); remap[used] = np.arange(len(used))
    P, A, Q = P[used], A[used], remap[Q]
    # units: decimetres -> metres, feet on y=0, HEIGHT tall, centred on x/z
    Pd = P * 0.1
    y0 = Pd[:, 1].min()
    k = HEIGHT / (Pd[:, 1].max() - y0)
    c = np.array([(Pd[:, 0].max() + Pd[:, 0].min()) / 2, y0, (Pd[:, 2].max() + Pd[:, 2].min()) / 2])
    tf = lambda p: (np.asarray(p) * 0.1 - c) * k
    P = tf(P)
    b = Body()
    b.P = P                                   # geometric vertices
    b.GW = A[:, :-1]
    b.Q = Q
    b.joints = {n: (tf(h), tf(t)) for n, (h, t) in joints.items()}
    # render vertices = unique (position, uv) pairs
    corners = np.stack([Q.ravel(), QT.ravel()], 1)
    rv, inv = np.unique(corners, axis=0, return_inverse=True)
    inv = inv.reshape(-1, 4)
    b.rv_pos = rv[:, 0]
    b.uv = np.stack([UV[rv[:, 1], 0], 1.0 - UV[rv[:, 1], 1]], 1)      # v = 0 at the top image row
    b.T = np.concatenate([inv[:, [0, 1, 2]], inv[:, [0, 2, 3]]])       # render-vertex triangles (CCW outside)
    b.TG = b.rv_pos[b.T]                                              # geometric triangles
    b.N = vertex_normals(P, b.TG)                                     # smooth across UV seams
    b.tri_eye = A[b.TG, -1].mean(1) > 0.5
    return b


# ----------------------------------------------------------------------------------------------
# Landmarks and body coordinates
def landmarks(b):
    J = b.joints
    L = Body()
    P, GW = b.P, b.GW
    for s, sg in (('L', 1), ('R', -1)):
        setattr(L, 'arm' + s, [J[f'upperarm01.{s}'][0], J[f'lowerarm01.{s}'][0], J[f'wrist.{s}'][0], J[f'finger3-3.{s}'][1]])
        setattr(L, 'leg' + s, [J[f'upperleg01.{s}'][0], J[f'lowerleg01.{s}'][0], J[f'foot.{s}'][0], J[f'toe3-3.{s}'][1]])
    torso = GW[:, [GI['torso'], GI['pelvis.L'], GI['pelvis.R']]].sum(1) > 0.5
    L.y_crotch = P[torso & (np.abs(P[:, 0]) < 0.012), 1].min()
    # torso centre line z_c(y): midpoint of front/back extent on the midline
    ys = np.arange(0.70, 1.62, 0.01)
    zc = []
    mid = np.abs(P[:, 0]) < 0.02
    for y in ys:
        m = mid & (np.abs(P[:, 1] - y) < 0.01) & (GW[:, GI['torso']] + GW[:, GI['neck']] + GW[:, GI['pelvis.L']] + GW[:, GI['pelvis.R']] > 0.3)
        zc.append((P[m, 2].max() + P[m, 2].min()) / 2 if m.sum() > 2 else np.nan)
    zc = np.array(zc)
    ok = ~np.isnan(zc)
    zc = np.interp(ys, ys[ok], zc[ok])
    zc = ndimage.gaussian_filter1d(zc, 3, mode='nearest')
    L.zc_y, L.zc = ys, zc
    # navel: deepest point of the front midline profile between 0.95 and 1.15 m
    front = mid & (P[:, 2] > np.interp(P[:, 1], ys, zc))
    # navel: the densest cluster of front-midline vertices between 1.0 and 1.2 m (the umbilicus ring)
    fm = front & (P[:, 1] > 0.55 * HEIGHT) & (P[:, 1] < 0.67 * HEIGHT) & (np.abs(P[:, 0]) < 0.01)
    hist, edges = np.histogram(P[fm, 1], bins=np.arange(0.55 * HEIGHT, 0.67 * HEIGHT, 0.01))
    hist = ndimage.uniform_filter1d(hist.astype(float), 3)
    L.y_navel = float(edges[np.argmax(hist)] + 0.005)
    for s, sg in (('L', 1), ('R', -1)):
        I = J[f'finger2-1.{s}'][0]; K = J[f'finger5-1.{s}'][0]
        fdir = J[f'finger3-1.{s}'][1] - J[f'finger3-1.{s}'][0]
        setattr(L, 'palm' + s, unit(sg * np.cross(K - I, fdir)))
    L.nipple = J['breast.L'][1] if np.linalg.norm(J['breast.L'][1] - J['breast.L'][0]) > 0 else J['breast.L'][0]
    L.neck_base = J['neck01'][0]
    L.head_base = J['head'][0]
    return L


def zc_at(L, y):
    return np.interp(y, L.zc_y, L.zc)


def limb_coords(p, pts, lateral_sign, front=np.array([0, 0, 1.0])):
    """Arclength s along a joint polyline, angle theta around it (0 = front, +90 = lateral, -90 = medial,
    +-180 = back) and radius."""
    pts = [np.asarray(q, float) for q in pts]
    nseg = len(pts) - 1
    best_d = np.full(len(p), np.inf)
    s = np.zeros(len(p)); th = np.zeros(len(p)); rad = np.zeros(len(p))
    acc = 0.0
    for i in range(nseg):
        a0, a1 = pts[i], pts[i + 1]
        seg = a1 - a0
        ln = np.linalg.norm(seg)
        ax = seg / ln
        t = (p - a0) @ ax
        tc = np.clip(t, 0, ln)
        d = np.linalg.norm(p - (a0 + tc[:, None] * ax), axis=1)
        te = t.copy()
        if i > 0:
            te = np.maximum(te, 0)
        if i < nseg - 1:
            te = np.minimum(te, ln)
        r = p - (a0 + te[:, None] * ax)
        f = front - (front @ ax) * ax
        f /= np.linalg.norm(f)
        l = np.cross(ax, f)
        if l[0] * lateral_sign < 0:
            l = -l
        upd = d < best_d
        best_d[upd] = d[upd]
        s[upd] = acc + te[upd]
        th[upd] = np.degrees(np.arctan2(r[upd] @ l, r[upd] @ f))
        rad[upd] = np.linalg.norm(r[upd], axis=1)
        acc += ln
    return s, th, rad


def seg_lengths(pts):
    return [float(np.linalg.norm(np.asarray(pts[i + 1]) - np.asarray(pts[i]))) for i in range(len(pts) - 1)]


def chains(gw):
    g = lambda *n: sum(gw[:, GI[x]] for x in n)
    return {
        'head': g('head'), 'neck': g('neck'),
        'torso': g('torso'),
        'pelvisL': g('pelvis.L'), 'pelvisR': g('pelvis.R'),
        'armL': g('shoulder.L', 'uarm.L', 'farm.L', 'hand.L'), 'armR': g('shoulder.R', 'uarm.R', 'farm.R', 'hand.R'),
        'legL': g('thigh.L', 'shank.L', 'foot.L'), 'legR': g('thigh.R', 'shank.R', 'foot.R'),
    }


# ----------------------------------------------------------------------------------------------
# Regions
def gluteal_fold(ax, L):
    return L.y_crotch - 0.035 + 0.3 * np.maximum(ax - 0.05, 0)


def hip_zone(p, th, L):
    """Leg-dominant skin that belongs to the lateral hip / buttock."""
    ax, y = np.abs(p[:, 0]), p[:, 1]
    glute = (np.abs(th) > 100) & (y > gluteal_fold(ax, L))
    lateral = (th > 55) & (th <= 100) & (y > L.y_crotch + 0.01 - 0.25 * (th - 55) / 45 * 0.0)
    return glute | lateral


def classify_regions(p, gw, L):
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    ax = np.abs(x)
    left = x >= 0
    ch = chains(gw)
    arm = np.where(left, ch['armL'], ch['armR'])
    leg = np.where(left, ch['legL'], ch['legR'])
    trunk = ch['torso'] + ch['pelvisL'] + ch['pelvisR']
    hn = ch['head'] + ch['neck']
    dom = np.argmax(np.stack([hn, trunk, arm, leg], 1), 1)
    front = z > zc_at(L, y)
    side = lambda l, r: np.where(left, RI[l], RI[r])
    reg = np.full(len(p), -1)

    # head & neck
    m = dom == 0
    reg[m & (ch['head'] >= ch['neck'])] = RI['head']
    reg[m & (ch['head'] < ch['neck'])] = RI['neck']

    # trunk
    yn = L.y_navel
    y_chest = yn + 0.125 - 0.5 * np.minimum(ax, 0.16)          # costal arch
    y_hipf = yn - 0.075                                       # lower belly / ASIS line
    y_back = yn + 0.07                                        # lower ribs at the back
    y_crest = yn - 0.08                                       # iliac crest at the back
    m = np.ones(len(p), bool)          # trunk labels for every point (also the fallback near the armpit)
    f = m & front
    reg[f & (y >= y_chest)] = RI['chest']
    reg[f & (y < y_chest) & (y >= y_hipf)] = RI['abdomen']
    low = f & (y < y_hipf)
    reg[low & (ax < 0.095)] = RI['hips']
    reg[low & (ax >= 0.095)] = side('leftHip', 'rightHip')[low & (ax >= 0.095)]
    bk = m & ~front
    reg[bk & (y >= y_back)] = RI['upperBack']
    reg[bk & (y < y_back) & (y >= y_crest)] = RI['lowerBack']
    low = bk & (y < y_crest)
    sac = ax < np.interp(y, [L.y_crotch, y_crest], [0.01, 0.055])
    reg[low & sac] = RI['hips']
    reg[low & ~sac] = side('leftHip', 'rightHip')[low & ~sac]
    # skin over the shoulder joint (trunk or arm) -> shoulder cap, bounded by a sphere
    S = np.where(left[:, None], L.armL[0], L.armR[0])
    Cc = S + np.stack([np.sign(x + 1e-9) * 0.012, np.full(len(x), 0.012), np.zeros(len(x))], 1)
    cap = (np.linalg.norm(p - Cc, axis=1) < 0.098) & (ax > np.abs(S[:, 0]) - 0.075)
    reg[cap] = side('leftShoulder', 'rightShoulder')[cap]
    trunk_reg = reg.copy()
    reg[dom == 0] = -1
    m = dom == 0
    reg[m & (ch['head'] >= ch['neck'])] = RI['head']
    reg[m & (ch['head'] < ch['neck'])] = RI['neck']

    # arms
    for s_, sg in (('L', 1), ('R', -1)):
        m = (dom == 2) & (left if sg > 0 else ~left)
        pts = getattr(L, 'arm' + s_)
        lu, lf, lh = seg_lengths(pts)
        s, th, _ = limb_coords(p[m], pts, sg)
        r = np.full(m.sum(), RI['leftHand' if sg > 0 else 'rightHand'])
        nm = lambda k: RI[('left' if sg > 0 else 'right') + k]
        r[s < lu + lf + 0.025] = nm('Wrist')
        r[s < lu + lf - 0.025] = nm('Forearm')
        r[s < lu + 0.035] = nm('Elbow')
        r[s < lu - 0.035] = nm('UpperArm')
        Cm = pts[0] + np.array([sg * 0.012, 0.012, 0])
        dC = np.linalg.norm(p[m] - Cm, axis=1)
        r[s < 0.3 * lu] = trunk_reg[m][s < 0.3 * lu]            # near the torso: trunk rules decide
        r[((s < 0.3 * lu) & (s > 0.0)) | ((dC < 0.098) & (s < 0.45 * lu))] = nm('Shoulder')
        reg[m] = r
    # legs
    for s_, sg in (('L', 1), ('R', -1)):
        m = (dom == 3) & (left if sg > 0 else ~left)
        pts = getattr(L, 'leg' + s_)
        lt, ls, _ = seg_lengths(pts)
        s, th, _ = limb_coords(p[m], pts, sg)
        yy, zz = y[m], z[m]
        A = pts[2]
        nm = lambda k: RI[('left' if sg > 0 else 'right') + k]
        r = np.where(np.abs(th) < 90, nm('Shin'), nm('Calf'))
        r[s < lt + 0.05] = nm('Knee')
        r[s < lt - 0.05] = nm('Thigh')
        r[(s < lt - 0.05) & hip_zone(p[m], th, L)] = nm('Hip')
        r[yy < A[1] + 0.055] = nm('Ankle')
        foot = yy < A[1] - 0.018 + 0.45 * np.maximum(zz - A[2] - 0.02, 0)
        r[foot] = nm('Foot')
        reg[m] = r
    return reg


def smooth_labels(TG, labels, nlab, iters=3, keep=None):
    """Majority filter over the triangle mesh (via shared vertices) to remove speckles."""
    from scipy import sparse
    nT = len(TG)
    nV = TG.max() + 1
    VT = sparse.csr_matrix((np.ones(nT * 3), (TG.ravel(), np.repeat(np.arange(nT), 3))), shape=(nV, nT))
    lab = labels.copy()
    for _ in range(iters):
        valid = lab < nlab
        oh = sparse.csr_matrix((np.ones(valid.sum()), (np.nonzero(valid)[0], lab[valid])), shape=(nT, nlab))
        vh = VT @ oh
        th = (VT.T @ vh).toarray()
        new = np.argmax(th, 1)
        if keep is not None:
            new[keep] = lab[keep]
        lab = np.where(valid, new, lab)
    return lab


# ----------------------------------------------------------------------------------------------
# Software renderer for previews
BG = np.array([7, 8, 11]) / 255.0


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)]) / 255.0


def project(b, yaw, W, H, fov=21.0, dist=5.6, cy=0.90, cx=0.0):
    a = np.radians(yaw)
    Ry = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
    P = b.P[b.rv_pos] @ Ry.T
    N = b.N[b.rv_pos] @ Ry.T
    z = dist - P[:, 2]
    f = (H / 2) / np.tan(np.radians(fov / 2))
    X = W / 2 + f * (P[:, 0] - cx) / z
    Y = H / 2 - f * (P[:, 1] - cy) / z
    tid, bc = rasterize(np.stack([X, Y], 1), z, b.T, W, H)
    m = tid >= 0
    t = b.T[tid[m]]
    w = bc[m][..., None]
    g = Body()
    g.mask, g.tid = m, tid[m]
    g.pos = (P[t] * w).sum(1)
    g.nrm = unit((N[t] * w).sum(1))
    g.uv = (b.uv[t] * w).sum(1)
    g.view = unit(np.array([cx, 0, dist]) + np.array([0, cy, 0]) - g.pos)
    g.W, g.H = W, H
    return g


def sample(tex, uv):
    """Bilinear texture lookup (uv v=0 at the top row)."""
    h, w = tex.shape[:2]
    x = np.clip(uv[:, 0] * w - 0.5, 0, w - 1.001)
    y = np.clip(uv[:, 1] * h - 0.5, 0, h - 1.001)
    x0, y0 = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    if tex.ndim == 3:
        fx, fy = fx[:, None], fy[:, None]
    return (tex[y0, x0] * (1 - fx) * (1 - fy) + tex[y0, x0 + 1] * fx * (1 - fy)
            + tex[y0 + 1, x0] * (1 - fx) * fy + tex[y0 + 1, x0 + 1] * fx * fy)


def compose(g, col, alpha=None, glow=None):
    img = np.tile(BG, (g.H, g.W, 1)).reshape(-1, 3)
    flat = np.nonzero(g.mask.ravel())[0]
    if alpha is None:
        img[flat] = col
    else:
        img[flat] = img[flat] * (1 - alpha[:, None]) + col * alpha[:, None]
    img = img.reshape(g.H, g.W, 3)
    if glow is not None:
        gl = np.zeros((g.H, g.W, 3))
        gl.reshape(-1, 3)[flat] = glow
        img += ndimage.gaussian_filter(gl, (6, 6, 0)) * 0.9
    return (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)


LIGHT = unit(np.array([-0.45, 0.55, 0.70]))   # upper front-left (viewer's left), camera space


def shade_regions(b, g, tri_region):
    rng = np.random.RandomState(3)
    pal = rng.uniform(0.25, 1.0, (len(REGION_IDS), 3))
    for i, r in enumerate(REGION_IDS):   # make left/right pairs clearly different
        if r.startswith('left'):
            pal[i] = pal[i] * 0.55 + np.array([0.45, 0.45, 0.45]) * 0.45
    col = pal[tri_region[g.tid]]
    lam = np.clip(g.nrm @ LIGHT, 0, 1)
    return col * (0.45 + 0.55 * lam)[:, None]


# ----------------------------------------------------------------------------------------------
# Clean label boundaries: per-vertex labels, majority smoothing, then split triangles along the
# label boundary (crossing points found by sampling the classifier along each edge).
def vertex_adjacency(TG, nV):
    from scipy import sparse
    e = np.concatenate([TG[:, [0, 1]], TG[:, [1, 2]], TG[:, [2, 0]]])
    A = sparse.csr_matrix((np.ones(len(e) * 2), (np.concatenate([e[:, 0], e[:, 1]]), np.concatenate([e[:, 1], e[:, 0]]))), shape=(nV, nV))
    A.data[:] = 1
    return A + sparse.identity(nV, format='csr')


def smooth_vertex_labels(A, lab, nlab, iters=2, fixed=None):
    from scipy import sparse
    lab = lab.copy()
    for _ in range(iters):
        oh = sparse.csr_matrix((np.ones(len(lab)), (np.arange(len(lab)), lab)), shape=(len(lab), nlab))
        new = np.asarray((A @ oh).argmax(1)).ravel()
        if fixed is not None:
            new[fixed] = lab[fixed]
        lab = new
    return lab


def split_by_labels(b, label_fn, nlab, fixed_fn=None, iters=2):
    """label_fn(pos, gw) -> int labels in [0, nlab). Returns per-triangle labels and updates b in place."""
    nV = len(b.P)
    lab = label_fn(b.P, b.GW)
    fixed = fixed_fn(b) if fixed_fn else None
    lab = smooth_vertex_labels(vertex_adjacency(b.TG, nV), lab, nlab, iters, fixed)
    TG, T = b.TG, b.T
    L3 = lab[TG]
    diff = ~((L3[:, 0] == L3[:, 1]) & (L3[:, 1] == L3[:, 2]))
    # unique geometric edges needing a crossing
    ce = []
    for i, j in ((0, 1), (1, 2), (2, 0)):
        m = diff & (L3[:, i] != L3[:, j])
        ce.append(np.sort(TG[m][:, [i, j]], 1))
    ce = np.unique(np.concatenate(ce), axis=0)
    e0, e1 = ce[:, 0], ce[:, 1]
    ts = np.linspace(0, 1, 17)[1:-1]
    labs = np.stack([label_fn(b.P[e0] * (1 - t) + b.P[e1] * t, b.GW[e0] * (1 - t) + b.GW[e1] * t) for t in ts], 1)
    ne = labs != lab[e0][:, None]
    first = np.where(ne.any(1), ne.argmax(1), len(ts) // 2)
    tcross = np.where(ne.any(1), (np.concatenate([[0.0], ts])[first] + ts[first]) / 2, 0.5)
    # new geometric vertices
    newP = b.P[e0] * (1 - tcross[:, None]) + b.P[e1] * tcross[:, None]
    newW = b.GW[e0] * (1 - tcross[:, None]) + b.GW[e1] * tcross[:, None]
    newN = unit(b.N[e0] * (1 - tcross[:, None]) + b.N[e1] * tcross[:, None])
    ekey = {(int(a), int(c)): k for k, (a, c) in enumerate(ce)}
    P = [b.P, newP]; GW = [b.GW, newW]; N = [b.N, newN]
    nG = nV + len(ce)
    rv_pos = [b.rv_pos]; uv = [b.uv]
    rkey = {}
    nR = len(b.rv_pos)
    extra_pos, extra_uv = [], []

    def cross_rv(ga, gb, ra, rb):
        nonlocal nR
        if ga > gb:
            ga, gb, ra, rb = gb, ga, rb, ra
        k = ekey[(ga, gb)]
        key = (k, ra, rb)
        if key not in rkey:
            t = tcross[k]
            extra_pos.append(nV + k)
            extra_uv.append(b.uv[ra] * (1 - t) + b.uv[rb] * t)
            rkey[key] = nR
            nR += 1
        return rkey[key]

    newT, newL, parent = [], [], []
    centers_P, centers_W, centers_N = [], [], []
    keepi = np.nonzero(~diff)[0]
    for ti in np.nonzero(diff)[0]:
        g = TG[ti]; r = T[ti]; l = L3[ti]
        if l[0] != l[1] and l[1] != l[2] and l[0] != l[2]:
            ab = cross_rv(g[0], g[1], r[0], r[1]); bc = cross_rv(g[1], g[2], r[1], r[2]); ca = cross_rv(g[2], g[0], r[2], r[0])
            wts = np.ones(3) / 3
            centers_P.append(b.P[g].mean(0)); centers_W.append(b.GW[g].mean(0)); centers_N.append(unit(b.N[g].mean(0)))
            extra_pos.append(nG + len(centers_P) - 1)
            extra_uv.append(b.uv[r].mean(0))
            c = nR; nR += 1
            tris = [(r[0], ab, c, l[0]), (r[0], c, ca, l[0]), (r[1], bc, c, l[1]), (r[1], c, ab, l[1]), (r[2], ca, c, l[2]), (r[2], c, bc, l[2])]
        else:
            k = 0 if l[1] == l[2] else (1 if l[0] == l[2] else 2)   # odd vertex
            a_, b_, c_ = k, (k + 1) % 3, (k + 2) % 3
            ab = cross_rv(g[a_], g[b_], r[a_], r[b_]); ac = cross_rv(g[a_], g[c_], r[a_], r[c_])
            tris = [(r[a_], ab, ac, l[a_]), (ab, r[b_], r[c_], l[b_]), (ab, r[c_], ac, l[b_])]
        for t0, t1, t2, ll in tris:
            newT.append((t0, t1, t2)); newL.append(ll); parent.append(ti)
    if centers_P:
        P.append(np.array(centers_P)); GW.append(np.array(centers_W)); N.append(np.array(centers_N))
    b.P = np.concatenate(P); b.GW = np.concatenate(GW).astype(np.float32); b.N = np.concatenate(N)
    b.rv_pos = np.concatenate([b.rv_pos, np.array(extra_pos, int)])
    b.uv = np.concatenate([b.uv, np.array(extra_uv).reshape(-1, 2)])
    b.T = np.concatenate([T[keepi], np.array(newT, int).reshape(-1, 3)])
    b.TG = b.rv_pos[b.T]
    parent = np.concatenate([keepi, np.array(parent, int)])
    tri_lab = np.concatenate([L3[keepi, 0], np.array(newL, int)])
    for attr in getattr(b, 'tri_attrs', []):
        setattr(b, attr, getattr(b, attr)[parent])
    return tri_lab


# ----------------------------------------------------------------------------------------------
# Muscles: "bellies" are the texture-level units (each has its own fibre focus and grooves around it);
# every belly maps to one of the public muscle ids (or none).
BELLIES = [  # name, muscle id
    ('pec_clav', 'pectorals'), ('pec_stern', 'pectorals'),
    ('delt_ant', 'deltoids'), ('delt_lat', 'deltoids'), ('delt_post', 'deltoids'),
    ('trap', 'trapezius'), ('lat', 'lats'), ('infra', 'lats'), ('serratus', 'serratus'),
    ('oblique', 'obliques'), ('rectus', 'abdominals'), ('erector', 'erectors'),
    ('glute_max', 'glutes'), ('glute_med', 'glutes'),
    ('rectus_fem', 'quadriceps'), ('vast_lat', 'quadriceps'), ('vast_med', 'quadriceps'),
    ('sartorius', 'adductors'), ('adductor', 'adductors'),
    ('biceps_fem', 'hamstrings'), ('semi', 'hamstrings'),
    ('gastro_med', 'calves'), ('gastro_lat', 'calves'), ('soleus', 'calves'),
    ('tib_ant', 'tibialis'), ('peroneus', 'tibialis'),
    ('biceps', 'biceps'), ('brachialis', 'biceps'), ('tri_lat', 'triceps'), ('tri_long', 'triceps'),
    ('flexors', 'forearmFlexors'), ('extensors', 'forearmExtensors'), ('brachiorad', 'forearmExtensors'),
    ('scm', 'neck'), ('neck_front', 'neck'),
    ('head', None), ('hand', None), ('foot', None), ('tibia', None), ('patella', None), ('wristband', None), ('groin', None),
]
BI = {n: i for i, (n, _) in enumerate(BELLIES)}
BELLY_MUSCLE = np.array([MI[m] if m else NONE for _, m in BELLIES])


def torso_angle(p, L):
    return np.degrees(np.arctan2(np.abs(p[:, 0]), p[:, 2] - zc_at(L, p[:, 1])))


def pchip(xs, ys):
    from scipy.interpolate import PchipInterpolator
    f = PchipInterpolator(np.asarray(xs, float), np.asarray(ys, float), extrapolate=False)
    lo, hi = xs[0], xs[-1]
    return lambda v: f(np.clip(v, lo, hi))


def trunk_curves(L):
    yn = L.y_navel
    c = Body()
    c.y_clav = pchip([0.015, 0.06, 0.12, 0.19], [1.446, 1.452, 1.459, 1.476])
    c.y_pec_low = pchip([0, 0.05, 0.10, 0.14, 0.17, 0.195], [yn + 0.140, yn + 0.143, yn + 0.157, yn + 0.186, yn + 0.226, yn + 0.28])
    c.x_dp = pchip([1.33, 1.38, 1.42, 1.47], [0.192, 0.18, 0.165, 0.15])
    c.w_trap = pchip([1.12, 1.25, 1.36, 1.42, 1.50], [0.0, 0.045, 0.085, 0.125, 0.21])
    c.y_lat_top = pchip([0, 0.07, 0.13, 0.17, 0.2], [1.20, 1.245, 1.30, 1.345, 1.385])
    c.tt_lat = pchip([c_ for c_ in (yn - 0.09, yn + 0.02, yn + 0.14, 1.34)], [118, 108, 92, 80])   # lat anterior border
    c.y_spine = pchip([0.055, 0.12, 0.2], [1.378, 1.415, 1.462])
    c.y_pubis = L.y_crotch + 0.045
    c.w_rect = pchip([c.y_pubis, yn - 0.05, yn, yn + 0.15], [0.034, 0.058, 0.068, 0.08])
    c.y_rect_top = yn + 0.152
    c.y_crest = yn - 0.08
    c.y_hipf = yn - 0.075
    c.y_inguinal = pchip([0.02, 0.06, 0.12], [c.y_pubis - 0.01, c.y_pubis + 0.02, yn - 0.085])
    c.sacrum = pchip([L.y_crotch, c.y_crest], [0.008, 0.05])
    return c


def organic_warp(p, amp=0.008, freq=10.0):
    """Low-frequency, left/right-symmetric displacement so belly borders are gently organic."""
    q = np.stack([np.abs(p[:, 0]), p[:, 1], p[:, 2]], 1) * freq
    d = np.stack([perlin3(q, 11), perlin3(q + 31.7, 12), perlin3(q - 17.3, 13)], 1)
    d[:, 0] *= np.sign(p[:, 0] + 1e-12)
    return p + amp * d


def classify_bellies(p, gw, L, nrm=None):
    """Belly index per point, a soft tendon/aponeurosis mask (0..1) and anatomical contour lines (0..1)."""
    p = organic_warp(p)
    n = len(p)
    x, y, z = p[:, 0], p[:, 1], p[:, 2]
    ax = np.abs(x)
    left = x >= 0
    ch = chains(gw)
    arm = np.where(left, ch['armL'], ch['armR'])
    leg = np.where(left, ch['legL'], ch['legR'])
    trunk = ch['torso'] + ch['pelvisL'] + ch['pelvisR']
    dom = np.argmax(np.stack([ch['head'] + ch['neck'], trunk, arm, leg], 1), 1)
    c = trunk_curves(L)
    yn = L.y_navel
    tt = torso_angle(p, L)
    front = tt < 90
    # trunk skin in front of the inguinal crease is treated as upper thigh
    dom[(dom == 1) & front & (y < c.y_inguinal(ax)) & (ax > 0.025)] = 3
    bel = np.full(n, BI['oblique'])
    ten = np.zeros(n)
    con = np.zeros(n)
    S = np.where(left[:, None], L.armL[0], L.armR[0])
    sx = np.abs(S[:, 0])

    # ---- trunk ----
    latm = (tt > c.tt_lat(y)) & (y < c.y_lat_top(ax) + 0.0)
    bel[latm] = BI['lat']
    bel[(tt > 100) & (y >= c.y_lat_top(ax)) & (ax > 0.05)] = BI['infra']
    ew = pchip([c.y_crest - 0.03, yn, 1.2, 1.27], [0.05, 0.068, 0.062, 0.035])(y)
    bel[(tt > 125) & (ax < ew) & (y < 1.27)] = BI['erector']
    trap = (~front & (ax < c.w_trap(y))) | ((tt > 100) & (y > c.y_spine(ax))) | ((y > c.y_clav(ax) + 0.014) & (ax < sx - 0.03))
    bel[trap] = BI['trap']
    wave = 0.5 * (1 - np.cos(2 * np.pi * (tt - 44) / 19.0))     # serratus digitations
    serr_low = yn + 0.102 + 0.015 * wave + 0.0005 * (tt - 50)
    serr = (tt > 48) & (tt < c.tt_lat(y)) & (y > serr_low) & (y < 1.345) & (ax > 0.1)
    bel[serr] = BI['serratus']
    rect = (tt < 60) & (ax < c.w_rect(y)) & (y > c.y_pubis) & (y < c.y_rect_top)
    bel[rect] = BI['rectus']
    pec = (tt < 95) & (y > c.y_pec_low(ax)) & (y < c.y_clav(ax) + 0.014) & (ax < c.x_dp(y))
    bel[pec] = BI['pec_stern']
    bel[pec & (y > c.y_clav(ax) - 0.042 + 0.1 * np.maximum(ax - 0.12, 0))] = BI['pec_clav']
    Cc = S + np.stack([np.sign(x + 1e-9) * 0.01, np.full(n, 0.015), np.zeros(n)], 1)
    delt = (np.linalg.norm(p - Cc, axis=1) < 0.092) & (ax > sx - 0.065) & ~pec & (dom != 0) & (y > S[:, 1] - 0.045)
    bel[delt] = np.where(tt[delt] < 62, BI['delt_ant'], np.where(tt[delt] < 118, BI['delt_lat'], BI['delt_post']))
    bel[front & (dom == 1) & (y < c.y_pubis + 0.005) & (ax < 0.045)] = BI['groin']

    # ---- head & neck ----
    hd = dom == 0
    bel[hd & (ch['head'] >= ch['neck'])] = BI['head']
    nk = hd & (ch['head'] < ch['neck'])
    if nk.any():
        _, thn, _ = limb_coords(p[nk], [L.neck_base + np.array([0, -0.08, 0.02]), L.head_base + np.array([0, 0.02, 0.03])], 1)
        thn = np.abs(thn)
        yy = y[nk]
        tc = np.interp(yy, [1.45, 1.64], [30, 112])
        b_ = np.where(thn < tc - 26, BI['neck_front'], np.where(thn < tc + 26, BI['scm'], BI['trap']))
        bel[nk] = b_

    # ---- arms ----
    for s_, sg in (('L', 1), ('R', -1)):
        m = (dom == 2) & (left if sg > 0 else ~left)
        if not m.any():
            continue
        pts = getattr(L, 'arm' + s_)
        lu, lf, lh = seg_lengths(pts)
        s, th, rad = limb_coords(p[m], pts, sg)
        b_ = np.full(m.sum(), BI['hand'])
        t_ = np.zeros(m.sum())
        # forearm: palm-side reference blends from antero-medial (elbow) to the palm normal (wrist)
        E, Wr = pts[1], pts[2]
        axf = unit(Wr - E)
        palm = getattr(L, 'palm' + s_)
        pm = unit(palm - (palm @ axf) * axf)
        fr = np.array([0, 0, 1.0]); fr = unit(fr - (fr @ axf) * axf)
        lat = unit(np.cross(axf, fr)); lat = lat if lat[0] * sg > 0 else -lat
        am = unit(fr - 0.35 * lat)
        u = np.clip((s - lu) / lf, 0, 1)[:, None]
        ref = unit(am * (1 - u) + pm * u)
        pp = p[m]
        foot_ = E + np.clip(((pp - E) @ axf), 0, lf)[:, None] * axf
        rr = unit(pp - foot_)
        side_flex = (rr * ref).sum(1)
        side_lat = (rr * lat).sum(1)
        fa = s < lu + lf - 0.03
        b_[fa] = np.where(side_flex[fa] > -0.05, BI['flexors'], BI['extensors'])
        br = fa & (s < lu + 0.62 * lf) & (side_lat > 0.25) & (side_flex > -0.45)
        b_[br] = BI['brachiorad']
        wb = (s >= lu + lf - 0.03) & (s < lu + lf + 0.02)
        b_[wb] = BI['wristband']
        t_ = np.maximum(t_, 0.22 * smoothstep(lu + lf - 0.045, lu + lf - 0.02, s) * (1 - smoothstep(lu + lf + 0.0, lu + lf + 0.025, s)))
        ua = s < lu + 0.0
        b_[ua] = np.where(np.abs(th[ua]) < 80, BI['biceps'], np.where(th[ua] > 0, BI['tri_lat'], BI['tri_long']))
        b_[ua & (th > 45) & (th < 85) & (s > 0.55 * lu)] = BI['brachialis']
        b_[ua & (np.abs(th) >= 80) & (np.abs(th) < 150) & (th > 0)] = BI['tri_lat']
        b_[ua & ((th >= 150) | (th <= -80))] = BI['tri_long']
        dl = lu * (0.24 + 0.30 * np.maximum(0, np.cos(np.radians(th - 90))) ** 1.5)
        dm_ = s < dl
        b_[dm_] = np.where(np.abs(th[dm_]) < 45, BI['delt_ant'], np.where(np.abs(th[dm_]) < 125, np.where(th[dm_] > 0, BI['delt_lat'], BI['delt_ant']), BI['delt_post']))
        b_[dm_ & (th < -45) & (th > -125)] = np.where(th[dm_ & (th < -45) & (th > -125)] > -85, BI['biceps'], BI['tri_long'])
        # triceps aponeurosis and olecranon
        t_ = np.maximum(t_, smoothstep(lu - 0.09, lu - 0.055, s) * smoothstep(148, 168, np.abs(th)) * (1 - smoothstep(lu + 0.0, lu + 0.02, s)) * 0.35)
        keep_trunk = (pp[:, 1] > pts[0][1] - 0.01) & (th < -40) & (s < 0.3 * lu)
        b_[keep_trunk] = bel[m][keep_trunk]
        bel[m] = b_
        ten[m] = np.maximum(ten[m], t_)
        # dorsum of the hand: pale tendons
        hm = s > lu + lf + 0.02
        dors = np.clip(-side_flex, 0, 1)
        tmp = ten[m]; tmp[hm] = np.maximum(tmp[hm], 0.3 * smoothstep(0.1, 0.5, dors[hm])); ten[m] = tmp

    # ---- legs ----
    for s_, sg in (('L', 1), ('R', -1)):
        m = (dom == 3) & (left if sg > 0 else ~left)
        if not m.any():
            continue
        pts = getattr(L, 'leg' + s_)
        lt, ls, _ = seg_lengths(pts)
        s, th, rad = limb_coords(p[m], pts, sg)
        pp = p[m]
        yy = pp[:, 1]
        axx = np.abs(pp[:, 0])
        b_ = np.full(m.sum(), BI['foot'])
        t_ = np.zeros(m.sum())
        A = pts[2]
        # thigh
        th_ = s < lt + 0.005
        tb = np.interp(s, [0.04, lt - 0.06], [38, -112])
        w = 11
        q = np.clip(s / lt, 0, 1)
        vl_b = 142 - 30 * q                                   # biceps femoris runs obliquely to the fibula head
        am_b = -162 + 34 * q                                  # semitendinosus / adductor border
        bt = np.where(th > vl_b, BI['biceps_fem'], BI['vast_lat'])
        bt = np.where((th <= vl_b) & (th > 22), BI['vast_lat'], bt)
        bt = np.where((th <= 22) & (th > tb + w), BI['rectus_fem'], bt)
        bt = np.where((th <= tb + w) & (th > tb - w), BI['sartorius'], bt)
        bt = np.where((th <= tb - w) & (th > am_b), BI['adductor'], bt)
        split = np.where(s > 0.3 * lt, 179 - 14 * q, 200)
        bt = np.where((th <= am_b) | (th > split), BI['semi'], bt)
        bt = np.where((th > vl_b) & (th <= split), BI['biceps_fem'], bt)
        vm = (th <= -5) & (th > tb + w) & (s > lt * (0.6 + 0.35 * ((th + 50) / 45) ** 2))
        bt = np.where(vm, BI['vast_med'], bt)
        rf_lo = (th <= 22) & (th > -5) & (s > lt - 0.09)
        bt = np.where(rf_lo & (th > tb + w), BI['vast_med'] if False else BI['rectus_fem'], bt)
        b_[th_] = bt[th_]
        # lower leg
        ll = (s >= lt + 0.005) & (yy > A[1] + 0.05)
        u = (s - lt) / ls
        latg = (th > 115) & (th <= 172)
        medg = (th > 172) | (th <= 0)
        dmed = (th + 150 + 180) % 360 - 180
        u_end = np.where(latg, 0.50 - 0.10 * ((th - 145) / 35) ** 2, 0.60 - 0.12 * (dmed / 70) ** 2)
        bl = np.where(latg, BI['gastro_lat'], BI['gastro_med'])
        bl = np.where((latg | medg) & (u > u_end), BI['soleus'], bl)
        bl = np.where((th <= 115) & (th > 85), BI['peroneus'], bl)
        bl = np.where((th <= 85) & (th > 0), BI['tib_ant'], bl)
        b_[ll] = bl[ll]
        b_[(s >= lt + 0.005) & (yy <= A[1] + 0.05)] = BI['foot']
        # tendons: patella & ligament, quadriceps tendon, IT band, achilles, foot dorsum
        arc = np.radians(th) * rad
        pat = ((s - (lt - 0.012)) / 0.031) ** 2 + (arc / 0.025) ** 2
        t_ = np.maximum(t_, 0.5 * (1 - smoothstep(0.5, 1.15, pat)))
        cm = con[m]; cm = np.maximum(cm, (1 - smoothstep(0.03, 0.08, np.abs(np.sqrt(pat) - 1.0))) * (s > lt - 0.07)); con[m] = cm
        t_ = np.maximum(t_, 0.45 * (1 - smoothstep(0.004, 0.011, np.abs(arc))) * smoothstep(lt, lt + 0.015, s) * (1 - smoothstep(lt + 0.05, lt + 0.075, s)))
        t_ = np.maximum(t_, 0.3 * (1 - smoothstep(0.01, 0.024, np.abs(arc))) * smoothstep(lt - 0.08, lt - 0.045, s) * (1 - smoothstep(lt - 0.03, lt - 0.01, s)))
        itb = np.interp(s, [0.15, 0.25, lt - 0.05], [0.02, 0.015, 0.011])
        t_ = np.maximum(t_, 0.28 * (1 - smoothstep(itb * 0.4, itb + 0.01, np.abs(np.radians(th - 98) * rad))) * smoothstep(0.15, 0.26, s) * (1 - smoothstep(lt - 0.05, lt - 0.01, s)) * (th > 50))
        ach = smoothstep(0.66, 0.78, u) * (1 - smoothstep(0.007, 0.013, np.abs(np.radians(np.abs(th) - 180) * rad)))
        t_ = np.maximum(t_, 0.72 * ach * (s >= lt + 0.05) * (s <= lt + ls) * smoothstep(A[1] - 0.045, A[1] - 0.02, yy))
        t_ = np.maximum(t_, 0.2 * smoothstep(0.08, 0.2, u) * (1 - smoothstep(0.005, 0.014, np.abs(np.radians(th + 22) * rad))) * (s >= lt + 0.005))
        fm = b_ == BI['foot']
        if nrm is not None:
            t_[fm] = np.maximum(t_[fm], 0.35 * smoothstep(0.2, 0.6, nrm[m][fm, 1]) * (pp[fm, 2] > A[2] - 0.01) * (1 - smoothstep(A[2] + 0.07, A[2] + 0.1, pp[fm, 2])))
        b_[(t_ > 0.35) & (np.abs(th) < 60) & (s > lt - 0.06) & (s < lt + 0.08)] = BI['patella']
        bel[m] = b_
        ten[m] = np.maximum(ten[m], t_)

    # ---- hips & buttocks (trunk or leg skin, one continuous rule set) ----
    hipd = (dom == 1) | (dom == 3)
    y_fold = gluteal_fold(ax, L)
    y_iliac = pchip([0, 45, 70, 95, 130, 180], [yn - 0.10, yn - 0.095, yn - 0.065, yn - 0.05, yn - 0.065, yn - 0.085])(tt)
    gmax_top = pchip([0.02, 0.08, 0.13, 0.17, 0.2], [yn - 0.085, yn - 0.09, yn - 0.112, yn - 0.145, yn - 0.18])(ax)
    sac = (tt > 140) & (y < c.y_crest) & (ax < c.sacrum(y)) & hipd
    gmax = hipd & (tt > 100) & (y < gmax_top) & (y > y_fold) & ~sac
    gmed = hipd & (y < y_iliac) & (((tt > 100) & (y >= gmax_top)) | ((tt <= 100) & (tt > 56) & (y > L.y_crotch + 0.035 + 0.0008 * (100 - tt))))
    gmed &= ~rect & (ax > 0.06)
    bel[gmed] = BI['glute_med']
    bel[gmax] = BI['glute_max']
    bel[sac] = BI['glute_max']

    # ---- trunk tendons / bones ----
    tr = (dom == 1)
    la = (1 - smoothstep(0.0025, 0.006, ax)) * rect
    ten = np.maximum(ten, 0.75 * la)
    con = np.maximum(con, (1 - smoothstep(0.001, 0.0028, ax)) * rect)
    for y0 in (yn + 0.004, yn + 0.056, yn + 0.106):
        yl = y0 + 0.014 * (ax / 0.07) ** 2
        ten = np.maximum(ten, 0.7 * (1 - smoothstep(0.002, 0.005, np.abs(y - yl))) * rect * (1 - smoothstep(0.75, 1.0, ax / c.w_rect(y))))
        con = np.maximum(con, 0.9 * (1 - smoothstep(0.001, 0.0028, np.abs(y - yl))) * rect)
    apo = front & (dom == 1) & (bel == BI['oblique']) & (y < yn + 0.07)
    wr_ = c.w_rect(y)
    ten = np.maximum(ten, 0.16 * apo * (1 - smoothstep(wr_ + 0.004, wr_ + 0.018, ax)))
    ten = np.maximum(ten, 0.35 * (tt < 90) * (1 - smoothstep(0.002, 0.008, ax)) * (y > c.y_pec_low(ax) - 0.01) * (y < 1.45) * (dom == 1))  # sternum
    clav = (1 - smoothstep(0.002, 0.009, np.abs(y - c.y_clav(ax)))) * (ax > 0.012) * (ax < sx - 0.02) * (tt < 95)
    ten = np.maximum(ten, 0.3 * clav * (dom != 2))
    con = np.maximum(con, (1 - smoothstep(0.001, 0.0028, np.abs(y - c.y_clav(ax)))) * (ax > 0.012) * (ax < sx - 0.02) * (tt < 95) * (dom != 2))
    con = np.maximum(con, 0.7 * (1 - smoothstep(0.001, 0.0028, np.abs(y - c.y_spine(ax)))) * (ax > 0.06) * (ax < sx - 0.01) * (tt > 100) * (dom != 2))
    spine = (1 - smoothstep(0.002, 0.009, np.abs(y - c.y_spine(ax)))) * (ax > 0.06) * (ax < sx - 0.01) * (tt > 100)
    ten = np.maximum(ten, 0.32 * spine * (dom != 2))
    dia = ax / 0.03 + np.abs(y - 1.47) / 0.06
    ten = np.maximum(ten, 0.4 * (1 - smoothstep(0.5, 1.05, dia)) * (tt > 100))
    tlf = ax / 0.08 + np.abs(y - (yn - 0.06)) / 0.12
    ten = np.maximum(ten, 0.1 * (1 - smoothstep(0.5, 1.05, tlf)) * (tt > 110) * (dom == 1))
    sac_soft = (1 - smoothstep(0.6, 1.1, ax / np.maximum(c.sacrum(y), 1e-3))) * smoothstep(L.y_crotch + 0.04, L.y_crotch + 0.1, y) * (1 - smoothstep(c.y_crest - 0.02, c.y_crest + 0.03, y))
    ten = np.maximum(ten, 0.12 * sac_soft * (tt > 140))
    return bel, np.clip(ten, 0, 1), np.clip(con, 0, 1)


# Fibre layout per belly (left side; mirrored for the right): stripes are constant along rays from a
# focus F, measured as the angle around an axis through F. Fan-shaped muscles use their mean surface
# normal as the axis (fibres converge on F); limb muscles use the limb axis (fibres run along it).
def belly_fibres(L):
    F, AX = {}, {}
    S, E, Wr, Ft = [np.asarray(q) for q in L.armL]
    H, K, A, Toe = [np.asarray(q) for q in L.legL]
    far = lambda a, d, k=2.5: a + unit(np.asarray(d, float)) * k
    F['pec_clav'] = S + np.array([-0.02, -0.05, 0.07])
    F['pec_stern'] = S + np.array([-0.02, -0.07, 0.07])
    D = S + 0.48 * (E - S) + np.array([0.03, 0, 0])
    F['delt_ant'] = F['delt_lat'] = F['delt_post'] = D
    F['trap'] = np.array([S[0] - 0.035, 1.45, -0.09])
    F['lat'] = np.array([S[0] - 0.03, 1.33, -0.03])
    F['infra'] = S + np.array([0.0, -0.01, -0.03])
    F['serratus'] = np.array([0.07, 1.37, -0.14])
    F['oblique'] = far(np.array([0.12, 1.05, 0.02]), [-0.55, -0.62, 0.55])
    F['rectus'] = np.array([0.04, -2.5, 0.08])
    F['erector'] = np.array([0.035, -2.5, -0.12])
    F['glute_max'] = np.array([H[0] + 0.07, L.y_crotch - 0.08, H[2] - 0.02])
    F['glute_med'] = np.array([H[0] + 0.07, L.y_crotch + 0.0, H[2]])
    pat = K + np.array([0, -0.02, 0.07])
    F['vast_lat'] = F['vast_med'] = pat
    F['sartorius'] = far(np.array([H[0], H[1], 0.06]), (K + np.array([-0.05, 0, -0.03])) - np.array([H[0] + 0.05, H[1], 0.06]), 2.0)
    F['adductor'] = np.array([0.03, L.y_crotch + 0.03, 0.03])
    F['gastro_med'] = F['gastro_lat'] = A + np.array([0, 0.12, -0.08])
    F['soleus'] = A + np.array([0, 0.02, -0.07])
    F['tri_lat'] = F['tri_long'] = E + np.array([0, 0.0, -0.05])
    F['scm'] = far(np.array([0.025, 1.45, 0.05]), np.array([0.025, 1.45, 0.05]) - np.array([0.065, 1.665, -0.03]), 2.0)
    F['neck_front'] = np.array([0.0, -2.0, 0.05])
    for k in ('rectus_fem', 'biceps_fem', 'semi'):
        F[k], AX[k] = H, unit(K - H)
    for k in ('tib_ant', 'peroneus', 'tibia'):
        F[k], AX[k] = K, unit(A - K)
    for k in ('biceps', 'brachialis'):
        F[k], AX[k] = S, unit(E - S)
    for k in ('flexors', 'extensors', 'brachiorad'):
        F[k], AX[k] = E, unit(Wr - E)
    for k in ('head', 'hand', 'foot', 'patella', 'wristband', 'groin'):
        F[k] = np.array([0.05, -2.5, 0.0])
    return [(F[n], AX.get(n)) for n, _ in BELLIES]


# ----------------------------------------------------------------------------------------------
# Texture baking
def perlin3(p, seed=0):
    rng = np.random.RandomState(seed)
    perm = rng.permutation(256)
    perm = np.concatenate([perm, perm]).astype(np.int64)
    grads = unit(rng.normal(size=(256, 3)))
    pi = np.floor(p).astype(np.int64)
    pf = p - pi
    u = pf * pf * pf * (pf * (pf * 6 - 15) + 10)
    pi &= 255
    out = np.zeros(len(p))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                h = perm[perm[perm[pi[:, 0] + dx] + pi[:, 1] + dy] + pi[:, 2] + dz]
                g = grads[h]
                d = pf - np.array([dx, dy, dz])
                w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                out += w * (g * d).sum(1)
    return out * 1.6


def bake_texels(b, size):
    P2 = b.uv * size
    tid, bc = rasterize(P2, None, b.T, size, size)
    mask = tid >= 0
    t = b.T[tid[mask]]
    w = bc[mask][..., None].astype(np.float64)
    tx = Body()
    tx.mask = mask
    tx.pos = (b.P[b.rv_pos[t]] * w).sum(1)
    tx.nrm = unit((b.N[b.rv_pos[t]] * w).sum(1))
    tx.gw = (b.GW[b.rv_pos[t]] * w).sum(1)
    tx.size = size
    return tx


def label_boundary_points(tx, lab):
    """3D midpoints between neighbouring texels (same UV island) whose labels differ."""
    size = tx.size
    L2 = np.full((size, size), -1, np.int64)
    L2[tx.mask] = lab
    idx = np.full((size, size), -1, np.int64)
    idx[tx.mask] = np.arange(tx.mask.sum())
    pts = []
    for dy, dx in ((0, 1), (1, 0), (1, 1), (1, -1)):
        ra, rb = slice(0, size - dy), slice(dy, size)
        ca, cb = (slice(0, size - dx), slice(dx, size)) if dx >= 0 else (slice(-dx, size), slice(0, size + dx))
        a, bb_ = idx[ra, ca], idx[rb, cb]
        a, bb_ = a.ravel(), bb_.ravel()
        ok = (a >= 0) & (bb_ >= 0)
        a, bb_ = a[ok], bb_[ok]
        diff = lab[a] != lab[bb_]
        a, bb_ = a[diff], bb_[diff]
        near = np.linalg.norm(tx.pos[a] - tx.pos[bb_], axis=1) < 0.004
        pts.append((tx.pos[a[near]] + tx.pos[bb_[near]]) / 2)
    return np.concatenate(pts)


def fill_uncovered(img, mask, margin=None, flat=None):
    """Dilate across UV seams: empty texels take the nearest covered texel's value (within `margin`
    texels if given; beyond that `flat`)."""
    dist, idx = ndimage.distance_transform_edt(~mask, return_distances=True, return_indices=True)
    out = img[idx[0], idx[1]]
    if margin is not None:
        out[dist > margin] = flat
    return out


def gradient_map(v, stops):
    xs = np.array([s_[0] for s_ in stops])
    cols = np.array([hexc(s_[1]) for s_ in stops])
    return np.stack([np.interp(v, xs, cols[:, i]) for i in range(3)], 1)


def make_textures(b, L, size=TEX):
    tx = bake_texels(b, size)
    p, nrm = tx.pos, tx.nrm
    bel, ten, con = classify_bellies(p, tx.gw, L, nrm)
    mus = BELLY_MUSCLE[bel]
    print('  texels', len(p))
    kb = cKDTree(label_boundary_points(tx, bel))
    kg = cKDTree(label_boundary_points(tx, mus))
    d_b = kb.query(p, workers=-1)[0]
    d_g = kg.query(p, workers=-1)[0]
    # fibres: stripes = noise of (angle around the belly's fibre axis) -> constant along each fibre
    fib = belly_fibres(L)
    nb = len(BELLIES)
    Fb, E1, E2, Ab, R0, AXIAL = (np.zeros((nb, 3)), np.zeros((nb, 3)), np.zeros((nb, 3)), np.zeros((nb, 3)), np.ones(nb), np.zeros(nb, bool))
    for i, (Fi, Ai) in enumerate(fib):
        m = (bel == i) & (p[:, 0] >= 0)
        cen = p[m].mean(0) if m.any() else Fi + np.array([0.1, 0, 0])
        A_ = Ai if Ai is not None else (unit(nrm[m].mean(0)) if m.any() else np.array([0, 0, 1.0]))
        r = cen - Fi
        r = r - (r @ A_) * A_
        e1 = unit(r) if np.linalg.norm(r) > 1e-6 else unit(np.cross(A_, [0.3, 0.5, 0.8]))
        Fb[i], E1[i], E2[i], Ab[i] = Fi, e1, np.cross(A_, e1), A_
        R0[i] = max(np.linalg.norm(r), 0.02)
        AXIAL[i] = Ai is not None
    mir = np.where(p[:, 0] >= 0, 1.0, -1.0)[:, None] * np.array([1, 0, 0]) + np.array([0, 1, 1])
    rel = p - Fb[bel] * mir
    a_ = (rel * (E1[bel] * mir)).sum(1)
    b_ = (rel * (E2[bel] * mir)).sum(1)
    uu = np.arctan2(b_, a_) * R0[bel]
    vv = np.where(AXIAL[bel], (rel * (Ab[bel] * mir)).sum(1), np.hypot(a_, b_))
    sd = bel * 7.31
    fine = (perlin3(np.stack([uu / 0.0024, vv / 0.035, sd], 1), 1) * 0.65
            + perlin3(np.stack([uu / 0.0012, vv / 0.02, sd + 3.3], 1), 2) * 0.35)
    bundle = perlin3(np.stack([uu / 0.008, vv / 0.07, sd + 9.1], 1), 3)
    along = perlin3(p * 38.0, 4)
    blob = perlin3(p * 9.0, 5)
    sep = 1 - smoothstep(0.03, 0.14, np.abs(bundle))
    bulge = smoothstep(0.0, 0.03, d_b)
    groove = (1 - smoothstep(0.0, 0.006, d_b)) ** 1.8
    ggroove = (1 - smoothstep(0.0, 0.01, d_g)) ** 1.8
    edge = 1 - smoothstep(0.0, 0.028, d_b)
    I = 0.56 + 0.16 * fine + 0.04 * along + 0.05 * blob + 0.1 * bulge - 0.22 * sep * (0.6 + 0.4 * along)
    I = I * (1 - 0.3 * edge) * (1 - 0.35 * groove) * (1 - 0.5 * ggroove)
    col = gradient_map(np.clip(I, 0, 1), [(0.0, '#220303'), (0.22, '#4E0909'), (0.42, '#8E1414'), (0.62, '#B0261F'), (0.8, '#D6453A'), (1.0, '#E3614C')])
    none = BELLY_MUSCLE[bel] == NONE
    muted = gradient_map(np.clip(0.5 + 0.12 * blob + 0.05 * fine + 0.1 * along, 0, 1), [(0.0, '#3C0D0C'), (0.5, '#6E1D1A'), (1.0, '#8A2B25')])
    muted = muted * (1 - 0.45 * groove * (bel != BI['head']))[:, None]
    col = np.where(none[:, None], muted, col)
    ivory = gradient_map(np.clip(0.6 + 0.25 * fine + 0.1 * along, 0, 1), [(0.0, '#B9A58C'), (0.6, '#E4D7C0'), (1.0, '#F2EADB')])
    tt = ten[:, None] * (1 - 0.5 * groove[:, None])
    col = col * (1 - tt) + ivory * tt
    # anatomy lines (for the blue look)
    nohead = np.where(bel == BI['head'], MI['neck'], mus)
    d_l = cKDTree(label_boundary_points(tx, nohead)).query(p, workers=-1)[0]
    lines = np.maximum(np.exp(-(d_l / 0.0012) ** 2), 0.35 * np.exp(-(d_b / 0.0010) ** 2))
    lines[bel == BI['head']] = 0
    lines = np.maximum(lines, con)
    # output images
    det = np.zeros((size, size)); det[tx.mask] = lines
    det = fill_uncovered(det, tx.mask, 12, 0.0)
    det = ndimage.gaussian_filter(det, 0.8)
    det = np.clip(det / max(det.max(), 1e-6) * 1.0, 0, 1)
    mimg = np.zeros((size, size, 3)); mimg[tx.mask] = col
    mimg = fill_uncovered(mimg, tx.mask, 12, col.mean(0))
    tx.bel, tx.ten = bel, ten
    mimg = ndimage.gaussian_filter(mimg, (0.35, 0.35, 0))
    return (det * 255 + 0.5).astype(np.uint8), (np.clip(mimg, 0, 1) * 255 + 0.5).astype(np.uint8), tx


# ----------------------------------------------------------------------------------------------
# Anchors
def surface_anchor(P, N, c, d):
    """Point on the surface near centroid c, seen from direction d (the front-most point along d close
    to the line through c)."""
    d = unit(np.asarray(d, float))
    rel = P - c
    perp = np.linalg.norm(rel - (rel @ d)[:, None] * d, axis=1)
    ok = (N @ d) > 0.15
    if not ok.any():
        ok[:] = True
    perp = np.where(ok, perp, np.inf)
    near = perp < perp.min() + 0.012
    i = np.argmax(np.where(near, P @ d, -np.inf))
    nb = np.linalg.norm(P - P[i], axis=1) < 0.02
    return P[i], unit(N[nb].mean(0))


REGION_VIEW = {'upperBack': (0, 0, -1), 'lowerBack': (0, 0, -1), 'rightCalf': (0, 0, -1), 'leftCalf': (0, 0, -1),
               'rightHand': (-0.7, 0, 0.7), 'leftHand': (0.7, 0, 0.7), 'rightFoot': (0, 0.5, 0.85), 'leftFoot': (0, 0.5, 0.85),
               'rightShoulder': (-0.45, 0.25, 0.85), 'leftShoulder': (0.45, 0.25, 0.85),
               'rightHip': (-0.8, 0, -0.6), 'leftHip': (0.8, 0, -0.6)}
# muscle views are for the person's left (+x) instance
MUSCLE_VIEW = {'trapezius': (0, 0.3, -1), 'deltoids': (0.8, 0.2, 0.3), 'triceps': (0.3, 0, -1), 'forearmExtensors': (0.7, 0, -0.7),
               'forearmFlexors': (-0.2, 0, 1), 'obliques': (0.6, 0, 0.8), 'serratus': (0.8, 0, 0.5), 'lats': (0.4, 0, -1),
               'erectors': (0, 0, -1), 'glutes': (0, 0, -1), 'hamstrings': (0, 0, -1), 'calves': (0, 0, -1), 'adductors': (-0.5, 0, 0.85)}


def tri_area(P, TG):
    return 0.5 * np.linalg.norm(np.cross(P[TG[:, 1]] - P[TG[:, 0]], P[TG[:, 2]] - P[TG[:, 0]]), axis=1)


MIDLINE = {'head', 'neck', 'chest', 'abdomen', 'upperBack', 'lowerBack', 'hips', 'trapezius', 'abdominals', 'erectors'}


def anchors(b, labels, names, views, left_only=False):
    """Per label: surface anchor, outward normal, rough radius. Bilateral muscles use the person's
    left (+x) instance; midline items are centred on x = 0."""
    P, N, TG = b.P, b.N, b.TG
    area = tri_area(P, TG)
    cen = P[TG].mean(1)
    out = []
    for i, name in enumerate(names):
        m = labels == i
        if left_only and name not in MIDLINE:
            m = m & (cen[:, 0] > 0)
        c = (cen[m] * area[m, None]).sum(0) / area[m].sum()
        if name in MIDLINE:
            c[0] = 0.0
        d = np.array(views.get(name, (0, 0, 1)), float)
        if not left_only and name.startswith('right'):
            d[0] = -abs(d[0])
        vid = np.unique(TG[m])
        a, n = surface_anchor(P[vid], N[vid], c, d)
        ext = P[vid].max(0) - P[vid].min(0)
        out.append((a, n, float(np.clip(0.5 * np.linalg.norm(ext), 0.05, 0.45))))
    return out


# ----------------------------------------------------------------------------------------------
# Output
def write_bin(path, pos, nrm, uv, groups, muscle, tris):
    with open(path, 'wb') as f:
        f.write(b'BLB2')
        f.write(struct.pack('<III', len(pos), len(tris), len(groups)))
        f.write(pos.astype('<f4').tobytes())
        f.write(nrm.astype('<f4').tobytes())
        f.write(uv.astype('<f4').tobytes())
        for g in groups:
            f.write(struct.pack('<III', *g))
        f.write(muscle.astype(np.uint8).tobytes())
        f.write(tris.astype('<u4').tobytes())


def rnd(v, k=4):
    return [round(float(x), k) for x in v]


# ----------------------------------------------------------------------------------------------
# Preview looks
def blue_look(g, det):
    lam = np.clip(g.nrm @ LIGHT, 0, 1)
    ndv = np.clip((g.nrm * g.view).sum(1), 0, 1)
    fres = (1 - ndv) ** 2.4
    base = hexc('#0A2A9E') * (0.38 + 0.62 * lam)[:, None]
    rim = (hexc('#6FA8FF') * (1 - fres[:, None] ** 1.5) + hexc('#BFE0FF') * fres[:, None] ** 1.5) * (fres * 1.15)[:, None]
    lines = hexc('#6FE0FF') * (0.25 * sample(det, g.uv))[:, None]
    col = base + rim + lines
    alpha = np.clip(0.8 + 0.2 * fres, 0, 1)
    return col, alpha, rim * 0.5 + lines * 0.6


def muscle_look(g, alb):
    lam = np.clip(g.nrm @ LIGHT, 0, 1)
    h = unit(LIGHT + g.view)
    spec = np.clip((g.nrm * h).sum(1), 0, 1) ** 28 * 0.16
    fill = np.clip(g.nrm @ unit(np.array([0.6, 0.1, 0.5])), 0, 1) * 0.12
    return sample(alb, g.uv) * (0.24 + 0.8 * lam + fill)[:, None] + spec[:, None]


def region_palette():
    import colorsys
    pal = np.zeros((len(REGION_IDS), 3))
    base = {}
    k = 0
    for i, r in enumerate(REGION_IDS):
        key = r.replace('left', '').replace('right', '').lower()
        if key not in base:
            base[key] = k
            k += 1
        h = (base[key] * 0.618034) % 1.0
        light = 0.62 if r.startswith('left') else 0.5
        pal[i] = colorsys.hls_to_rgb(h, light, 0.75)
    return pal


def render_previews(b, reg, det, alb):
    W, H = 900, 1400
    detf = det.astype(np.float64) / 255.0
    albf = alb.astype(np.float64) / 255.0
    for name, yaw in (('front', 0), ('back', 180), ('34', -35)):
        g = project(b, yaw, W, H)
        col, alpha, glow = blue_look(g, detf)
        Image.fromarray(compose(g, col, alpha, glow)).save(os.path.join(DESIGN, f'preview-{name}.png'), optimize=True)
    for name, yaw in (('front', 0), ('back', 180)):
        g = project(b, yaw, W, H)
        Image.fromarray(compose(g, muscle_look(g, albf))).save(os.path.join(DESIGN, f'preview-muscle-{name}.png'), optimize=True)
    pal = region_palette()
    ims = []
    for yaw in (0, 180):
        g = project(b, yaw, W, H)
        lam = np.clip(g.nrm @ LIGHT, 0, 1)
        ims.append(compose(g, pal[reg[g.tid]] * (0.55 + 0.45 * lam)[:, None]))
    Image.fromarray(np.concatenate(ims, 1)).save(os.path.join(DESIGN, 'preview-regions.png'), optimize=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    print('building mesh')
    b = build_mesh()
    L = landmarks(b)
    b.tri_attrs = ['tri_eye']
    reg = split_by_labels(b, lambda p, gw: classify_regions(p, gw, L), len(REGION_IDS))
    reg[b.tri_eye] = RI['head']
    print(f'  vertices {len(b.rv_pos)}, triangles {len(b.T)}')
    assert len(b.rv_pos) <= 60000
    # muscles per triangle (centroid classification, majority-smoothed)
    cen = b.P[b.TG].mean(1)
    gw = b.GW[b.TG].mean(1)
    nt = unit(b.N[b.TG].mean(1))
    bel, _, _ = classify_bellies(cen, gw, L, nt)
    mus = BELLY_MUSCLE[bel].astype(np.int64)
    mus[b.tri_eye] = NONE
    nm = len(MUSCLES)
    mus = np.where(mus == NONE, nm, mus)
    mus = smooth_labels(b.TG, mus, nm + 1, iters=2)
    mus = np.where(mus == nm, NONE, mus)
    # sort triangles by region
    order = np.argsort(reg, kind='stable')
    b.T, reg, mus, b.TG = b.T[order], reg[order], mus[order], b.TG[order]
    groups = []
    for r in range(len(REGION_IDS)):
        idx = np.nonzero(reg == r)[0]
        assert len(idx), REGION_IDS[r]
        groups.append((r, int(idx[0]), len(idx)))
    pos, nrm = b.P[b.rv_pos], b.N[b.rv_pos]
    write_bin(os.path.join(OUT, 'body.bin'), pos, nrm, b.uv, groups, mus, b.T)
    ra = anchors(b, reg, REGION_IDS, REGION_VIEW)
    ma = anchors(b, np.where(mus == NONE, -1, mus), [m for m, _ in MUSCLES], MUSCLE_VIEW, left_only=True)
    meta = {
        'source': 'MakeHuman 1.x base mesh + macro targets (CC0 1.0)',
        'height': round(float(pos[:, 1].max() - pos[:, 1].min()), 4),
        'bounds': {'min': rnd(pos.min(0)), 'max': rnd(pos.max(0))},
        'regions': [{'id': r, 'anchor': rnd(a), 'normal': rnd(n), 'radius': round(rad, 3)} for r, (a, n, rad) in zip(REGION_IDS, ra)],
        'muscles': [{'id': m, 'name': nme, 'anchor': rnd(a), 'normal': rnd(n)} for (m, nme), (a, n, _) in zip(MUSCLES, ma)],
    }
    with open(os.path.join(OUT, 'body3d.json'), 'w') as f:
        json.dump(meta, f, indent=1)
    print('baking textures')
    det, alb, _ = make_textures(b, L, TEX)
    Image.fromarray(det, 'L').save(os.path.join(OUT, 'body_detail.png'), optimize=True)
    Image.fromarray(alb, 'RGB').save(os.path.join(OUT, 'body_muscle.jpg'), quality=85, optimize=True, subsampling=0)
    print('rendering previews')
    render_previews(b, reg, det, alb)
    for fn in ('body.bin', 'body3d.json', 'body_detail.png', 'body_muscle.jpg'):
        print(f'  {fn}: {os.path.getsize(os.path.join(OUT, fn)) / 1e6:.2f} MB')


if __name__ == '__main__':
    main()
