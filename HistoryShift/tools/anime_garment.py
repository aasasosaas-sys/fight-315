"""アニメ素体（VRoid）向けの和装パーツ（vrm_wasou.py から呼ぶ）。腕を下ろした A ポーズの体で作る。

- 小袖の身頃・袖：体を少し膨らませた「殻」（シェル）。体の形に沿ったきれいなシルエット＋ウェイトは体のものそのまま
- 袂：腕の下に下がる袋。布シミュで自然に垂らす
- 衿：小袖の表面に沿わせた帯（右前：着る人の左身頃が上）と白い半衿
- 袴：ひだ付きの筒＋前紐。女性の着物は裾すぼまりの筒
- 帯：男は細帯、女は幅広の帯＋背中のお太鼓
"""
import math

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import kimono as K


def _weights(o):
    names = {vg.index: vg.name for vg in o.vertex_groups}
    out = []
    for v in o.data.vertices:
        out.append({names[g.group]: g.weight for g in v.groups if g.group in names})
    return out


def _sum(w, names):
    return sum(w.get(n, 0.0) for n in names)


def shell(body, L, name, top_z, bottom_z, offset, wrist_t=0.96, sleeve_flare=0.035, smooth=12):
    """体から胴（と腕）を切り出して膨らませた殻。袖口に向かって少し広げる。"""
    g = body.copy()
    g.data = body.data.copy()
    g.name = name
    bpy.context.collection.objects.link(g)
    for m in list(g.modifiers):
        g.modifiers.remove(m)
    W = _weights(g)
    head_names = [K.bn("head"), K.bn("neck_01")]
    hand_names = [K.bn("hand_l"), K.bn("hand_r")]
    mw = g.matrix_world
    arms = {}
    for s in ("l", "r"):
        sh, wr = L["upperarm_" + s], L["hand_" + s]
        arms[s] = (sh, wr, (wr - sh))
    bm = bmesh.new()
    bm.from_mesh(g.data)
    bm.verts.ensure_lookup_table()
    kill = []
    arm_t = {}
    for v in bm.verts:
        w = W[v.index]
        q = mw @ v.co
        if _sum(w, head_names) > 0.35 or _sum(w, hand_names) > 0.3:
            kill.append(v)
            continue
        on_arm = None
        for s, (sh, wr, ax) in arms.items():
            if _sum(w, [K.bn("upperarm_" + s), K.bn("lowerarm_" + s)]) > 0.5:
                on_arm = s
                t = (q - sh).dot(ax) / ax.length_squared
                if t > wrist_t:
                    kill.append(v)
                    on_arm = "x"
                else:
                    arm_t[v.index] = (s, t)
        if on_arm is None and (q.z > top_z or q.z < bottom_z):
            kill.append(v)
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(g.data)
    bm.free()
    # 体の起伏（筋肉・胸など）をならしてから膨らませる
    sm = g.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.8
    sm.iterations = smooth
    disp = g.modifiers.new("inflate", "DISPLACE")
    disp.strength = offset
    disp.mid_level = 0.0
    bpy.context.view_layer.objects.active = g
    for mn in ("smooth", "inflate"):
        with bpy.context.temp_override(object=g, active_object=g):
            bpy.ops.object.modifier_apply(modifier=mn)
    # 袖口へ向かって少し広げる（腕の軸から放射方向に押し出す）
    for v in g.data.vertices:
        q = mw @ v.co
        best = None
        for s, (sh, wr, ax) in arms.items():
            t = (q - sh).dot(ax) / ax.length_squared
            if 0.15 < t < 1.0:
                c = sh + ax * t
                d = q - c
                if d.length < 0.09 and (best is None or d.length < best[1].length):
                    best = (t, d)
        if best:
            t, d = best
            k = max(0.0, (t - 0.25) / 0.75) ** 1.4
            v.co = mw.inverted() @ (q + d.normalized() * sleeve_flare * k)
    for p in g.data.polygons:
        p.use_smooth = True
    return g


def tamoto(body, L, side, drop, width=0.2, depth=0.022):
    """袂：腕を下ろした時、体の横に下がる広い板状の袋。
    前の縁が腕（肩→手首）に沿い、後ろへ width だけ広がり、手首より drop だけ下まで垂れる。"""
    sh, wr = L["upperarm_" + side], L["hand_" + side]
    sx = 1.0 if side == "l" else -1.0
    out = Vector((sx, 0, 0))
    back = Vector((0, 1, 0))
    top = sh + (wr - sh) * 0.12 + out * 0.035
    bot = sh + (wr - sh) * 0.92 + out * 0.035
    bot = bot + Vector((0, 0, -drop))
    nu, nv = 10, 12   # u: 前→後ろ、v: 上→下
    verts = []
    for layer in (-1, 1):
        for i in range(nv + 1):
            v = i / nv
            c = top + (bot - top) * v
            for j in range(nu + 1):
                u = j / nu
                # 下の後ろ角は丸く
                round_ = (max(0.0, v - 0.75) / 0.25) ** 2 * (u ** 2) * 0.06
                p = c + back * (width * u) + Vector((0, 0, round_)) + out * (layer * depth * (0.3 + 0.7 * math.sin(math.pi * min(u, 1.0) ** 0.5)))
                verts.append(p)
    def idx(l, i, j):
        return l * (nv + 1) * (nu + 1) + i * (nu + 1) + j
    faces = []
    for l in (0, 1):
        for i in range(nv):
            for j in range(nu):
                a, b, c2, d = idx(l, i, j), idx(l, i + 1, j), idx(l, i + 1, j + 1), idx(l, i, j + 1)
                faces.append((a, b, c2, d) if l == 1 else (a, d, c2, b))
    # 縫い目：下辺と後ろの辺を閉じる（前は袖口、上は肩につながる）
    for j in range(nu):
        faces.append((idx(0, nv, j), idx(0, nv, j + 1), idx(1, nv, j + 1), idx(1, nv, j)))
    for i in range(nv):
        faces.append((idx(0, i, nu), idx(0, i + 1, nu), idx(1, i + 1, nu), idx(1, i, nu)))
    me = bpy.data.meshes.new("tamoto_" + side)
    me.from_pydata([tuple(p) for p in verts], [], faces)
    me.update()
    o = bpy.data.objects.new("tamoto_" + side, me)
    bpy.context.collection.objects.link(o)
    for p in me.polygons:
        p.use_smooth = True
    me.uv_layers.new(name="UVMap")
    # 腕に沿う前の縁と上の縁（肩付け）を固定
    vg = o.vertex_groups.new(name="pin")
    pins = [idx(l, i, 0) for l in (0, 1) for i in range(nv + 1)] + [idx(l, 0, j) for l in (0, 1) for j in range(nu + 1)]
    vg.add(pins, 1.0, "REPLACE")
    return o


def collar(kosode, L, width=0.034, han_w=0.012):
    """衿：首の後ろから両肩を通り、前で交差して帯の下へ。右前（着る人の左身頃が上）。"""
    neck = L["neck_01"]
    waist_z = L["spine_01"].z
    bvh = BVHTree.FromObject(kosode, bpy.context.evaluated_depsgraph_get())
    mw = kosode.matrix_world
    mwi = mw.inverted()

    def on_surface(p):
        if p.y < neck.y - 0.1:
            # 前身頃：正面から体へ向けて光線を飛ばす（最寄り点だと胸の中央に寄ってしまう）
            o_ = mwi @ p
            d_ = (mwi.to_3x3() @ Vector((0, 1, 0))).normalized()
            loc, nrm, _, _ = bvh.ray_cast(o_, d_)
            if loc is not None:
                return mw @ loc, (mw.to_3x3() @ nrm).normalized()
        loc, nrm, _, _ = bvh.find_nearest(mwi @ p)
        return mw @ loc, (mw.to_3x3() @ nrm).normalized()

    def path(sign, n=40, cross=True):
        # sign=+1: 着る人の左（+X）の衿＝上前。首の後ろ→左の首筋→前で右下へ
        pts = []
        for i in range(n + 1):
            t = i / n
            if t < 0.3:      # 後ろ衿から首の横へ（首の周りを回る）
                a = math.pi * 0.5 + (t / 0.3) * math.pi * 0.5  # 背中側(+Y)から横(±X)へ
                r = 0.065
                p = Vector((neck.x + sign * math.sin(a - math.pi * 0.5) * r * 1.0 + sign * 0.0,
                            neck.y + math.cos(a - math.pi * 0.5) * r * 0.9 + 0.01, neck.z - 0.025 - t * 0.04))
                p = Vector((neck.x + sign * r * math.sin((t / 0.3) * math.pi * 0.5),
                            neck.y + r * 0.9 * math.cos((t / 0.3) * math.pi * 0.5) + 0.005,
                            neck.z - 0.02 - (t / 0.3) * 0.03))
            else:            # 首の横から前へ下り、反対側の脇腹へ交差
                u = (t - 0.3) / 0.7
                x0 = neck.x + sign * 0.065
                x1 = neck.x - sign * (0.09 if cross else -0.0)
                z0 = neck.z - 0.05
                z1 = waist_z - 0.02
                x = x0 + (x1 - x0) * (u ** 1.15)
                z = z0 + (z1 - z0) * u
                p = Vector((x, neck.y - 0.2, z))
            pts.append(p)
        return pts

    def ribbon(name, pts, w, lift, inner_side):
        rows = []
        sp = []
        for p in pts:
            q, nrm = on_surface(p)
            sp.append((q + nrm * lift, nrm))
        for i, (q, nrm) in enumerate(sp):
            a = sp[max(0, i - 1)][0]
            b = sp[min(len(sp) - 1, i + 1)][0]
            tan = (b - a).normalized()
            side = nrm.cross(tan).normalized()
            if side.dot(inner_side(q)) < 0:
                side = -side
            rows.append([q, q + side * w])
        o = K.rings_to_mesh(name, rows, closed=False)
        return o

    def toward_neck(q):
        d = Vector((neck.x - q.x, 0.0, neck.z + 0.2 - q.z))
        return d.normalized()

    objs = []
    # 下前（着る人の右の衿）を先に、少しだけ低く
    objs.append(ribbon("eri_under", path(-1.0), width, 0.003, toward_neck))
    objs.append(ribbon("eri_top", path(1.0), width, 0.006, toward_neck))
    # 半衿（白）：衿の内側（首側）に細く見える
    han = []
    han.append(ribbon("haneri_u", path(-1.0, cross=True)[:24], han_w, 0.0045, lambda q: -toward_neck(q)))
    han.append(ribbon("haneri_t", path(1.0)[:24], han_w, 0.0075, lambda q: -toward_neck(q)))
    return objs, han


_TORSO = {}


def tsection(body, z, band=0.02):
    """胴と脚だけ（腕・手を除く）の断面：中心と半径。"""
    key = id(body)
    if key not in _TORSO:
        W = _weights(body)
        mw = body.matrix_world
        pts = []
        for v, w in zip(body.data.vertices, W):
            if sum(x for n, x in w.items() if any(k in n for k in ARM_KEYS)) < 0.3:
                pts.append(mw @ v.co)
        _TORSO[key] = pts
    pts = [q for q in _TORSO[key] if abs(q.z - z) < band]
    if not pts:
        return Vector((0, 0, z)), 0.12, 0.09
    cx = sum(q.x for q in pts) / len(pts)
    cy = sum(q.y for q in pts) / len(pts)
    return Vector((cx, cy, z)), max(abs(q.x - cx) for q in pts), max(abs(q.y - cy) for q in pts)


ARM_KEYS = ("UpperArm", "LowerArm", "Hand", "Thumb", "Index", "Middle", "Ring", "Little", "Shoulder")


def strip_arm_weights(o):
    """腕・手・指の骨の影響を外す（袴や帯が手の動きに引っ張られないように）。"""
    arm_groups = {vg.index for vg in o.vertex_groups if any(k in vg.name for k in ARM_KEYS)}
    hips = o.vertex_groups.get(K.bn("pelvis"))
    spine = o.vertex_groups.get(K.bn("spine_01"))
    for v in o.data.vertices:
        rest = 0.0
        for g in list(v.groups):
            if g.group in arm_groups:
                o.vertex_groups[g.group].remove([v.index])
            else:
                rest += g.weight
        if rest < 1e-4:
            (spine or hips).add([v.index], 1.0, "REPLACE")


def hakama(body, L, n=72):
    """袴：腰から足首へ、前後に深いひだ。寸法は体の断面から（アニメ体型でも大きくなりすぎない）。"""
    waist = L["spine_01"].z - 0.02
    ank = L["floor"] + 0.05
    c0, rx0, ry0 = tsection(body, waist)
    hc, hrx, hry = tsection(body, L["pelvis"].z - 0.05)
    rings = []
    steps = 18
    for i in range(steps + 1):
        t = i / steps
        z = waist + (ank - waist) * t
        # 腰はぴったり、腰骨の下から広がり、裾は肩幅ほどに
        k = t * t * (3 - 2 * t) * 0.6 + t * 0.4
        rx = max(rx0, hrx) + 0.03 + 0.09 * k
        ry = max(ry0, hry) + 0.035 + 0.07 * k
        def wob(a, t=t):
            # 前に 5 本・後ろに 2 本のひだ（前：-Y 側）
            front = max(0.0, -math.sin(a))
            return (0.03 + 0.05 * t) * (front * abs(math.sin(a * 5)) ** 0.6 * 1.0 + (1 - front) * 0.3 * abs(math.sin(a * 2)))
        rings.append(K.ellipse(Vector((c0.x, c0.y, z)), rx, ry, n, wob))
    o = K.rings_to_mesh("hakama", rings)
    K.pin_group(o, lambda q: q.z > waist - 0.12)
    # 前紐（腰の前で交差して結ぶ帯）
    straps = []
    for k, dz in enumerate((0.0, -0.035)):
        r = [K.ellipse(Vector((c0.x, c0.y, waist + dz + 0.012)), rx0 + 0.035, ry0 + 0.04, 48),
             K.ellipse(Vector((c0.x, c0.y, waist + dz - 0.012)), rx0 + 0.035, ry0 + 0.04, 48)]
        straps.append(K.rings_to_mesh("hakama_himo%d" % k, r))
    return o, straps


def robe_skirt(body, L, n=56):
    """女性の着物の裾：腰から足首へ、裾すぼまりの筒。"""
    top = L["spine_01"].z - 0.04
    bottom = L["floor"] + 0.02
    c0, rx0, ry0 = tsection(body, top)
    hc, hrx, hry = tsection(body, L["pelvis"].z - 0.06)
    rings = []
    steps = 18
    for i in range(steps + 1):
        t = i / steps
        z = top + (bottom - top) * t
        bulge = math.sin(min(1.0, t / 0.35) * math.pi * 0.5)
        rx = (rx0 + 0.02) + (hrx + 0.03 - rx0 - 0.02) * bulge - 0.03 * max(0.0, t - 0.4)
        ry = (ry0 + 0.03) + (hry + 0.04 - ry0 - 0.03) * bulge - 0.02 * max(0.0, t - 0.4)
        rings.append(K.ellipse(Vector((c0.x, c0.y, z)), rx, ry, n))
    o = K.rings_to_mesh("robe_skirt", rings)
    K.pin_group(o, lambda q: q.z > top - 0.1)
    return o


def make(body_p, L, female, rest_body):
    K.SECTION_HOOK = tsection
    hip_z = L["pelvis"].z
    waist_z = L["spine_01"].z
    neck_z = L["neck_01"].z
    K.body_for_wasou(rest_body, "w", L)
    # 小袖：男は腰下まで（袴の中へ）、女は膝上まで（下は裾の筒が受け持つ）
    ks = shell(body_p, L, "kosode", neck_z + 0.03, hip_z - (0.06 if not female else 0.1), 0.012)
    tl = tamoto(body_p, L, "l", 0.22 if female else 0.08, 0.24 if female else 0.2)
    tr = tamoto(body_p, L, "r", 0.22 if female else 0.08, 0.24 if female else 0.2)
    hk_main, himo = hakama(body_p, L)
    hk = [hk_main]
    rb = robe_skirt(body_p, L)
    K.drape([tl, tr, hk_main, rb], body_p, frames=40, stiff=14.0, bend=0.8)
    K.transfer_weights(ks, body_p, 0.0, L)
    for t, s in ((tl, "l"), (tr, "r")):
        K.arm_weights(t, L, s)
    K.transfer_weights(rb, body_p, 0.7, L)
    strip_arm_weights(rb)
    for h in hk + himo:
        K.wrap_onto(h, body_p, 0.0) if False else None
        K.transfer_weights(h, body_p, 0.25, L)
        strip_arm_weights(h)
    hk = hk + himo
    er, han = collar(ks, L)
    for e in er + han:
        K.transfer_weights(e, body_p, 0.0, L)
    ob = K.obi(body_p, L, 0.2 if female else 0.06, female)
    K.wrap_onto(ob[0], ks, 0.012)
    for x in ob:
        K.transfer_weights(x, body_p, 0.0, L)
        strip_arm_weights(x)
    # 甲冑は別途作り直す（ここでは作らない）
    groups = {"kosode": [ks, tl, tr], "eri": er, "haneri": han, "hakama": hk, "robe": [rb], "obi": ob}
    out = {}
    for key, objs in groups.items():
        j = K.join(objs, "w_garment_%s" % key)
        K.material(j, key)
        mods = [m for m in j.modifiers if m.type == "ARMATURE"]
        for m in mods[1:]:
            j.modifiers.remove(m)
        # 模様を貼る UV（実寸に近いスケールで展開）
        bpy.context.view_layer.objects.active = j
        for o2 in bpy.context.selected_objects:
            o2.select_set(False)
        j.select_set(True)
        if not j.data.uv_layers:
            j.data.uv_layers.new(name="UVMap")
        with bpy.context.temp_override(object=j, active_object=j, selected_objects=[j], selected_editable_objects=[j]):
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01, scale_to_bounds=False)
            bpy.ops.object.mode_set(mode="OBJECT")
        out[key] = j
    return out
