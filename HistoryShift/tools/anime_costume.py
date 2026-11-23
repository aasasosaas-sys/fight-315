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


def inflate(o, d):
    """法線方向へ一様に膨らませる（スキンの殻はオフセットが大きいと腕と胴がぶつかって壊れるため）。"""
    m = o.modifiers.new("disp", "DISPLACE")
    m.mid_level = 0.0
    m.strength = d
    apply_mod(o, m)


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


def leg_w(L, q, crotch=0.12, center_soft=0.03, side=None):
    """脚の骨のウェイト（太腿→すね→足）。腰の上は胴の骨。side：片脚だけのもの（履物・脛当）はその脚に固定。"""
    hip_z = L["pelvis"].z
    s = side or ("l" if q.x > L["pelvis"].x else "r")
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
    side = o.get("side")
    _clear(o)
    groups = {}
    mw = o.matrix_world
    for v in o.data.vertices:
        for k, x in leg_w(L, mw @ v.co, crotch, center_soft, side).items():
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


def w_coat(o, L, sleeve_r):
    """洋服の殻：袖の筒の面に近い頂点は腕、胴の面に近い頂点は胴（腕を下ろすと袖が胴に近いので距離では分けられない）。"""
    _clear(o)
    groups = {}
    tsec = G.tsection_dims(L)
    mw = o.matrix_world
    for v in o.data.vertices:
        q = mw @ v.co
        w = _torso_w(L, q.z)
        c, rx, ry = tsec(None, min(q.z, L["spine_03"].z))
        rr = math.sqrt(((q.x - c.x) / rx) ** 2 + ((q.y - c.y) / ry) ** 2)
        e_tor = abs(rr - 1.0) * min(rx, ry)
        best = None
        for sd in ("l", "r"):
            sh, el, wr = L["upperarm_" + sd], L["lowerarm_" + sd], L["hand_" + sd]
            ax = wr - sh
            t = (q - sh).dot(ax) / ax.length_squared
            tc = max(0.0, min(1.0, t))
            d = (q - (sh + ax * tc)).length
            r = lerp(sleeve_r[0], sleeve_r[2], tc)
            e = abs(d - r)
            if best is None or e < best[0]:
                best = (e, sd, t, (el - sh).dot(ax) / ax.length_squared)
        e_arm, sd, t, te = best
        a = ss(-0.012, 0.012, e_tor - e_arm) * ss(-0.04, 0.14, t)
        if q.z > L["spine_03"].z + 0.02 and abs(q.x - L["neck_01"].x) < 0.09:
            a = 0.0
        if a > 0:
            lo = ss(te - 0.1, te + 0.1, t)
            for k in list(w):
                w[k] *= (1 - a)
            w["upperarm_" + sd] = a * (1 - lo)
            w["lowerarm_" + sd] = a * lo
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
    o = remesh_solid(parts, name, voxel=0.0028 if split else 0.0035, smooth=3, ratio=0.12 if split else 0.1)
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
    loc, _, _, _ = tabi_bvh.ray_cast(Vector((p0.x, p0.y + 0.012, z0 + 0.3)), Vector((0, 0, -1)))
    p1 = Vector((p0.x, p0.y + 0.012, (loc.z if loc is not None else z0 + 0.025) + r * 0.9))
    objs = [tube(name + "_m", [p0, p0 + Vector((0, 0, 0.012)), p1], r * 0.8, 8)]
    for side in (1, -1):
        sp = Vector((fi["cx"] + side * (W / 2 + 0.006), fi["toe"] + back * Lf, z0 + 0.002))
        pts = []
        for i in range(15):
            u = i / 14
            p = p1.lerp(sp, u)
            loc, nrm, _, _ = tabi_bvh.ray_cast(Vector((p.x, p.y, z0 + 0.3)), Vector((0, 0, -1)))
            if loc is not None and loc.z > z0 + 0.006:
                p = Vector((p.x, p.y, loc.z + r * 0.9))
            else:
                p = Vector((p.x, p.y, max(p.z, z0 + r)))
            loc, nrm, _, d = tabi_bvh.find_nearest(p)
            if loc is not None:
                inside = (p - loc).dot(nrm) < 0
                if inside or d < r + 0.001:
                    p = loc + nrm * (r + 0.001)
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
        out.setdefault("shoes", []).append(foot_last("shoe_" + s, fi, floor + 0.01, floor + 0.11, wide=1.0, height=0.064,
                                                     shaft=[(floor + 0.03, 0.043, 0.05), (floor + 0.11, 0.042, 0.047)]))
        out.setdefault("boots", []).append(foot_last("boot_" + s, fi, floor + 0.01, floor + 0.16, wide=1.04, height=0.068,
                                                     shaft=[(floor + 0.03, 0.045, 0.052), (floor + 0.16, 0.045, 0.049)]))
        knee = L["calf_" + s]
        tall = knee.z - 0.05
        out.setdefault("boots_h", []).append(foot_last("booth_" + s, fi, floor + 0.01, tall, wide=0.98, height=0.064,
                                                       shaft=[(floor + 0.03, 0.043, 0.049), (floor + 0.12, 0.039, 0.044),
                                                              (lerp(floor, tall, 0.55), 0.048, 0.052), (tall, 0.052, 0.056)]))
        # 靴底と踵（少し張り出した縁）
        for key, wk in (("shoes", 1.0), ("boots", 1.04), ("boots_h", 0.98)):
            fi2 = dict(fi)
            fi2["w"] = fi["w"] * wk
            so = slab("sole_" + s, sole_outline(fi2, 0.004, e=2.6, front_w=1.0, heel_w=0.9, toe_off=0.008, heel_off=0.006), floor, floor + 0.012)
            Lf = fi["heel"] - fi["toe"]
            hy = fi["heel"] - 0.22 * Lf
            heel = slab("heel_" + s, [(p[0], p[1]) for p in sole_outline(fi2, 0.002, e=3.0, heel_w=0.9, toe_off=0.006, heel_off=0.004) if p[1] > hy], floor, floor + 0.022)
            out[key] += [so, heel]
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
        for objs in out.values():
            _tag(objs, s)
    for k, objs in out.items():
        for o in objs:
            w_legs(o, L)
    return out


def _tag(objs, s):
    for o in objs:
        if "side" not in o:
            o["side"] = s
    return objs


# ================================================================ 帯
def torso_section(o, L, z, band=0.012, add_x=0.018):
    """o（小袖など）の高さ z での胴の断面：前後の厚みは中央の帯から実測、幅は骨からの寸法（袖が横に下がるので測らない）。"""
    c0, rx0, ry0 = G.tsection_dims(L)(None, z)
    mw = o.matrix_world
    ys = []
    for v in o.data.vertices:
        q = mw @ v.co
        if abs(q.z - z) < band and abs(q.x - c0.x) < 0.05:
            ys.append(q.y)
    if len(ys) < 4:
        return c0, rx0 + add_x, ry0 + 0.012
    cy = (min(ys) + max(ys)) / 2
    return Vector((c0.x, cy, z)), rx0 + add_x, (max(ys) - min(ys)) / 2


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
        zc = L["spine_01"].z + 0.05
        wdt = 0.17
    else:
        zc = L["spine_01"].z + 0.012
        wdt = 0.065
    z0, z1 = zc - wdt / 2, zc + wdt / 2
    c, rx, ry = torso_section(kosode, L, zc, band=wdt / 2)
    rx -= 0.03 - 0.012
    ry -= 0.035 - 0.012
    band = _band("obi_band", c, rx + 0.03, ry + 0.035, z0, z1, slant=0.0 if female else 0.012)
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
        ag = _band("obiage", c, rx + 0.024, ry + 0.029, z1 - 0.004, z1 + 0.014, n=40)
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


# ================================================================ まとめ
def make_extra(body_p, L, female, ks):
    """追加パーツ一式：{パーツ名: [オブジェクト]} と、UV を自前で付けたパーツ名の集合。"""
    groups = {}
    custom_uv = set()
    fw = footwear(body_p, L)
    groups.update(fw)
    custom_uv.update(["zori", "geta", "waraji", "puttee"])
    groups.update(obi(ks, L, female))
    for name, fn in EXTRA_BUILDERS:
        g, cu = fn(body_p, L, female, ks)
        groups.update(g)
        custom_uv.update(cu)
    # ゲートルはズボンの上、脛当は小袴の上に巻く
    if "trousers" in groups:
        for o in groups["puttee"]:
            push_out(o, groups["trousers"][0], 0.004)
    if "kobakama" in groups:
        for o in groups["suneate"]:
            push_out(o, groups["kobakama"][0], 0.004)
    return groups, custom_uv


EXTRA_BUILDERS = []   # 甲冑・近代の服などを後から登録する: (名前, fn(body_p, L, female, ks) -> (groups, custom_uv))


# ================================================================ 確認用の撮影（Blender Cycles）
PREVIEW_COLORS = {
    "kosode": (0.2, 0.3, 0.6), "tamoto": (0.2, 0.3, 0.6), "eri": (0.1, 0.1, 0.1), "haneri": (0.95, 0.95, 0.95),
    "hakama": (0.5, 0.5, 0.55), "robe": (0.9, 0.6, 0.7), "obi": (0.85, 0.65, 0.25), "taiko": (0.85, 0.65, 0.25),
    "obijime": (0.7, 0.1, 0.15), "obiage": (0.95, 0.5, 0.6), "tabi": (0.96, 0.96, 0.96), "tabi_g": (0.96, 0.96, 0.96),
    "zori": (0.85, 0.75, 0.5), "zori_hanao": (0.75, 0.1, 0.15), "geta": (0.65, 0.45, 0.25), "geta_hanao": (0.1, 0.1, 0.1),
    "waraji": (0.8, 0.7, 0.4), "shoes": (0.08, 0.06, 0.05), "boots": (0.3, 0.18, 0.1), "boots_h": (0.25, 0.12, 0.08),
    "puttee": (0.5, 0.45, 0.3),
}


def preview(garments, body_p, L, path, parts="", cams="front,back,feet"):
    import random
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 12
    sc.cycles.device = "CPU"
    sc.render.resolution_x = 700
    sc.render.resolution_y = 1000
    sc.render.film_transparent = False
    def hidden(q):
        for sd in ("l", "r"):
            sh, wr = L["upperarm_" + sd], L["hand_" + sd]
            ax = wr - sh
            t = (q - sh).dot(ax) / ax.length_squared
            if t > 0.93 and (q - (sh + ax * t)).length < 0.12:
                return False
        return q.z < L["neck_01"].z - 0.025
    delete_verts(body_p, hidden)
    sets = parts.split("|") if parts else [""]
    for k, o in garments.items():
        for md in o.modifiers:
            if md.type == "ARMATURE":
                md.show_render = False
                md.show_viewport = False
        m = bpy.data.materials.new("pv_" + k)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        random.seed(hash(k) & 0xffff)
        col = PREVIEW_COLORS.get(k, (random.random(), random.random(), random.random()))
        bsdf.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1)
        bsdf.inputs["Roughness"].default_value = 0.8
        o.data.materials.clear()
        o.data.materials.append(m)
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.78, 0.85, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("pvcam", bpy.data.cameras.new("pvcam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    h = L["head"].z + 0.25
    c = L["pelvis"]
    views = {
        "front": (Vector((c.x - 0.8, -3, h * 0.5)), Vector((c.x, 0, h * 0.5)), h * 1.08),
        "back": (Vector((c.x + 0.8, 3, h * 0.5)), Vector((c.x, 0, h * 0.5)), h * 1.08),
        "side": (Vector((c.x + 3, -0.6, h * 0.5)), Vector((c.x, 0, h * 0.5)), h * 1.08),
        "feet": (Vector((c.x - 1.2, -2.2, L["floor"] + 1.0)), Vector((c.x, -0.02, L["floor"] + 0.08)), 0.42),
        "head": (Vector((c.x - 1.4, -2.4, L["head"].z + 0.6)), Vector((c.x, 0, L["head"].z + 0.08)), 0.6),
        "headb": (Vector((c.x + 1.4, 2.4, L["head"].z + 0.6)), Vector((c.x, 0, L["head"].z + 0.08)), 0.6),
        "torso": (Vector((c.x - 0.9, -3, L["spine_03"].z + 0.3)), Vector((c.x, 0, L["spine_01"].z + 0.05)), 0.75),
        "torsob": (Vector((c.x + 0.9, 3, L["spine_03"].z + 0.3)), Vector((c.x, 0, L["spine_01"].z + 0.05)), 0.75),
        "legs": (Vector((c.x - 1.0, -3, L["calf_l"].z + 0.3)), Vector((c.x, 0, L["calf_l"].z)), 1.0),
    }
    for si, pset in enumerate(sets):
        want = [p for p in pset.split(",") if p] or list(garments.keys())
        keep = {body_p.name}
        for o in bpy.data.objects:
            if o.type == "MESH" and o.name.startswith(("Face", "Hair")):
                keep.add(o.name)
        for k in want:
            if k in garments:
                keep.add(garments[k].name)
        for o in bpy.data.objects:
            if o.type == "MESH":
                o.hide_render = o.name not in keep
        for vname in cams.split(","):
            if vname not in views:
                continue
            loc, tgt, scale = views[vname]
            cam.location = loc
            cam.rotation_euler = (tgt - loc).to_track_quat("-Z", "Y").to_euler()
            cam.data.ortho_scale = scale
            sc.render.filepath = path + ("_%d" % si if len(sets) > 1 else "") + "_" + vname + ".png"
            bpy.ops.render.render(write_still=True)


# ================================================================ 下着の殻・脚の殻
def legs_shell(L, name, waist_z, hem_z, off, thigh_r, knee_r, calf_r, hem_r, calf_z=None, waist_r=None, hip_add=0.0):
    """二股の筒（ズボン・もんぺ・小袴）：腰→尻→左右の太腿→膝→ふくらはぎ→裾。"""
    D = G.dims(L)
    c = D["center"]
    nodes, edges = [], []

    def add(p, rx, ry):
        nodes.append((p, rx, ry))
        return len(nodes) - 1
    wr = waist_r or (D["waist"][0] + off, D["waist"][1] + off)
    wst = add(Vector((c.x, c.y, waist_z)), wr[0], wr[1])
    hip = add(Vector((c.x, c.y, L["pelvis"].z)), D["hip"][0] + off + hip_add, D["hip"][1] + off + hip_add)
    edges.append((wst, hip))
    for s in ("l", "r"):
        th, kn, ft = L["thigh_" + s], L["calf_" + s], L["foot_" + s]
        top = add(Vector((th.x * 1.12 + c.x * -0.12, th.y, L["pelvis"].z - 0.11)), thigh_r, thigh_r * 1.05)
        knee = add(kn.copy(), knee_r, knee_r * 1.05)
        edges += [(hip, top), (top, knee)]
        prev = knee
        if calf_z is not None:
            t = (kn.z - calf_z) / max(kn.z - ft.z, 0.01)
            cp = kn.lerp(ft, t)
            cn = add(Vector((cp.x, cp.y, calf_z)), calf_r, calf_r * 1.05)
            edges.append((prev, cn))
            prev = cn
        t = (kn.z - hem_z) / max(kn.z - ft.z, 0.01)
        hp = kn.lerp(ft, t)
        hn = add(Vector((hp.x, hp.y, hem_z - 0.01)), hem_r, hem_r * 1.06)
        edges.append((prev, hn))
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(n[0]) for n in nodes], edges, [])
    me.update()
    g = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(g)
    sk = g.modifiers.new("skin", "SKIN")
    sk.use_smooth_shade = True
    sv = me.skin_vertices[0].data
    for i, (p, rx, ry) in enumerate(nodes):
        sv[i].radius = (rx, ry)
    sv[hip].use_root = True
    sub = g.modifiers.new("sub", "SUBSURF")
    sub.levels = 2
    rm = g.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.006
    sm = g.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.6
    sm.iterations = 6
    dec = g.modifiers.new("dec", "DECIMATE")
    dec.ratio = 0.16
    for m in list(g.modifiers):
        apply_mod(g, m)
    delete_verts(g, lambda q: q.z > waist_z - 0.004 or q.z < hem_z + 0.002)
    for p in g.data.polygons:
        p.use_smooth = True
    return g


def under_shell(body_p, L, female, name, offset=0.006, top_dz=0.03, bottom=None):
    """袖の細い小袖（具足下・書生の白シャツ）。"""
    hip_z = L["pelvis"].z
    return G.shell(body_p, L, name, L["neck_01"].z + top_dz, bottom if bottom is not None else hip_z - 0.06, offset,
                   sleeve_flare=0.0)


# ================================================================ 当世具足
def _rad(L, z, m):
    tsec = G.tsection_dims(L)
    c, rx, ry = tsec(None, z)
    return c, rx + m, ry + m * 1.15


def _tiers_uv(k, circ_or_w, tile_w=0.18):
    return lambda s, t: (s * circ_or_w / tile_w * TILE, (k + 1 - t) * TILE)


def armor(body_p, L, female, ks):
    out = {}
    cu = set()
    D = G.dims(L)
    neck = L["neck_01"]
    # 具足下：袖の細い小袖と、その衿
    kt = under_shell(body_p, L, female, "kosode_t", offset=0.008)
    G.bone_weights(kt, L)
    er, han = G.collar(kt, L)
    for e in er + han:
        G.bone_weights(e, L)
    out["kosode_t"] = [kt]
    out["eri_t"] = er
    out["haneri_t"] = han
    # ---- 胴：小札の段を 6 段。上の段の裾が下の段の上端にかぶさる
    z_bot = L["pelvis"].z + 0.035
    z_front = L["spine_03"].z + 0.04
    nb = 6
    span = (z_front - z_bot) / nb
    do = []

    def top_z(a):
        fr = max(0.0, -math.sin(a))     # 前
        bk = max(0.0, math.sin(a))      # 後ろ
        side = abs(math.cos(a)) ** 3
        return z_front + 0.045 * bk - 0.055 * side * (1 - bk * 0.3) - 0.0 * fr

    for k in range(nb):
        zt0 = z_bot + (nb - k) * span + 0.012
        zb = z_bot + (nb - k - 1) * span

        def f(s, t, k=k, zt0=zt0, zb=zb):
            a = 2 * math.pi * s
            zt = top_z(a) if k == 0 else zt0
            z = lerp(zt, zb, t)
            c, rx, ry = _rad(L, max(z, z_bot + span), 0.04)
            fl = 1.0 + 0.035 * t
            flat = 1.0 - 0.06 * max(0.0, -math.sin(a)) ** 2   # 前は少し平らに
            return Vector((c.x + math.cos(a) * rx * fl, c.y + math.sin(a) * ry * fl * flat, z))
        c0, rx0, ry0 = _rad(L, zb, 0.04)
        circ = math.pi * (rx0 + ry0)
        b = grid("do_%d" % k, f, 56, 3, closed_u=True, uvf=_tiers_uv(nb - 1 - k, circ))
        face_away(b, Vector((c0.x, c0.y, zb)))
        solidify(b, 0.004)
        do.append(b)
    # 綿噛（肩の上を前後に渡す帯）
    for sd in (1, -1):
        cf, rxf, ryf = _rad(L, z_front, 0.04)
        pf = Vector((neck.x + sd * 0.075, cf.y - ryf * 0.92, z_front - 0.01))
        pb = Vector((neck.x + sd * 0.075, cf.y + ryf * 0.95, z_front + 0.035))
        ptop = Vector((neck.x + sd * 0.085, neck.y + 0.005, neck.z - 0.02))
        pts = []
        for i in range(13):
            u = i / 12
            p = (pf.lerp(ptop, u * 2) if u < 0.5 else ptop.lerp(pb, (u - 0.5) * 2))
            pts.append(p)
        bv = bvh_of(ks)

        def fw(s, t, pts=pts, sd=sd):
            i = t * (len(pts) - 1)
            k2 = min(int(i), len(pts) - 2)
            p = pts[k2].lerp(pts[k2 + 1], i - k2) + Vector((lerp(-0.022, 0.022, s), 0, 0))
            loc, nrm, _, _ = bv.find_nearest(p)
            return loc + nrm * 0.012 if loc is not None else p
        wg = grid("watagami", fw, 3, 16)
        face_away(wg, Vector((neck.x, neck.y, neck.z - 0.15)))
        solidify(wg, 0.006)
        do.append(wg)
    for o in do:
        G.bone_weights(o, L, arms=False)
    out["do"] = do
    cu.add("do")
    # ---- 草摺：7 間、各 4 段。胴の裾の下から腿の中ほどまで
    ks_ = []
    nk = 7
    tiers = 4
    th = 0.058
    kz0 = z_bot + 0.012
    c0, rx0, ry0 = _rad(L, z_bot, 0.04)
    rx0 *= 1.02
    ry0 *= 1.02
    for i in range(nk):
        a0 = -math.pi / 2 + (i - 0.5) * 2 * math.pi / nk + 0.035
        a1 = -math.pi / 2 + (i + 0.5) * 2 * math.pi / nk - 0.035
        for j in range(tiers):
            zt = kz0 - j * (th - 0.014)
            zb = zt - th

            def fk(s, t, j=j, zt=zt, zb=zb, a0=a0, a1=a1):
                a = lerp(a0, a1, s)
                z = lerp(zt, zb, t)
                d = (kz0 - z) / (tiers * th)
                fl = 1.0 + 0.22 * d + 0.03 * t
                return Vector((c0.x + math.cos(a) * rx0 * fl, c0.y + math.sin(a) * ry0 * fl, z))
            w_ = (a1 - a0) * (rx0 + ry0) / 2
            b = grid("kusazuri", fk, 10, 2, uvf=_tiers_uv(j, w_))
            face_away(b, Vector((c0.x, c0.y, zt)))
            solidify(b, 0.004)
            ks_.append(b)
    for o in ks_:
        G.bone_weights(o, L, arms=False, legs=0.35)
    out["kusazuri"] = ks_
    cu.add("kusazuri")
    # ---- 袖（大袖ふうの当世袖）：肩から上腕の外側に下がる 6 段の板
    sode = []
    for s in ("l", "r"):
        sx = 1.0 if s == "l" else -1.0
        sh, el = L["upperarm_" + s], L["lowerarm_" + s]
        d = (el - sh).normalized()
        outv = Vector((sx, 0, 0)) - d * (d.x * sx)
        outv.normalize()
        fb = Vector((0, 1, 0))
        w = 0.17
        n6 = 6
        tl = 0.036
        for j in range(n6):
            s0 = -0.015 + j * tl

            def fs(u, t, j=j, s0=s0, sh=sh, d=d, outv=outv):
                x = lerp(-w / 2, w / 2, u)
                along = s0 + t * (tl + 0.012)
                curve = -0.035 * (x / (w / 2)) ** 2
                return sh + d * along + fb * (x + 0.01) + outv * (0.078 + along * 0.18 + curve + 0.008 * t)
            b = grid("sode", fs, 10, 2, uvf=_tiers_uv(j, w))
            face_away(b, sh + d * 0.1)
            solidify(b, 0.004)
            b2 = b
            w_arm(b2, L, s)
            sode.append(b2)
    out["sode"] = sode
    cu.add("sode")
    # ---- 籠手：前腕の筏（細長い板 3 本）・肘金・上腕の小板・手甲
    kote = []
    for s in ("l", "r"):
        sx = 1.0 if s == "l" else -1.0
        sh, el, wr = L["upperarm_" + s], L["lowerarm_" + s], L["hand_" + s]
        ax = wr - sh
        te = (el - sh).dot(ax) / ax.length_squared
        d = ax.normalized()
        outv = Vector((sx, 0, 0)) - d * (d.x * sx)
        outv.normalize()
        side = d.cross(outv).normalized()
        plates = []
        for k_, ang in enumerate((-0.55, 0.0, 0.55)):
            def fp(u, t, ang=ang, d=d, outv=outv, side=side):
                tt = lerp(te + 0.06, 0.96, t)
                r = lerp(0.056, 0.047, t)
                a = ang + lerp(-0.2, 0.2, u)
                c = sh + ax * tt
                return c + (outv * math.cos(a) + side * math.sin(a)) * r
            b = grid("ikada", fp, 2, 8)
            face_away(b, sh + ax * 0.7)
            solidify(b, 0.003)
            plates.append(b)
        # 上腕：小さな板を 2 列
        for row in range(3):
            for ang in (-0.4, 0.4):
                def fu(u, t, ang=ang, row=row, d=d, outv=outv, side=side):
                    tt = lerp(0.2 + row * 0.1, 0.27 + row * 0.1, t)
                    a = ang + lerp(-0.28, 0.28, u)
                    return sh + ax * tt + (outv * math.cos(a) + side * math.sin(a)) * 0.07
                b = grid("kote_up", fu, 3, 2)
                face_away(b, sh + ax * 0.25)
                solidify(b, 0.003)
                plates.append(b)
        elbow = sh + ax * te
        plates.append(stud("hijigane", elbow + outv * 0.055, outv, 0.024, 0.008, 12))
        # 手甲：手の甲（腕を下ろした姿勢では外側）を覆う板
        hd = L["hand_" + s]

        def fh(u, t, hd=hd, d=d, outv=outv, side=side):
            a = lerp(-0.7, 0.7, u)
            return hd + d * lerp(-0.01, 0.07, t) + outv * (0.016 + 0.012 * math.cos(a)) + side * 0.028 * math.sin(a)
        b = grid("tekko", fh, 6, 4)
        face_away(b, hd - outv * 0.05)
        solidify(b, 0.003)
        plates.append(b)
        for b in plates:
            w_arm(b, L, s, hand=True)
        kote += plates
    out["kote"] = kote
    # ---- 小袴（腿は太く、膝下は細く脛当の中へ）
    hip_w = D["hip"][0] - 0.07
    kb = legs_shell(L, "kobakama", L["spine_01"].z - 0.02, L["floor"] + 0.09, 0.02, hip_w + 0.05, 0.085, 0.052, 0.045,
                    calf_z=L["calf_l"].z - 0.15, hip_add=0.01)
    w_legs(kb, L)
    out["kobakama"] = [kb]
    # ---- 佩楯：腰から膝上まで、腿の前を覆う板の段
    hd_ = []
    for s in ("l", "r"):
        sx = 1.0 if s == "l" else -1.0
        th_, kn = L["thigh_" + s], L["calf_" + s]
        zt = L["pelvis"].z + 0.01
        zb = kn.z + 0.05
        n5 = 5
        tl = (zt - zb) / n5
        for j in range(n5 + 1):
            z1 = zt - j * tl + (0.012 if j else 0.0)
            z2 = zt - (j + 1) * tl if j < n5 else zt - n5 * tl
            if j == n5:
                break

            def fhd(u, t, j=j, z1=z1, z2=z2, sx=sx, th_=th_, kn=kn):
                z = lerp(z1, z2, t)
                k = (th_.z - z) / max(th_.z - kn.z, 0.01)
                c = th_.lerp(kn, max(0.0, k))
                c = Vector((c.x + sx * 0.012, c.y, z))
                a = -math.pi / 2 + sx * lerp(-1.25, 1.6, u)
                r = lerp(0.128, 0.104, max(0.0, k)) + 0.006 * t
                return Vector((c.x + math.cos(a) * r, c.y + math.sin(a) * r * 0.95, z))
            b = grid("haidate", fhd, 12, 2, uvf=_tiers_uv(j, 0.25))
            face_away(b, Vector((th_.x, th_.y, z1)))
            solidify(b, 0.004)
            b["side"] = s
            hd_.append(b)
    for o in hd_:
        w_legs(o, L, crotch=0.06)
    out["haidate"] = hd_
    cu.add("haidate")
    # ---- 脛当：膝下から足首まで、脛の前と横を覆う篠（縦の板）
    sn = []
    for s in ("l", "r"):
        sx = 1.0 if s == "l" else -1.0
        kn, ft = L["calf_" + s], L["foot_" + s]
        z1, z0 = kn.z - 0.03, L["floor"] + 0.125

        def fsn(u, t, kn=kn, ft=ft, z0=z0, z1=z1):
            z = lerp(z1, z0, t)
            k = (kn.z - z) / max(kn.z - ft.z, 0.01)
            c = kn.lerp(ft, k)
            a = -math.pi / 2 + lerp(-2.1, 2.1, u)
            r = lerp(0.07, 0.056, ss(0.1, 0.9, t)) + 0.012 * ss(0.0, 0.25, 1 - t) * 0
            return Vector((c.x + math.cos(a) * r, c.y + math.sin(a) * r * 1.05, z))
        b = grid("suneate", fsn, 20, 8, uvf=lambda u, t: (u * 0.3 / 0.18 * TILE, t * 2 * TILE))
        face_away(b, Vector((kn.x, kn.y, (z0 + z1) / 2)))
        solidify(b, 0.004)
        # 立挙（膝の上の小さな板）
        kp = grid("tateage", lambda u, t, kn=kn: Vector((kn.x + math.cos(-math.pi / 2 + lerp(-1.0, 1.0, u)) * 0.072,
                                                         kn.y + math.sin(-math.pi / 2 + lerp(-1.0, 1.0, u)) * 0.075 - 0.004 * t,
                                                         lerp(kn.z + 0.05, kn.z - 0.03, t))), 8, 2,
                  uvf=lambda u, t: (u * 0.12 / 0.18 * TILE, t * TILE))
        face_away(kp, Vector((kn.x, kn.y, kn.z)))
        solidify(kp, 0.004)
        b["side"] = s
        kp["side"] = s
        sn += [b, kp]
    for o in sn:
        w_legs(o, L)
    out["suneate"] = sn
    cu.add("suneate")
    # ---- 兜
    h, _ = head_frame(L)
    hc = Vector((h.x, h.y + 0.012, h.z + 0.095))
    RX, RY, RZ = 0.128, 0.142, 0.15

    def rim_dz(a):
        return lerp(-0.024, 0.012, max(0.0, -math.sin(a)) ** 1.5)

    def bowl(s, t):
        a = 2 * math.pi * s
        phr = math.asin(max(-0.9, min(0.9, rim_dz(a) / RZ)))
        ph = lerp(math.pi / 2, phr, t)
        return Vector((hc.x + math.cos(a) * math.cos(ph) * RX, hc.y + math.sin(a) * math.cos(ph) * RY, hc.z + math.sin(ph) * RZ))
    hachi = grid("hachi", bowl, 64, 14, closed_u=True, uvf=lambda s, t: (s * 8 * TILE, (1 - t) * 1.5 * TILE))
    face_away(hachi, hc)
    solidify(hachi, 0.004)
    # 眉庇（前の庇）
    a0, a1 = -math.pi / 2 - 1.0, -math.pi / 2 + 1.0
    mab = grid("mabizashi", lambda u, t: bowl((lerp(a0, a1, u)) / (2 * math.pi) % 1.0, 1.0) +
               Vector((math.cos(lerp(a0, a1, u)), math.sin(lerp(a0, a1, u)), 0)) * (0.05 * t * (1 - 0.5 * abs(u - 0.5) * 2) ** 0.5) +
               Vector((0, 0, -0.016 * t)), 16, 2)
    face_away(mab, hc + Vector((0, 0, 0.2)))
    solidify(mab, 0.004)
    out["kabuto"] = [hachi, mab]
    cu.add("kabuto")
    # 錣：鉢の下縁から首の後ろへ広がる 4 段。前の両端は吹返し
    shik = []
    ae0, ae1 = -math.pi / 2 + 0.95, -math.pi / 2 + 2 * math.pi - 0.95
    for j in range(4):
        def fsk(u, t, j=j):
            a = lerp(ae0, ae1, u)
            base = bowl(a / (2 * math.pi) % 1.0, 1.0)
            z = base.z + 0.006 - j * 0.03 - t * 0.042
            r = 1.0 + 0.06 + 0.11 * j + 0.06 * t
            return Vector((hc.x + (base.x - hc.x) * r, hc.y + (base.y - hc.y) * r, z))
        b = grid("shikoro", fsk, 40, 2, uvf=_tiers_uv(j, 0.75))
        face_away(b, hc)
        solidify(b, 0.004)
        shik.append(b)
    for ae, sd in ((ae0, 1), (ae1, -1)):
        def ffk(u, t, ae=ae, sd=sd):
            base = bowl(ae / (2 * math.pi) % 1.0, 1.0)
            rad = Vector((base.x - hc.x, base.y - hc.y, 0)).normalized()
            tan = Vector((-rad.y, rad.x, 0)) * sd
            return base + rad * (0.01 + 0.06 * u) + tan * (0.02 * u) + Vector((0, 0, 0.004 - 0.075 * t + 0.015 * u))
        b = grid("fukigaeshi", ffk, 4, 4, uvf=lambda u, t: (u * 0.4 * TILE, (1 - t) * TILE))
        face_away(b, hc + Vector((0, -0.3, 0)))
        solidify(b, 0.004)
        shik.append(b)
    out["shikoro"] = shik
    cu.add("shikoro")
    # 前立：金の鍬形と、付け根の丸い金具
    fz = hc.z + 0.03
    front_y = hc.y - RY + 0.004
    mt = []
    for sd in (1, -1):
        pts = [(0.022, 0.0), (0.05, 0.07), (0.08, 0.15), (0.095, 0.22), (0.088, 0.28)]
        wid = [0.024, 0.022, 0.018, 0.013, 0.006]

        def fm(u, t, sd=sd, pts=pts, wid=wid):
            i = t * (len(pts) - 1)
            k = min(int(i), len(pts) - 2)
            fr = i - k
            x = lerp(pts[k][0], pts[k + 1][0], fr)
            z = lerp(pts[k][1], pts[k + 1][1], fr)
            w = lerp(wid[k], wid[k + 1], fr)
            return Vector((hc.x + sd * (x + lerp(-w / 2, w / 2, u)), front_y - 0.012 - 0.04 * t * t, fz + z))
        b = grid("kuwagata", fm, 2, 16)
        face_away(b, Vector((hc.x, 0.5, fz)))
        solidify(b, 0.004)
        mt.append(b)
    mt.append(stud("maedate_dai", Vector((hc.x, front_y - 0.004, fz + 0.005)), Vector((0, -1, 0)), 0.024, 0.01, 14))
    mt.append(stud("tehen", hc + Vector((0, 0, RZ - 0.002)), Vector((0, 0, 1)), 0.016, 0.006, 12))
    out["maedate"] = mt
    # 陣笠：浅い円錐の笠＋顎紐、正面に家紋の丸
    apex = h.z + 0.29
    rimz = h.z + 0.135
    jc = Vector((h.x, h.y + 0.01, 0))

    def fj(s, t):
        a = 2 * math.pi * s
        z = apex - (apex - rimz) * t ** 0.9 - 0.012 * ss(0.85, 1.0, t)
        return Vector((jc.x + math.cos(a) * 0.215 * t, jc.y + math.sin(a) * 0.228 * t, z))
    jg = grid("jingasa", fj, 48, 10, closed_u=True, uvf=lambda s, t: (s * 2 * TILE, t * TILE))
    face_away(jg, Vector((jc.x, jc.y, rimz - 0.2)))
    solidify(jg, 0.006)
    cords = []
    for sd in (1, -1):
        p0 = Vector((h.x + sd * 0.095, h.y + 0.01, rimz + 0.035))
        p1 = Vector((h.x + sd * 0.1, h.y - 0.005, h.z + 0.02))
        p2 = Vector((h.x + sd * 0.04, h.y - 0.06, h.z - 0.045))
        p3 = Vector((h.x, h.y - 0.075, h.z - 0.055))
        cords.append(tube("agohimo", [p0, p1, p2, p3], 0.003, 6))
    out["jingasa"] = [jg] + cords
    tm = 0.55
    pm = fj(0.75, tm)
    nrm = (fj(0.75, tm + 0.01) - fj(0.75, tm - 0.01)).cross(Vector((1, 0, 0))).normalized()
    if nrm.y > 0:
        nrm = -nrm
    out["jingasa_mon"] = [stud("mon", pm + nrm * 0.0005, nrm, 0.038, 0.002, 20)]
    for key in ("kabuto", "shikoro", "maedate", "jingasa", "jingasa_mon"):
        for o in out[key]:
            w_single(o, L, "head")
    return out, cu


EXTRA_BUILDERS.append(("armor", armor))


# ================================================================ 近代の服
def coat_shell(L, name, hem_z, off, hem_flare=0.012, sleeve=(0.05, 0.043, 0.038), wrist_t=0.95, shoulder_pad=0.0):
    """洋服の胴と袖：胴の輪切りを重ねた筒＋腕に沿う袖の筒を、ボクセルで一体化した殻（首・裾・袖口は開ける）。"""
    tsec = G.tsection_dims(L)
    neck = L["neck_01"]
    nz = neck.z
    chest_z = L["spine_03"].z
    sh_z = (L["upperarm_l"].z + L["upperarm_r"].z) / 2
    sh_w = abs(L["upperarm_l"].x - L["upperarm_r"].x) / 2
    D = G.dims(L)
    cy = D["center"].y
    zs = []
    z = hem_z - 0.01
    while z < nz + 0.03:
        zs.append(z)
        z += 0.02
    zs.append(nz + 0.03)
    c_ch, rx_ch, ry_ch = tsec(None, chest_z)

    def f(s, t):
        z = lerp(zs[0], zs[-1], t)
        a = 2 * math.pi * s
        if z <= chest_z:
            c, rx, ry = tsec(None, z)
            rx += off + hem_flare * ss(L["pelvis"].z, hem_z, z)
            ry += off + hem_flare * ss(L["pelvis"].z, hem_z, z)
            e = 2.0
        else:
            u = ss(sh_z - 0.04, nz + 0.03, z)
            k = (z - chest_z) / max(sh_z - chest_z, 0.01)
            rx0 = lerp(rx_ch + off, sh_w * 0.92 + off + shoulder_pad, min(1.0, k))
            ry0 = ry_ch + off
            rx = lerp(rx0, 0.072, u ** 1.3)
            ry = lerp(ry0, 0.066, u ** 1.1)
            e = lerp(2.4, 2.0, u)
        ex, ey = _superellipse(a, e)
        cyy = lerp(cy, (neck.y + cy) / 2 + 0.003, ss(chest_z, nz, z))
        return Vector((neck.x + ex * rx, cyy + ey * ry, z))
    torso = grid(name + "_t", f, 48, len(zs) - 1, closed_u=True, cap0=True, cap1=True)
    parts = [torso]
    for sd in ("l", "r"):
        sh, el, wr = L["upperarm_" + sd], L["lowerarm_" + sd], L["hand_" + sd]
        ax = wr - sh
        sx = 1.0 if sd == "l" else -1.0
        p0 = sh + Vector((-sx * 0.03, 0, -0.012))
        pts = [p0, sh + ax * 0.25, el, sh + ax * (wrist_t + 0.03)]
        rs = [sleeve[0] + off, lerp(sleeve[0], sleeve[1], 0.5) + off, sleeve[1] + off, sleeve[2] + off]
        dense, drs = [], []
        for i in range(len(pts) - 1):
            for k in range(6):
                u = k / 6
                dense.append(pts[i].lerp(pts[i + 1], u))
                drs.append(lerp(rs[i], rs[i + 1], u))
        dense.append(pts[-1])
        drs.append(rs[-1])
        parts.append(tube(name + "_s", dense, drs, 16))
    o = remesh_solid(parts, name, voxel=0.005, smooth=6, ratio=1.0)
    bm = bmesh.new()
    bm.from_mesh(o.data)

    def bis(geom_pred, co, no):
        geom = [f for f in bm.faces if geom_pred(f.calc_center_median())]
        gv = {v for f in geom for v in f.verts}
        ge = {e for f in geom for e in f.edges}
        res = bmesh.ops.bisect_plane(bm, geom=list(gv) + list(ge) + geom, plane_co=co, plane_no=no, clear_outer=True, dist=1e-5)
        return res
    bis(lambda c: c.z > L["spine_03"].z and abs(c.x - neck.x) < 0.13, Vector((0, 0, nz - 0.001)), Vector((0, 0, 1)))
    bis(lambda c: True, Vector((0, 0, hem_z)), Vector((0, 0, -1)))
    for sd in ("l", "r"):
        sh, wr = L["upperarm_" + sd], L["hand_" + sd]
        ax = wr - sh

        def near(c, sh=sh, ax=ax):
            t = (c - sh).dot(ax) / ax.length_squared
            return t > 0.6 and (c - (sh + ax * t)).length < 0.12
        bis(near, sh + ax * wrist_t, ax.normalized())
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    d = o.modifiers.new("dec", "DECIMATE")
    d.ratio = 0.25
    apply_mod(o, d)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def star(name, p, nrm, r, h=0.003):
    nrm = nrm.normalized()
    up = Vector((0, 0, 1))
    a = (up - nrm * up.dot(nrm)).normalized()
    b = nrm.cross(a)
    verts = []
    for z in (0.0, h):
        for k in range(10):
            ang = math.pi / 2 + 2 * math.pi * k / 10
            rr = r if k % 2 == 0 else r * 0.42
            verts.append(p + nrm * z + (a * math.sin(ang) + b * math.cos(ang)) * rr)
    verts += [p, p + nrm * h * 1.4]
    c0, c1 = len(verts) - 2, len(verts) - 1
    faces = [(k, (k + 1) % 10, 10 + (k + 1) % 10, 10 + k) for k in range(10)]
    faces += [((k + 1) % 10, k, c0) for k in range(10)] + [(10 + k, 10 + (k + 1) % 10, c1) for k in range(10)]
    o = mk(name, verts, faces, smooth=False)
    recalc_out(o)
    return o


def _ray_front(bvh, x, z, front=True):
    loc, nrm, _, _ = bvh.ray_cast(Vector((x, -2.0 if front else 2.0, z)), Vector((0, 1 if front else -1, 0)))
    return loc, nrm


def neck_ring(name, L, z0, z1, rb, rt, front_gap=0.0, drop=None, n=48):
    D = G.dims(L)
    neck = L["neck_01"]
    c = Vector((neck.x, (neck.y + D["center"].y) / 2 + 0.003, 0))
    a0 = -math.pi / 2 + front_gap
    a1 = -math.pi / 2 + 2 * math.pi - front_gap

    def f(s, t):
        a = lerp(a0, a1, s) if front_gap > 0 else 2 * math.pi * s
        zb = z0 - (drop(a) if drop else 0.0)
        z = lerp(zb, z1, t)
        rx = lerp(rb[0], rt[0], t)
        ry = lerp(rb[1], rt[1], t)
        return Vector((c.x + math.cos(a) * rx, c.y + math.sin(a) * ry, z))
    o = grid(name, f, n, 3, closed_u=front_gap <= 0)
    face_away(o, Vector((c.x, c.y, (z0 + z1) / 2)))
    solidify(o, 0.004)
    return o


def hakama_f(L, ks, n=72):
    """女袴（行灯袴）：胸の下から脛の中ほどまで、ひだのある筒（海老茶式部）。"""
    tsec = G.tsection_dims(L)
    top = L["spine_01"].z + 0.11
    hem = L["calf_l"].z - 0.17
    c0, rx0, ry0 = torso_section(ks, L, top - 0.03, band=0.04, add_x=0.012)
    rings = []
    steps = 16
    for i in range(steps + 1):
        t = i / steps
        z = lerp(top, hem, t)
        c, rx, ry = tsec(None, max(z, L["pelvis"].z))
        k = ss(0.0, 1.0, t)
        rx_ = max(rx, rx0) + 0.03 + 0.07 * k
        ry_ = max(ry, ry0) + 0.035 + 0.06 * k

        def wob(a, t=t):
            front = max(0.0, -math.sin(a))
            return (0.015 + 0.04 * t) * (front * abs(math.sin(a * 5)) ** 0.6 + (1 - front) * 0.4 * abs(math.sin(a * 3)))
        rings.append(K.ellipse(Vector((c0.x, c0.y, z)), rx_, ry_, n, wob))
    o = K.rings_to_mesh("hakama_f", rings)
    solidify(o, 0.004)
    himo = []
    for k, dz in enumerate((0.0, -0.03)):
        r = [K.ellipse(Vector((c0.x, c0.y, top + dz + 0.01)), rx0 + 0.032, ry0 + 0.037, 48),
             K.ellipse(Vector((c0.x, c0.y, top + dz - 0.01)), rx0 + 0.032, ry0 + 0.037, 48)]
        himo.append(K.rings_to_mesh("hakama_f_himo%d" % k, r))
    for x in [o] + himo:
        G.bone_weights(x, L, arms=False, legs=0.5)
    return [o] + himo


def western(body_p, L, female, ks):
    out = {}
    cu = set()
    neck = L["neck_01"]
    nx, nz = neck.x, neck.z
    hip_z = L["pelvis"].z
    waist_z = L["spine_01"].z
    chest_z = L["spine_03"].z
    floor = L["floor"]
    D = G.dims(L)
    # ---- 上着（背広・詰襟の軍服・海軍の白の共通の形）
    jk = coat_shell(L, "jacket", hip_z - (0.1 if female else 0.13), 0.024, hem_flare=0.014, wrist_t=0.94, shoulder_pad=0.01)
    w_coat(jk, L, (0.05 + 0.024, 0.043 + 0.024, 0.038 + 0.024))
    out["jacket"] = [jk]
    jb = bvh_of(jk)
    # ---- シャツ（昭和の男の白シャツ・女のブラウス）：裾はズボン・もんぺの中
    sh = coat_shell(L, "shirt", waist_z - 0.045, 0.01, hem_flare=0.0, sleeve=(0.047, 0.04, 0.036), wrist_t=0.95)
    w_coat(sh, L, (0.057, 0.05, 0.046))
    # 書生の着物の袖口からのぞくシャツの袖
    cuffs = []
    for sd in ("l", "r"):
        shp, wr = L["upperarm_" + sd], L["hand_" + sd]
        ax = wr - shp
        pts = [shp + ax * (0.62 + 0.34 * i / 6) for i in range(7)]
        cf = tube("shirt_cuff", pts, 0.05, 14)
        w_arm(cf, L, sd)
        cuffs.append(cf)
    out["shirt_cuff"] = cuffs
    out["shirt"] = [sh]
    # ---- ズボン・もんぺ
    hw = D["hip"][0] - 0.07
    tr = legs_shell(L, "trousers", waist_z - 0.005, floor + 0.035, 0.02, hw + 0.012, 0.064, 0.058, 0.057,
                    calf_z=L["calf_l"].z - 0.2)
    # シャツの裾はズボンの中：腰回りだけズボンをシャツの外へ
    vg = tr.vertex_groups.new(name="waist_push")
    vg.add([v.index for v in tr.data.vertices if v.co.z > waist_z - 0.08], 1.0, "REPLACE")
    sw = tr.modifiers.new("push", "SHRINKWRAP")
    sw.target = sh
    sw.wrap_method = "NEAREST_SURFACEPOINT"
    sw.wrap_mode = "OUTSIDE"
    sw.offset = 0.004
    sw.vertex_group = "waist_push"
    apply_mod(tr, sw)
    w_legs(tr, L)
    out["trousers"] = [tr]
    mp = legs_shell(L, "monpe", waist_z - 0.005, floor + 0.06, 0.026, hw + 0.03, 0.088, 0.078, 0.05,
                    calf_z=floor + 0.2, hip_add=0.012)
    w_legs(mp, L)
    out["monpe"] = [mp]
    # ---- 立襟（シャツの高い襟・学生服・軍服の詰襟）
    cs = neck_ring("collar_st", L, nz - 0.014, nz + 0.034, (0.066, 0.062), (0.058, 0.055))
    G.bone_weights(cs, L, arms=False)
    out["collar_st"] = [cs]
    # ---- 折り襟（昭和のシャツ・ブラウス）：前で尖った衿先
    def drop(a):
        d = abs(((a + math.pi / 2 + math.pi) % (2 * math.pi)) - math.pi)   # 前からの角度
        return 0.012 + 0.05 * ss(0.9, 0.25, d)
    sc = neck_ring("shirt_collar", L, nz - 0.01, nz + 0.024, (0.088, 0.083), (0.062, 0.058), front_gap=0.16, drop=drop)
    push_out(sc, sh, 0.003)
    G.bone_weights(sc, L, arms=False)
    out["shirt_collar"] = [sc]
    # 前立て（シャツのボタン）
    btn = []
    shb = bvh_of(sh)
    for i in range(4):
        z = nz - 0.06 - i * (nz - 0.06 - (waist_z + 0.02)) / 3.5
        loc, nrm = _ray_front(shb, nx, z)
        if loc is not None:
            btn.append(stud("sbtn", loc, nrm, 0.006, 0.003, 8))
    for o in btn:
        G.bone_weights(o, L, arms=False)
    out["btn_shirt"] = btn
    # ---- 背広の前：上着の V 開き（チョッキ・シャツ・ネクタイ・下襟）
    z_v = waist_z + 0.035
    z_vv = chest_z - 0.07
    vest = patch("vest", jk, [(nx + 0.075, nz - 0.004), (nx, z_v), (nx - 0.075, nz - 0.004), (nx - 0.046, nz - 0.004),
                              (nx, z_vv), (nx + 0.046, nz - 0.004)], 0.003, bvh=jb)
    shirt_v = patch("shirt_v", jk, [(nx + 0.05, nz - 0.0), (nx, z_vv - 0.006), (nx - 0.05, nz - 0.0)], 0.004, bvh=jb)
    tie = patch("tie", jk, [(nx - 0.012, nz - 0.022), (nx + 0.012, nz - 0.022), (nx + 0.007, nz - 0.046),
                            (nx + 0.018, z_vv - 0.01), (nx - 0.018, z_vv - 0.01), (nx - 0.007, nz - 0.046)], 0.006, bvh=jb)
    lap = []
    for sd in (1, -1):
        poly = [(nx + sd * 0.07, nz - 0.0), (nx + sd * 0.112, nz - 0.04), (nx + sd * 0.098, nz - 0.058),
                (nx + sd * 0.125, nz - 0.07), (nx + sd * 0.02, z_v + 0.004), (nx + sd * 0.0, z_v - 0.004)]
        lap.append(patch("lapel", jk, poly, 0.007, bvh=jb))
    vb = []
    vbv = bvh_of(vest)
    for i in range(3):
        z = z_vv - 0.025 - i * 0.04
        loc, nrm = _ray_front(vbv, nx, z)
        if loc is not None:
            vb.append(stud("vbtn", loc, nrm, 0.005, 0.003, 8))
    sb = []
    for z in (z_v - 0.03, z_v - 0.11):
        loc, nrm = _ray_front(jb, nx + 0.0, z)
        if loc is not None:
            sb.append(stud("jbtn", loc, nrm, 0.009, 0.004, 10))
    for key, objs in (("vest", [vest] + vb), ("shirt_v", [shirt_v]), ("tie", [tie]), ("lapel", lap), ("btn_suit", sb)):
        for o in objs:
            G.bone_weights(o, L, arms=False)
        out[key] = objs
    # ---- 詰襟の上着の前：ボタン 5 個・胸と腰のポケットの蓋・帯革・肩章・襟章
    tb = []
    zb_ = hip_z - 0.13 + 0.05
    for i in range(5):
        z = lerp(nz - 0.045, zb_, i / 4)
        loc, nrm = _ray_front(jb, nx, z)
        if loc is not None:
            tb.append(stud("tbtn", loc, nrm, 0.008, 0.004, 10))
    out["btn_tunic"] = tb
    pk = []
    for sd in (1, -1):
        cx = nx + sd * 0.068
        z = chest_z - 0.005
        pk.append(patch("pocket", jk, [(cx - 0.036, z), (cx + 0.036, z), (cx + 0.036, z - 0.022), (cx, z - 0.032), (cx - 0.036, z - 0.022)], 0.004, res=0.006, bvh=jb))
        cx = nx + sd * 0.08
        z = hip_z + 0.0
        pk.append(patch("pocket", jk, [(cx - 0.045, z), (cx + 0.045, z), (cx + 0.045, z - 0.03), (cx - 0.045, z - 0.03)], 0.004, res=0.006, bvh=jb))
    out["pockets"] = pk
    c_, rx_, ry_ = G.tsection_dims(L)(None, waist_z - 0.01)
    belt = _band("belt", c_, rx_ + 0.03, ry_ + 0.035, waist_z - 0.03, waist_z + 0.008)
    push_out(belt, jk, 0.004)
    bl = belt
    bk_loc, bk_n = _ray_front(bvh_of(bl), nx, waist_z - 0.011)
    out["belt"] = [bl]
    out["buckle"] = [stud("buckle", bk_loc, bk_n, 0.026, 0.006, 4)] if bk_loc is not None else []
    c_, rx_, ry_ = G.tsection_dims(L)(None, waist_z - 0.02)
    bt = _band("belt_t", c_, rx_ + 0.02, ry_ + 0.025, waist_z - 0.034, waist_z - 0.008)
    push_out(bt, tr, 0.003)
    out["belt_t"] = [bt]
    ep = []
    for sd in (1, -1):
        sh_ = L["upperarm_" + ("l" if sd > 0 else "r")]
        p0 = Vector((nx + sd * 0.06, neck.y, nz))
        p1 = Vector((sh_.x - sd * 0.0, sh_.y, sh_.z))

        def fe(u, t, p0=p0, p1=p1):
            p = p0.lerp(p1, lerp(0.35, 0.98, t)) + Vector((0, lerp(-0.024, 0.024, u), 0.0))
            loc, nrm, _, _ = jb.ray_cast(Vector((p.x, p.y, p.z + 0.3)), Vector((0, 0, -1)))
            if loc is None or loc.z < p1.z - 0.06:
                return p + Vector((0, 0, 0.01))
            return loc + Vector((0, 0, 0.004))
        e = grid("epaulet", fe, 3, 6)
        face_away(e, Vector((nx, neck.y, nz - 0.3)))
        solidify(e, 0.004)
        ep.append(e)
    out["epaulet"] = ep
    cb_ = bvh_of(cs)
    ct = []
    for sd in (1, -1):
        ct.append(patch("ctab", cs, [(nx + sd * 0.026, nz - 0.008), (nx + sd * 0.056, nz - 0.008), (nx + sd * 0.056, nz + 0.026), (nx + sd * 0.034, nz + 0.026)], 0.003, res=0.005, bvh=cb_))
    out["collar_tab"] = ct
    for key in ("btn_tunic", "pockets", "belt", "buckle", "epaulet", "collar_tab"):
        for o in out[key]:
            G.bone_weights(o, L, arms=False)
    # ---- 女袴
    out["hakama_f"] = hakama_f(L, ks)
    # ---- 帽子（頭の骨に付ける）
    h, _ = head_frame(L)
    hc = Vector((h.x, h.y + 0.012, h.z))
    # 山高帽
    def fbw(s, t):
        a = 2 * math.pi * s
        ph = lerp(math.pi / 2, 0.0, t)
        r = math.cos(ph)
        z = 0.115 + math.sin(ph) * 0.128
        return Vector((hc.x + math.cos(a) * r * 0.122, hc.y + math.sin(a) * r * 0.136, hc.z + z))
    crown = grid("bowler_c", fbw, 40, 10, closed_u=True)
    face_away(crown, hc + Vector((0, 0, 0.15)))
    solidify(crown, 0.004)

    def fbr(s, t):
        a = 2 * math.pi * s
        sidek = abs(math.cos(a)) ** 2
        r = lerp(1.0, 1.0 + 0.4, t)
        z = 0.112 + (0.022 * sidek - 0.006 * (1 - sidek)) * t * t
        return Vector((hc.x + math.cos(a) * r * 0.122, hc.y + math.sin(a) * r * 0.136, hc.z + z))
    brim = grid("bowler_b", fbr, 40, 3, closed_u=True)
    face_away(brim, hc + Vector((0, 0, 0.5)))
    solidify(brim, 0.004)
    band = grid("bowler_band", lambda s, t: Vector((hc.x + math.cos(2 * math.pi * s) * 0.1235, hc.y + math.sin(2 * math.pi * s) * 0.1375, hc.z + lerp(0.114, 0.134, t))), 40, 1, closed_u=True)
    face_away(band, hc + Vector((0, 0, 0.12)))
    out["bowler"] = [crown, brim, band]
    # 戦闘帽（略帽）：柔らかい筒に小さな庇、正面に星
    def ffc(s, t):
        a = 2 * math.pi * s
        if t < 0.7:
            u = t / 0.7
            z = lerp(0.1, 0.19, u)
            r = 1.0 + 0.04 * math.sin(math.pi * u * 0.8)
        else:
            u = (t - 0.7) / 0.3
            z = 0.19 + 0.032 * math.sin(math.pi * 0.5 * u)
            r = 1.04 * max(0.0, math.cos(math.pi * 0.5 * u)) ** 0.7
        front = max(0.0, -math.sin(a))
        return Vector((hc.x + math.cos(a) * r * 0.117, hc.y + math.sin(a) * r * 0.13, hc.z + z + 0.006 * front * (t > 0.3)))
    fc = grid("fcap", ffc, 40, 12, closed_u=True)
    face_away(fc, hc + Vector((0, 0, 0.15)))
    solidify(fc, 0.004)

    def visor(rx, ry, z, ext, a_half=0.95, droop=0.02):
        def fv(u, t):
            a = -math.pi / 2 + lerp(-a_half, a_half, u)
            e = ext * (1 - (abs(u - 0.5) * 2) ** 2.5) * t
            return Vector((hc.x + math.cos(a) * (rx + e * 0.4), hc.y + math.sin(a) * (ry + e), hc.z + z - droop * t * t))
        v = grid("visor", fv, 14, 3)
        face_away(v, hc + Vector((0, 0, 0.6)))
        solidify(v, 0.004)
        return v
    out["fcap"] = [fc, visor(0.118, 0.131, 0.102, 0.05)]
    loc, nrm = _ray_front(bvh_of(fc), hc.x, hc.z + 0.16)
    out["fcap_star"] = [star("star", loc + nrm * 0.001, nrm, 0.017)] if loc is not None else []
    # 制帽（海軍・学帽）：鉢巻（帯）＋平たい天井＋庇＋帽章
    pb = grid("pcap_band", lambda s, t: Vector((hc.x + math.cos(2 * math.pi * s) * 0.118, hc.y + math.sin(2 * math.pi * s) * 0.13, hc.z + lerp(0.1, 0.152, t))), 40, 2, closed_u=True)
    face_away(pb, hc + Vector((0, 0, 0.12)))
    solidify(pb, 0.004)

    def fpt(s, t):
        a = 2 * math.pi * s
        if t < 0.55:
            u = t / 0.55
            r = lerp(1.0, 1.2, math.sin(math.pi * 0.5 * u))
            z = lerp(0.15, 0.212, u)
        else:
            u = (t - 0.55) / 0.45
            r = 1.2 * (1 - u)
            z = 0.212 + 0.02 * math.sin(math.pi * 0.5 * u)
        back = max(0.0, math.sin(a))
        return Vector((hc.x + math.cos(a) * r * 0.118, hc.y + 0.006 * back + math.sin(a) * r * 0.132, hc.z + z + 0.012 * max(0.0, -math.sin(a)) * min(1.0, t * 2)))
    pt = grid("pcap_top", fpt, 40, 10, closed_u=True)
    face_away(pt, hc + Vector((0, 0, 0.15)))
    solidify(pt, 0.004)
    out["pcap_top"] = [pt]
    out["pcap_band"] = [pb, visor(0.119, 0.131, 0.1, 0.06, droop=0.028)]
    loc, nrm = _ray_front(bvh_of(pb), hc.x, hc.z + 0.128)
    out["pcap_badge"] = [stud("badge", loc, nrm, 0.017, 0.005, 12)] if loc is not None else []
    for key in ("bowler", "fcap", "fcap_star", "pcap_top", "pcap_band", "pcap_badge"):
        for o in out[key]:
            w_single(o, L, "head")
    return out, cu


EXTRA_BUILDERS.append(("western", western))
