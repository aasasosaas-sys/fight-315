"""アニメ素体（VRoid）向けの追加衣装パーツ（anime_garment.make から呼ぶ）。A ポーズの体・骨の位置から作る。

- 履物：足袋（白）・草履・草鞋・下駄（鼻緒つき）、洋靴・編み上げブーツ・ゲートル（巻脚絆）
- 帯：女はお太鼓結び＋帯締め＋帯揚げ、男は角帯（貝の口）
- 当世具足：胴（小札の段）・草摺・袖・籠手・佩楯・脛当・兜（鉢・錣・吹返し・鍬形）・陣笠
- 近代の服：詰襟の上着（軍服・海軍の白・背広の上着）・ズボン・シャツ・もんぺ・立襟・帽子

作る空間：正面が -Y、着る人の左が +X、上が +Z（kimono.py / anime_garment.py と同じ）。
模様の UV は Godot 側の _MainTex_ST=6 に合わせ、UV 1/6 で模様 1 枚（TILE）。
"""
import math

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import delaunay_2d_cdt

import kimono as K
import anime_garment as G

TILE = 1.0 / 6.0


def ss(a, b, x):
    if a == b:
        return 1.0 if x >= b else 0.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


# ================================================================ 基本形状
def mk(name, verts, faces, vuv=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.update()
    uv = me.uv_layers.new(name="UVMap")
    if vuv:
        for li, lp in enumerate(me.loops):
            uv.data[li].uv = vuv[lp.vertex_index]
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    for p in me.polygons:
        p.use_smooth = smooth
    return o


def weld(o, dist=1e-5):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()
    return o


def grid(name, f, nu, nv, closed_u=False, uvf=None, cap0=False, cap1=False):
    """パラメータ曲面：f(s, t) -> 位置（s: 周・横 0..1、t: 縦 0..1）。uvf(s, t) -> UV。"""
    cols = nu + 1
    verts, vuv = [], []
    for j in range(nv + 1):
        t = j / nv
        for i in range(cols):
            s = i / nu
            verts.append(f(s, t))
            vuv.append(uvf(s, t) if uvf else (s, t))
    faces = []
    for j in range(nv):
        for i in range(nu):
            a = j * cols + i
            faces.append((a, a + 1, a + cols + 1, a + cols))
    for cap, j in ((cap0, 0), (cap1, nv)):
        if cap:
            ring = [j * cols + i for i in range(nu if closed_u else cols)]
            c = sum((verts[k] for k in ring), Vector()) / len(ring)
            verts.append(c)
            vuv.append(vuv[ring[0]])
            ci = len(verts) - 1
            for k in range(len(ring) - (0 if closed_u else 1)):
                a, b = ring[k], ring[(k + 1) % len(ring)]
                faces.append((a, b, ci) if j == 0 else (b, a, ci))
    o = mk(name, verts, faces, vuv)
    if closed_u:
        weld(o)
    return o


def recalc_out(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()


def face_away(o, center):
    """開いた面の向きを center から外向きにそろえる。"""
    me = o.data
    me.update()
    acc = 0.0
    for p in me.polygons:
        acc += p.normal.dot(p.center - center) * p.area
    if acc < 0:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        me.update()


def apply_mod(o, m):
    bpy.context.view_layer.objects.active = o
    with bpy.context.temp_override(object=o, active_object=o):
        bpy.ops.object.modifier_apply(modifier=m.name)


def solidify(o, t, offset=-1.0):
    m = o.modifiers.new("solid", "SOLIDIFY")
    m.thickness = t
    m.offset = offset
    m.use_even_offset = True
    m.use_rim = True
    apply_mod(o, m)
    return o


def push_out(o, target, margin):
    """target の内側に入った頂点だけを外へ押し出す（外にある頂点はそのまま）。"""
    sw = o.modifiers.new("push", "SHRINKWRAP")
    sw.target = target
    sw.wrap_method = "NEAREST_SURFACEPOINT"
    sw.wrap_mode = "OUTSIDE"
    sw.offset = margin
    apply_mod(o, sw)


def tube(name, pts, r, n=8, cap=True):
    """折れ線に沿った管（紐・縁）。r は数値か、点ごとの半径のリスト。"""
    rs = r if isinstance(r, (list, tuple)) else [r] * len(pts)
    tans = []
    for i in range(len(pts)):
        a = pts[max(0, i - 1)]
        b = pts[min(len(pts) - 1, i + 1)]
        tans.append((b - a).normalized())
    ref = Vector((0, 0, 1)) if abs(tans[0].z) < 0.9 else Vector((1, 0, 0))
    nrm = (ref - tans[0] * ref.dot(tans[0])).normalized()
    frames = []
    for i, t in enumerate(tans):
        nrm = (nrm - t * nrm.dot(t)).normalized()
        frames.append((nrm, t.cross(nrm)))
    verts, vuv, faces = [], [], []
    for i, p in enumerate(pts):
        a_, b_ = frames[i]
        for k in range(n):
            ang = 2 * math.pi * k / n
            verts.append(p + (a_ * math.cos(ang) + b_ * math.sin(ang)) * rs[i])
            vuv.append((k / n * TILE, i / len(pts) * TILE))
    for i in range(len(pts) - 1):
        for k in range(n):
            a = i * n + k
            b = i * n + (k + 1) % n
            faces.append((a, b, b + n, a + n))
    if cap:
        for i, rev in ((0, True), (len(pts) - 1, False)):
            verts.append(pts[i])
            vuv.append((0, 0))
            c = len(verts) - 1
            for k in range(n):
                a = i * n + k
                b = i * n + (k + 1) % n
                faces.append((b, a, c) if rev else (a, b, c))
    o = mk(name, verts, faces, vuv)
    recalc_out(o)
    return o


def slab(name, outline, z0, z1, uv_scale=None):
    """平面の輪郭（x, y の列）を z0..z1 に押し出した板（草履の台・下駄の台）。"""
    n = len(outline)
    verts, vuv = [], []
    for z in (z0, z1):
        for (x, y) in outline:
            verts.append(Vector((x, y, z)))
            vuv.append(((x * (uv_scale or 1)), (y * (uv_scale or 1))))
    faces = [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    cx = sum(x for x, _ in outline) / n
    cy = sum(y for _, y in outline) / n
    for z, off in ((z0, 0), (z1, n)):
        verts.append(Vector((cx, cy, z)))
        vuv.append((cx * (uv_scale or 1), cy * (uv_scale or 1)))
        c = len(verts) - 1
        for i in range(n):
            faces.append((off + i, off + (i + 1) % n, c))
    o = mk(name, verts, faces, vuv)
    recalc_out(o)
    for p in o.data.polygons:
        p.use_smooth = False
    return o


def remesh_solid(objs, name, voxel=0.003, smooth=4, ratio=0.4):
    """閉じた形の和をボクセルで一体化（足袋のつま先と足首など）。"""
    o = K.join(objs, name)
    rm = o.modifiers.new("rm", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    apply_mod(o, rm)
    if smooth:
        sm = o.modifiers.new("sm", "SMOOTH")
        sm.factor = 0.5
        sm.iterations = smooth
        apply_mod(o, sm)
    if ratio < 1.0:
        d = o.modifiers.new("dec", "DECIMATE")
        d.ratio = ratio
        apply_mod(o, d)
    for p in o.data.polygons:
        p.use_smooth = True
    if not o.data.uv_layers:
        o.data.uv_layers.new(name="UVMap")
    return o


def delete_verts(o, pred):
    mw = o.matrix_world
    bm = bmesh.new()
    bm.from_mesh(o.data)
    kill = [v for v in bm.verts if pred(mw @ v.co)]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()


def bvh_of(o):
    return BVHTree.FromObject(o, bpy.context.evaluated_depsgraph_get())


def _pip(pt, poly):
    x, y = pt
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = x1 + (y - y1) * (x2 - x1) / (y2 - y1)
            if xi > x:
                inside = not inside
    return inside


def patch(name, target, poly, lift, res=0.008, front=True, bvh=None):
    """正面（front=False で背面）から見た多角形（x, z の列）を、target の表面へ投影した薄い布（衿・ネクタイ・ポケット）。"""
    bvh = bvh or bvh_of(target)
    pts = []
    for i in range(len(poly)):
        a = Vector(poly[i])
        b = Vector(poly[(i + 1) % len(poly)])
        k = max(1, int((b - a).length / res))
        for j in range(k):
            pts.append(a + (b - a) * (j / k))
    nb = len(pts)
    xs = [p.x for p in pts]
    zs = [p.y for p in pts]
    x = min(xs) + res * 0.5
    while x < max(xs):
        z = min(zs) + res * 0.5
        while z < max(zs):
            if _pip((x, z), poly) and min((Vector((x, z)) - q).length for q in pts) > res * 0.45:
                pts.append(Vector((x, z)))
            z += res
        x += res
    edges = [(i, (i + 1) % nb) for i in range(nb)]
    out = delaunay_2d_cdt(pts, edges, [list(range(nb))], 1, 1e-6)
    co, _, faces = out[0], out[1], out[2]
    mwi = target.matrix_world.inverted()
    mw = target.matrix_world
    d = Vector((0, 1 if front else -1, 0))
    verts = []
    ok = []
    for c in co:
        o_ = Vector((c.x, -2.0 if front else 2.0, c.y))
        loc, nrm, _, _ = bvh.ray_cast(mwi @ o_, (mwi.to_3x3() @ d).normalized())
        if loc is None:
            verts.append(Vector((c.x, 0, c.y)))
            ok.append(False)
            continue
        loc = mw @ loc
        nrm = (mw.to_3x3() @ nrm).normalized()
        verts.append(loc + nrm * lift)
        ok.append(True)
    faces = [f for f in faces if all(ok[i] for i in f)]
    vuv = [(c.x * TILE / 0.05, c.y * TILE / 0.05) for c in co]
    o = mk(name, verts, faces, vuv)
    # 正面のものは -Y、背面のものは +Y を向く
    me = o.data
    me.update()
    s = sum(p.normal.y for p in me.polygons)
    if (front and s > 0) or (not front and s < 0):
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
    delete_verts(o, lambda q: False)
    return o


def surf_point(bvh, p, d):
    """p から方向 d へ光線を飛ばし、当たった点と法線。"""
    loc, nrm, _, _ = bvh.ray_cast(p, d)
    return loc, nrm


def stud(name, p, nrm, r, h, n=10):
    """ボタン・鋲：表面の点 p に法線 nrm 向きの低い円柱。"""
    nrm = nrm.normalized()
    ref = Vector((0, 0, 1)) if abs(nrm.z) < 0.9 else Vector((1, 0, 0))
    a = (ref - nrm * ref.dot(nrm)).normalized()
    b = nrm.cross(a)
    verts = []
    for z in (0.0, h):
        for k in range(n):
            ang = 2 * math.pi * k / n
            verts.append(p + nrm * z + (a * math.cos(ang) + b * math.sin(ang)) * r * (1.0 if z == 0 else 0.8))
    verts.append(p + nrm * (h * 1.15))
    c = len(verts) - 1
    faces = [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)]
    faces += [(n + k, n + (k + 1) % n, c) for k in range(n)]
    o = mk(name, verts, faces)
    recalc_out(o)
    return o


# ================================================================ ウェイト
def _vg(o, groups, key):
    name = K.bn(key)
    if name not in groups:
        groups[name] = o.vertex_groups.get(name) or o.vertex_groups.new(name=name)
    return groups[name]


def _clear(o):
    for vg in list(o.vertex_groups):
        o.vertex_groups.remove(vg)
    for m in list(o.modifiers):
        if m.type == "ARMATURE":
            o.modifiers.remove(m)


def _finish(o, L):
    am = o.modifiers.new("Armature", "ARMATURE")
    am.object = L["arm"]


def w_single(o, L, key):
    _clear(o)
    g = o.vertex_groups.new(name=K.bn(key))
    g.add([v.index for v in o.data.vertices], 1.0, "REPLACE")
    _finish(o, L)


def _torso_w(L, z):
    chain = [("pelvis", L["pelvis"].z), ("spine_01", L["spine_01"].z),
             ("spine_02", (L["spine_01"].z + L["spine_03"].z) / 2), ("spine_03", L["spine_03"].z)]
    if z <= chain[0][1]:
        return {chain[0][0]: 1.0}
    if z >= chain[-1][1]:
        return {chain[-1][0]: 1.0}
    for (n0, z0), (n1, z1) in zip(chain, chain[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / max(z1 - z0, 1e-4)
            return {n0: 1 - t, n1: t}
    return {"pelvis": 1.0}


def leg_w(L, q, crotch=0.12, center_soft=0.03):
    """脚の骨のウェイト（太腿→すね→足）。腰の上は胴の骨。"""
    hip_z = L["pelvis"].z
    s = "l" if q.x > L["pelvis"].x else "r"
    knee = L["calf_" + s].z
    ank = L["foot_" + s].z
    w = {}
    leg = ss(hip_z + 0.02, hip_z - crotch, q.z)
    if center_soft > 0:
        leg *= ss(0.0, center_soft, abs(q.x - L["pelvis"].x)) * 0.5 + 0.5 * ss(hip_z - 0.02, hip_z - crotch - 0.05, q.z)
    if leg < 1.0:
        for k, x in _torso_w(L, q.z).items():
            w[k] = x * (1 - leg)
    if leg > 0:
        lo = ss(knee + 0.07, knee - 0.07, q.z)
        ft = ss(ank + 0.03, ank - 0.03, q.z)
        w["thigh_" + s] = leg * (1 - lo)
        w["calf_" + s] = leg * lo * (1 - ft)
        w["foot_" + s] = leg * lo * ft
    return w


def w_legs(o, L, crotch=0.12, center_soft=0.03):
    _clear(o)
    groups = {}
    mw = o.matrix_world
    for v in o.data.vertices:
        for k, x in leg_w(L, mw @ v.co, crotch, center_soft).items():
            if x > 1e-4:
                _vg(o, groups, k).add([v.index], x, "REPLACE")
    _finish(o, L)


def w_arm(o, L, side, hand=False):
    """腕に沿うもの（籠手・袖）：上腕→前腕（→手）。"""
    _clear(o)
    groups = {}
    sh, el, wr = L["upperarm_" + side], L["lowerarm_" + side], L["hand_" + side]
    ax = wr - sh
    te = (el - sh).dot(ax) / ax.length_squared
    mw = o.matrix_world
    for v in o.data.vertices:
        q = mw @ v.co
        t = (q - sh).dot(ax) / ax.length_squared
        lo = ss(te - 0.1, te + 0.1, t)
        hd = ss(0.97, 1.03, t) if hand else 0.0
        w = {"upperarm_" + side: (1 - lo), "lowerarm_" + side: lo * (1 - hd)}
        if hd > 0:
            w["hand_" + side] = lo * hd
        for k, x in w.items():
            if x > 1e-4:
                _vg(o, groups, k).add([v.index], x, "REPLACE")
    _finish(o, L)


def w_torso(o, L):
    G.bone_weights(o, L, arms=False)


# ================================================================ 寸法
def foot_info(body, L, s):
    f = L["foot_" + s]
    mw = body.matrix_world
    sx = 1.0 if s == "l" else -1.0
    pts = []
    for v in body.data.vertices:
        p = mw @ v.co
        if p.z < L["floor"] + 0.09 and abs(p.x - f.x) < 0.08 and (p.x - L["pelvis"].x) * sx > 0.005:
            pts.append(p)
    if len(pts) < 10:
        return {"toe": f.y - 0.16, "heel": f.y + 0.05, "cx": f.x, "w": 0.085, "ankle": f, "m": -sx}
    toe = min(p.y for p in pts)
    heel = max(p.y for p in pts)
    x0 = min(p.x for p in pts)
    x1 = max(p.x for p in pts)
    w = max(0.074, min(0.095, x1 - x0))
    return {"toe": toe, "heel": heel, "cx": (x0 + x1) / 2, "w": w, "ankle": f, "m": -sx}


def head_frame(L):
    """頭の骨を基準にした頭の寸法（髪型 glb の範囲：横 ±0.11、前 -0.1〜後ろ +0.12、頂 +0.23）。"""
    h = L["head"]
    k = abs(L["upperarm_l"].x - L["upperarm_r"].x) / 0.295
    k = max(0.85, min(1.1, k)) * 0.0 + 1.0
    return h, k


# ================================================================ 履物
def _superellipse(a, e=3.0):
    c, s = math.cos(a), math.sin(a)
    return (math.copysign(abs(c) ** (2 / e), c), math.copysign(abs(s) ** (2 / e), s))


def _lobe(name, fi, t0, t1, xoff, wk, h0, h1, z0, round_from, ny=18, na=20):
    """足の形の一部（踵〜つま先の筒）。t: 0=踵 1=つま先。"""
    Lf = fi["heel"] - fi["toe"]
    W = fi["w"]

    def f(s, t):
        tt = lerp(t0, t1, t)
        y = fi["heel"] + 0.004 - tt * (Lf + 0.008)
        w = W * wk(tt) / 2
        h = lerp(h0, h1, ss(0.3, 0.85, tt))
        if tt > round_from:
            r = math.sqrt(max(0.0, 1 - ((tt - round_from) / (t1 - round_from)) ** 2))
            w *= max(0.05, r ** 0.8)
            h *= max(0.3, r ** 0.5)
        if tt < 0.06:
            r = math.sqrt(max(0.0, 1 - ((0.06 - tt) / 0.06) ** 2))
            w *= max(0.1, r)
        ex, ez = _superellipse(2 * math.pi * s, 3.0)
        z = z0 + h / 2 + ez * h / 2
        return Vector((fi["cx"] + fi["m"] * xoff * W + ex * w, y, max(z0, z)))
    return grid(name, f, na, ny, closed_u=True, cap0=True, cap1=True)


def foot_last(name, fi, z0, top_z, split=False, wide=1.0, height=0.068, shaft=None):
    """足袋・靴の形：足の甲＋つま先（足袋は親指が分かれる）＋足首の筒。shaft で長靴の筒。"""
    parts = []
    if split:
        parts.append(_lobe(name + "_m", fi, 0.0, 0.84, 0.0, lambda t: wide * (0.72 + 0.28 * ss(0.0, 0.6, t)), height, height * 0.5, z0, 2.0))
        parts.append(_lobe(name + "_bt", fi, 0.6, 1.0, 0.30, lambda t: wide * 0.32, height * 0.52, height * 0.5, z0, 0.86))
        parts.append(_lobe(name + "_ft", fi, 0.6, 0.965, -0.14, lambda t: wide * 0.52, height * 0.48, height * 0.42, z0, 0.8))
    else:
        parts.append(_lobe(name + "_m", fi, 0.0, 1.0, 0.04, lambda t: wide * (0.74 + 0.26 * ss(0.0, 0.6, t)) * (1 - 0.1 * ss(0.8, 1.0, t)), height, height * 0.55, z0, 0.78))
    a = fi["ankle"]
    prof = shaft or [(z0 + 0.02, 0.042, 0.048), (top_z, 0.04, 0.045)]
    rings = []
    for (z, rx, ry) in prof:
        rings.append((z, rx, ry))

    def fs(s, t):
        k = t * (len(rings) - 1)
        i = min(int(k), len(rings) - 2)
        u = k - i
        z = lerp(rings[i][0], rings[i + 1][0], u)
        rx = lerp(rings[i][1], rings[i + 1][1], u)
        ry = lerp(rings[i][2], rings[i + 1][2], u)
        c = _leg_axis(fi, z)
        ang = 2 * math.pi * s
        return Vector((c.x + math.cos(ang) * rx, c.y + math.sin(ang) * ry + 0.004, z))
    parts.append(grid(name + "_c", fs, 20, max(4, 3 * (len(rings) - 1)), closed_u=True, cap0=True, cap1=True))
    o = remesh_solid(parts, name, voxel=0.0028 if split else 0.0035, smooth=3, ratio=0.45)
    top = prof[-1][0]
    delete_verts(o, lambda q: q.z > top - 0.004)
    for v in o.data.vertices:
        if v.co.z < z0 + 0.0015:
            v.co.z = z0
    return o


_LEG = {}


def _leg_axis(fi, z):
    """足首→膝の線上で高さ z の点（長靴・脚絆の筒の中心）。"""
    a = fi["ankle"]
    k = _LEG.get(round(a.x, 4))
    if k is None or z <= a.z:
        return Vector((a.x, a.y, z))
    t = (z - a.z) / max(k.z - a.z, 0.01)
    return Vector((lerp(a.x, k.x, t), lerp(a.y, k.y, t), z))


def sole_outline(fi, margin, n=36, e=2.6, front_w=1.0, heel_w=0.86, toe_off=0.004, heel_off=0.004):
    Lf = fi["heel"] - fi["toe"] + toe_off + heel_off
    cy = (fi["heel"] + heel_off + fi["toe"] - toe_off) / 2
    W = fi["w"] / 2 + margin
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        ex, ey = _superellipse(a, e)
        y = cy + ey * Lf / 2
        front = (cy - y) / (Lf / 2)   # 1 = つま先
        wk = lerp(heel_w, front_w, ss(-0.7, 0.4, front))
        x = fi["cx"] + fi["m"] * 0.06 * fi["w"] * max(0.0, front) + ex * W * wk
        out.append((x, y))
    return out


def hanao(name, fi, z0, tabi_bvh, r=0.0055, back=0.56):
    """鼻緒：親指と人差し指の間の前坪から、甲を越えて左右の横緒へ。"""
    Lf = fi["heel"] - fi["toe"]
    W = fi["w"]
    p0 = Vector((fi["cx"] + fi["m"] * W * 0.15, fi["toe"] + 0.04, z0 - 0.002))
    p1 = Vector((p0.x, p0.y - 0.004, z0 + 0.03))
    objs = [tube(name + "_m", [p0, p0 + Vector((0, 0, 0.012)), p1], r * 0.8, 8)]
    for side in (1, -1):
        sp = Vector((fi["cx"] + side * (W / 2 + 0.006), fi["toe"] + back * Lf, z0 + 0.002))
        pts = []
        for i in range(13):
            u = i / 12
            p = p1.lerp(sp, u) + Vector((0, 0, 0.035 * math.sin(math.pi * u) * (1 - u) + 0.01 * (1 - u)))
            loc, nrm, _, d = tabi_bvh.find_nearest(p)
            if loc is not None:
                inside = (p - loc).dot(nrm) < 0
                if inside or d < r + 0.0015:
                    p = loc + nrm * (r + 0.0015)
            pts.append(p)
        pts[-1] = sp
        objs.append(tube(name + "_%d" % side, pts, r, 8))
    return objs


def footwear(body, L):
    out = {}
    floor = L["floor"]
    for s in ("l", "r"):
        _LEG[round(L["foot_" + s].x, 4)] = L["calf_" + s]
    for s in ("l", "r"):
        fi = foot_info(body, L, s)
        # 足袋（草履・草鞋用：台の厚み分上げる）と、下駄用（歯の高さ分上げる）
        tabi = foot_last("tabi_" + s, fi, floor + 0.012, floor + 0.15, split=True)
        tabi_g = foot_last("tabig_" + s, fi, floor + 0.048, floor + 0.17, split=True,
                           shaft=[(floor + 0.068, 0.042, 0.048), (floor + 0.17, 0.04, 0.045)])
        out.setdefault("tabi", []).append(tabi)
        out.setdefault("tabi_g", []).append(tabi_g)
        tb = bvh_of(tabi)
        tbg = bvh_of(tabi_g)
        # 草履：楕円の台（踵を少し厚く）
        zr = slab("zori_" + s, sole_outline(fi, 0.006, front_w=1.0, heel_w=0.92, toe_off=0.01, heel_off=0.01), floor, floor + 0.012)
        for v in zr.data.vertices:
            if v.co.z < floor + 0.001:
                pass
            elif v.co.y > (fi["heel"] + fi["toe"]) / 2:
                v.co.z += 0.004 * ss((fi["heel"] + fi["toe"]) / 2, fi["heel"], v.co.y)
        out.setdefault("zori", []).append(zr)
        out.setdefault("zori_hanao", []).extend(hanao("zhanao_" + s, fi, floor + 0.012, tb))
        # 下駄：角の丸い板＋二枚歯
        gt = slab("geta_" + s, sole_outline(fi, 0.009, e=4.5, front_w=1.0, heel_w=1.0, toe_off=0.006, heel_off=0.008), floor + 0.032, floor + 0.048, uv_scale=TILE / 0.05)
        Lf = fi["heel"] - fi["toe"]
        teeth = []
        for ty in (fi["toe"] + 0.22 * Lf, fi["toe"] + 0.8 * Lf):
            hw = fi["w"] / 2 + 0.006
            teeth.append(slab("geta_ha", [(fi["cx"] - hw, ty - 0.009), (fi["cx"] + hw, ty - 0.009), (fi["cx"] + hw, ty + 0.009), (fi["cx"] - hw, ty + 0.009)], floor, floor + 0.034, uv_scale=TILE / 0.05))
        out.setdefault("geta", []).extend([gt] + teeth)
        out.setdefault("geta_hanao", []).extend(hanao("ghanao_" + s, fi, floor + 0.048, tbg))
        # 草鞋：藁の台（つま先は足より短い）＋足首を結ぶ緒
        wr = slab("waraji_" + s, sole_outline(fi, 0.002, e=2.4, front_w=0.95, heel_w=0.85, toe_off=-0.012, heel_off=0.006), floor, floor + 0.011, uv_scale=TILE / 0.03)
        cords = []
        a = fi["ankle"]
        ring = []
        for i in range(25):
            ang = 2 * math.pi * i / 24
            ring.append(Vector((a.x + math.cos(ang) * 0.047, a.y + 0.004 + math.sin(ang) * 0.053, floor + 0.085 - 0.012 * math.sin(ang))))
        cords.append(tube("wcord_ring", ring, 0.0035, 6, cap=False))
        for (yt, side) in ((0.38, 1), (0.38, -1), (0.72, 1), (0.72, -1)):
            sp = Vector((fi["cx"] + side * (fi["w"] / 2 + 0.002), fi["toe"] + yt * Lf, floor + 0.011))
            ang = math.atan2(sp.y - a.y, (sp.x - a.x))
            ep = Vector((a.x + math.cos(ang) * 0.047, a.y + 0.004 + math.sin(ang) * 0.053, floor + 0.085 - 0.012 * math.sin(ang)))
            pts = []
            for i in range(9):
                u = i / 8
                p = sp.lerp(ep, u)
                loc, nrm, _, d = tb.find_nearest(p)
                if loc is not None and ((p - loc).dot(nrm) < 0 or d < 0.005):
                    p = loc + nrm * 0.005
                pts.append(p)
            cords.append(tube("wcord", pts, 0.003, 6))
        tp = Vector((fi["cx"] + fi["m"] * fi["w"] * 0.15, fi["toe"] + 0.03, floor + 0.011))
        ep = Vector((a.x, a.y + 0.004 - 0.053, floor + 0.097))
        pts = []
        for i in range(11):
            u = i / 10
            p = tp.lerp(ep, u) + Vector((0, 0, 0.02 * math.sin(math.pi * u)))
            loc, nrm, _, d = tb.find_nearest(p)
            if loc is not None and ((p - loc).dot(nrm) < 0 or d < 0.005):
                p = loc + nrm * 0.005
            pts.append(p)
        cords.append(tube("wcord_f", pts, 0.0032, 6))
        out.setdefault("waraji", []).extend([wr] + cords)
        # 洋靴（短靴）・軍靴（くるぶし丈）・編み上げの長靴（膝下まで）
        out.setdefault("shoes", []).append(foot_last("shoe_" + s, fi, floor, floor + 0.11, wide=1.08, height=0.072,
                                                     shaft=[(floor + 0.03, 0.044, 0.052), (floor + 0.11, 0.043, 0.048)]))
        out.setdefault("boots", []).append(foot_last("boot_" + s, fi, floor, floor + 0.16, wide=1.1, height=0.074,
                                                     shaft=[(floor + 0.03, 0.046, 0.054), (floor + 0.16, 0.046, 0.05)]))
        knee = L["calf_" + s]
        tall = knee.z - 0.05
        out.setdefault("boots_h", []).append(foot_last("booth_" + s, fi, floor, tall, wide=1.04, height=0.07,
                                                       shaft=[(floor + 0.03, 0.044, 0.05), (floor + 0.12, 0.04, 0.045),
                                                              (lerp(floor, tall, 0.55), 0.05, 0.054), (tall, 0.054, 0.058)]))
        # ゲートル（巻脚絆）：足首の上から膝下まで、斜めに巻いた帯
        z0, z1 = floor + 0.1, knee.z - 0.05

        def fp(su, t, fi=fi, z0=z0, z1=z1):
            z = lerp(z0, z1, t)
            c = _leg_axis(fi, z)
            r = lerp(0.046, 0.062, ss(0.0, 0.75, t)) * (1 - 0.06 * ss(0.85, 1.0, t))
            ang = 2 * math.pi * su
            return Vector((c.x + math.cos(ang) * r, c.y + 0.004 + math.sin(ang) * r * 1.08, z))
        pt = grid("puttee_" + s, fp, 24, 14, closed_u=True, uvf=lambda su, t, z0=z0, z1=z1: (su * 2 * TILE, (z1 - z0) * t / 0.03 * TILE))
        out.setdefault("puttee", []).append(pt)
    for k, objs in out.items():
        for o in objs:
            w_legs(o, L)
    return out


# ================================================================ 帯
def _band(name, c, rx, ry, z0, z1, n=48, slant=0.0):
    def f(s, t):
        a = 2 * math.pi * s
        z = lerp(z0, z1, t) + slant * (-math.sin(a))   # 前（-Y）で下がる
        return Vector((c.x + math.cos(a) * rx, c.y + math.sin(a) * ry, z))
    circ = math.pi * (rx + ry)
    return grid(name, f, n, 3, closed_u=True, uvf=lambda s, t: (s * circ * 2, t * (z1 - z0) * 2))


def obi(kosode, L, female):
    """女：幅広の帯＋背中のお太鼓（帯枕で丸く膨らみ、下にたれ）＋帯締め＋帯揚げ。男：腰の角帯＋背中の貝の口。"""
    D = G.dims(L)
    tsec = G.tsection_dims(L)
    out = {}
    if female:
        zc = L["spine_01"].z + 0.06
        wdt = 0.17
    else:
        zc = L["pelvis"].z + 0.065
        wdt = 0.07
    z0, z1 = zc - wdt / 2, zc + wdt / 2
    c, rx, ry = tsec(None, zc)
    band = _band("obi_band", c, rx + 0.03, ry + 0.035, z0, z1, slant=0.0 if female else 0.012)
    push_out(band, kosode, 0.01)
    out["obi"] = [band]
    if female:
        # お太鼓：帯の上端の少し上から丸く後ろへ膨らみ、帯の下端より下まで垂れる
        back = c.y + ry + 0.035
        w = 0.15
        top = z1 + 0.035
        bot = z0 - 0.045
        prof = []   # (y の張り出し, z)
        for i in range(21):
            u = i / 20
            if u < 0.35:
                a = u / 0.35 * math.pi * 0.5
                prof.append((0.035 + 0.04 * math.sin(a), top - 0.03 * (1 - math.cos(a)) + 0.0))
            else:
                v = (u - 0.35) / 0.65
                prof.append((0.075 - 0.012 * v, lerp(top - 0.03, bot, v)))

        def ft(s, t):
            x = lerp(-w, w, s)
            i = t * (len(prof) - 1)
            k = min(int(i), len(prof) - 2)
            fr = i - k
            dy = lerp(prof[k][0], prof[k + 1][0], fr)
            z = lerp(prof[k][1], prof[k + 1][1], fr)
            curve = (x / w) ** 2 * 0.02
            return Vector((c.x + x, back + dy - curve - 0.03, z))
        taiko = grid("taiko", ft, 16, 20, uvf=lambda s, t: (s * 0.3 * 2, t * 0.3 * 2))
        face_away(taiko, Vector((c.x, c.y, zc)))
        solidify(taiko, 0.012)
        # 帯枕の上を覆う山（お太鼓の上端を閉じる）
        top_cap = grid("taiko_top", lambda s, t: Vector((c.x + lerp(-w, w, s), lerp(back - 0.005, back + 0.038, t), top - 0.03 + 0.03 * math.sin(math.pi * 0.5 * t) - (lerp(-w, w, s) / w) ** 2 * 0.01)), 16, 4)
        face_away(top_cap, Vector((c.x, c.y, zc - 0.1)))
        solidify(top_cap, 0.01)
        # たれ（お太鼓の下から少し出る）と、両脇に出る「て」
        tare = grid("tare", lambda s, t: Vector((c.x + lerp(-w + 0.004, w - 0.004, s), back + 0.065 - 0.003 * t, lerp(bot + 0.004, bot - 0.035, t))), 12, 3)
        face_away(tare, Vector((c.x, c.y, zc)))
        solidify(tare, 0.01)
        te = []
        for sd in (1, -1):
            te.append(grid("te", lambda s, t, sd=sd: Vector((c.x + sd * lerp(w - 0.01, w + 0.035, s), back + 0.05 - 0.01 * s, lerp(z0 + 0.012, z0 + 0.05, t))), 4, 3))
            face_away(te[-1], Vector((c.x, c.y - 0.2, zc)))
            solidify(te[-1], 0.012)
        out["taiko"] = [taiko, top_cap, tare] + te
        # 帯締め：帯の中央を一周し、正面で結ぶ。お太鼓の中も通る
        zj = zc - 0.005
        ring = []
        for i in range(49):
            a = 2 * math.pi * i / 48
            r_x = rx + 0.03 + 0.012
            r_y = ry + 0.035 + 0.012
            p = Vector((c.x + math.cos(a) * r_x, c.y + math.sin(a) * r_y, zj))
            if math.sin(a) > 0.2 and abs(math.cos(a) * r_x) < w + 0.01:
                p.y = max(p.y, back + 0.075 + 0.004)
            ring.append(p)
        jime = [tube("obijime", ring, 0.0045, 8, cap=False)]
        fy = c.y - ry - 0.035 - 0.014
        jime.append(tube("obijime_knot", [Vector((c.x - 0.016, fy, zj + 0.004)), Vector((c.x, fy - 0.006, zj)), Vector((c.x + 0.016, fy, zj - 0.004))], 0.008, 8))
        for sd in (1, -1):
            jime.append(tube("obijime_end", [Vector((c.x + sd * 0.008, fy - 0.004, zj - 0.004)), Vector((c.x + sd * 0.03, fy + 0.002, zj - 0.03)),
                                             Vector((c.x + sd * 0.05, fy + 0.012, zj - 0.035))], 0.0042, 8))
        out["obijime"] = jime
        # 帯揚げ：帯の上端の前に少し見える布
        ag = _band("obiage", c, rx + 0.03, ry + 0.035, z1 - 0.004, z1 + 0.014, n=40)
        push_out(ag, kosode, 0.006)
        delete_verts(ag, lambda q: q.y > c.y - ry * 0.2)
        out["obiage"] = [ag]
    else:
        # 貝の口：背中で、帯の両端が斜め上・斜め下へ短く出る結び目
        by = c.y + ry + 0.035 + 0.008
        kz = zc + 0.012
        knot = grid("kai_knot", lambda s, t: Vector((c.x + lerp(-0.035, 0.035, s), by + 0.006 * math.sin(math.pi * s), lerp(kz - 0.03, kz + 0.03, t))), 6, 4)
        face_away(knot, Vector((c.x, c.y, kz)))
        solidify(knot, 0.012)
        tabs = [knot]
        for sd, dz in ((1, 1), (-1, -1)):
            tabs.append(grid("kai_end", lambda s, t, sd=sd, dz=dz: Vector((c.x + sd * lerp(0.02, 0.085, s), by + 0.004 + 0.008 * s, kz + dz * lerp(0.0, 0.035, s) + lerp(-0.016, 0.016, t))), 6, 2))
            face_away(tabs[-1], Vector((c.x, c.y, kz)))
            solidify(tabs[-1], 0.008)
        out["obi"] += tabs
    for k, objs in out.items():
        for o in objs:
            G.bone_weights(o, L, arms=False)
    return out
