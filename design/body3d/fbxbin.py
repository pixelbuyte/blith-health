"""Minimal binary FBX 7.x reader: enough to pull meshes, names, hierarchy and transforms out of
Z-Anatomy's exported FBX files (no animation, materials or UVs)."""
import collections
import struct
import zlib

import numpy as np

_ARR = {b'f': '<f4', b'd': '<f8', b'l': '<i8', b'i': '<i4', b'b': 'u1'}


class Node:
    __slots__ = ('name', 'props', 'children')

    def __init__(self, name, props, children):
        self.name, self.props, self.children = name, props, children

    def find(self, n):
        return [c for c in self.children if c.name == n]

    def first(self, n):
        r = self.find(n)
        return r[0] if r else None


def _prop(d, o):
    t = d[o:o + 1]
    o += 1
    if t == b'Y':
        return struct.unpack_from('<h', d, o)[0], o + 2
    if t == b'C':
        return d[o] != 0, o + 1
    if t == b'I':
        return struct.unpack_from('<i', d, o)[0], o + 4
    if t == b'F':
        return struct.unpack_from('<f', d, o)[0], o + 4
    if t == b'D':
        return struct.unpack_from('<d', d, o)[0], o + 8
    if t == b'L':
        return struct.unpack_from('<q', d, o)[0], o + 8
    if t in (b'S', b'R'):
        n = struct.unpack_from('<I', d, o)[0]
        v = d[o + 4:o + 4 + n]
        return (v.decode('utf-8', 'replace') if t == b'S' else v), o + 4 + n
    if t in _ARR:
        ln, enc, cl = struct.unpack_from('<III', d, o)
        raw = d[o + 12:o + 12 + cl]
        if enc == 1:
            raw = zlib.decompress(raw)
        return np.frombuffer(raw, _ARR[t], ln), o + 12 + cl
    raise ValueError(f'unknown FBX property type {t!r} at {o}')


def _node(d, o, v64):
    if v64:
        end, nprop, _ = struct.unpack_from('<QQQ', d, o)
        o += 24
    else:
        end, nprop, _ = struct.unpack_from('<III', d, o)
        o += 12
    nl = d[o]
    o += 1
    if end == 0:
        return None, o
    name = d[o:o + nl].decode()
    o += nl
    props = []
    for _ in range(nprop):
        p, o = _prop(d, o)
        props.append(p)
    children = []
    null = 25 if v64 else 13
    while o < end:
        if end - o <= null and not any(d[o:end]):
            break
        c, o = _node(d, o, v64)
        if c is None:
            break
        children.append(c)
    return Node(name, props, children), end


def read(path):
    d = open(path, 'rb').read()
    assert d[:18] == b'Kaydara FBX Binary', path
    v64 = struct.unpack_from('<I', d, 23)[0] >= 7500
    o, top = 27, []
    while o < len(d):
        n, o2 = _node(d, o, v64)
        if n is None:
            break
        top.append(n)
        o = o2
    return Node('root', [], top)


def _euler(deg):
    x, y, z = np.radians(deg)
    rx = np.array([[1, 0, 0], [0, np.cos(x), -np.sin(x)], [0, np.sin(x), np.cos(x)]])
    ry = np.array([[np.cos(y), 0, np.sin(y)], [0, 1, 0], [-np.sin(y), 0, np.cos(y)]])
    rz = np.array([[np.cos(z), -np.sin(z), 0], [np.sin(z), np.cos(z), 0], [0, 0, 1]])
    return rz @ ry @ rx          # FBX eEulerXYZ


def _m4(r=None, t=None, s=None):
    m = np.eye(4)
    if r is not None:
        m[:3, :3] = r
    if s is not None:
        m[:3, :3] = m[:3, :3] @ np.diag(s)
    if t is not None:
        m[:3, 3] = t
    return m


def _local(tf):
    g = lambda k, d: np.array(tf.get(k, d), float)
    inv = np.linalg.inv
    rp, sp = _m4(t=g('RotationPivot', (0, 0, 0))), _m4(t=g('ScalingPivot', (0, 0, 0)))
    return (_m4(t=g('Lcl Translation', (0, 0, 0))) @ _m4(t=g('RotationOffset', (0, 0, 0))) @ rp
            @ _m4(r=_euler(g('PreRotation', (0, 0, 0)))) @ _m4(r=_euler(g('Lcl Rotation', (0, 0, 0))))
            @ inv(_m4(r=_euler(g('PostRotation', (0, 0, 0))))) @ inv(rp) @ _m4(t=g('ScalingOffset', (0, 0, 0)))
            @ sp @ _m4(s=g('Lcl Scaling', (1, 1, 1))) @ inv(sp))


def _geometric(tf):
    g = lambda k, d: np.array(tf.get(k, d), float)
    return (_m4(t=g('GeometricTranslation', (0, 0, 0))) @ _m4(r=_euler(g('GeometricRotation', (0, 0, 0))))
            @ _m4(s=g('GeometricScaling', (1, 1, 1))))


def _triangulate(pi):
    ends = np.nonzero(pi < 0)[0]
    idx = np.where(pi < 0, -pi - 1, pi).astype(np.int64)
    starts = np.concatenate([[0], ends[:-1] + 1])
    n = ends - starts + 1
    tris = []
    for k in np.unique(n):
        sel = starts[n == k]
        for i in range(1, k - 1):
            tris.append(np.stack([idx[sel], idx[sel + i], idx[sel + i + 1]], 1))
    return np.concatenate(tris) if tris else np.zeros((0, 3), np.int64)


_TF_KEYS = ('Lcl Translation', 'Lcl Rotation', 'Lcl Scaling', 'PreRotation', 'PostRotation', 'RotationPivot',
            'ScalingPivot', 'RotationOffset', 'ScalingOffset', 'GeometricTranslation', 'GeometricRotation',
            'GeometricScaling')


def meshes(path):
    """World-space triangle meshes: [{name, path (list of ancestor names), V (n,3), F (m,3)}]."""
    root = read(path)
    geo, models = {}, {}
    for c in root.first('Objects').children:
        if c.name == 'Geometry':
            v, pi = c.first('Vertices'), c.first('PolygonVertexIndex')
            if v is not None and pi is not None:
                geo[c.props[0]] = (v.props[0].reshape(-1, 3).astype(np.float64), pi.props[0])
        elif c.name == 'Model':
            tf = {}
            p70 = c.first('Properties70')
            for p in (p70.children if p70 else []):
                if p.props[0] in _TF_KEYS:
                    tf[p.props[0]] = p.props[4:]
                if p.props[0] == 'RotationOrder':
                    assert p.props[4] == 0, 'only XYZ rotation order is supported'
            models[c.props[0]] = (c.props[1].split('\x00')[0], tf)
    parent, geo_of = {}, collections.defaultdict(list)
    for c in root.first('Connections').children:
        t, a, b = c.props[:3]
        if t != 'OO':
            continue
        if a in geo and b in models:
            geo_of[b].append(a)
        elif a in models:
            parent[a] = b
    world = {}

    def w(m):
        if m not in world:
            p = parent.get(m, 0)
            world[m] = (w(p) if p in models else np.eye(4)) @ _local(models[m][1])
        return world[m]

    out = []
    for mid, (name, tf) in models.items():
        for gid in geo_of.get(mid, []):
            v, pi = geo[gid]
            m = w(mid) @ _geometric(tf)
            f = _triangulate(pi)
            if np.linalg.det(m[:3, :3]) < 0:
                f = f[:, ::-1]
            names, p = [], mid
            while p in models:
                names.append(models[p][0])
                p = parent.get(p, 0)
            out.append(dict(name=name, path=names[::-1], V=v @ m[:3, :3].T + m[:3, 3], F=f))
    return out
