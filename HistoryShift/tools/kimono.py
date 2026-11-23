"""和装を「布」として作り、Blender の布シミュレーションで体に着せる（make_humans.py から呼ぶ）。

体の延長ではなく、型紙のように独立した布（身頃・袂・衿・袴・裾・帯・胴）を体の周りに作り、
衝突判定つきで重力で落として本物のしわ・たるみを作る。最後に骨格のウェイトを付けて一緒に動くようにする。
"""
import math

import bmesh
import bpy
from mathutils import Vector


# ---------------------------------------------------------------- 体の寸法
def landmarks(body):
    arm = body.find_armature()
    mw = arm.matrix_world
    b = arm.data.bones

    def p(n, tail=False):
        bone = b[n]
        return mw @ (bone.tail_local if tail else bone.head_local)

    L = {k: p(k) for k in ("pelvis", "spine_01", "spine_03", "neck_01", "head", "upperarm_l", "upperarm_r",
                           "lowerarm_l", "lowerarm_r", "hand_l", "hand_r", "thigh_l", "thigh_r",
                           "calf_l", "calf_r", "foot_l", "foot_r")}
    zs = [ (body.matrix_world @ v.co).z for v in body.data.vertices]
    L["floor"] = min(zs)
    L["arm"] = arm
    return L


def section(body, z, band=0.025):
    """高さ z での体の断面の中心と半径（x, y）。"""
    pts = [body.matrix_world @ v.co for v in body.data.vertices if abs((body.matrix_world @ v.co).z - z) < band]
    pts = [q for q in pts if abs(q.x) < 0.25]  # 腕を除く
    if not pts:
        return Vector((0, 0, z)), 0.15, 0.11
    cx = sum(q.x for q in pts) / len(pts)
    cy = sum(q.y for q in pts) / len(pts)
    rx = max(abs(q.x - cx) for q in pts)
    ry = max(abs(q.y - cy) for q in pts)
    return Vector((cx, cy, z)), rx, ry


# ---------------------------------------------------------------- メッシュ生成
def rings_to_mesh(name, rings, closed=True, cap_top=False):
    verts, faces = [], []
    n = len(rings[0])
    for r in rings:
        verts.extend(r)
    for i in range(len(rings) - 1):
        for j in range(n if closed else n - 1):
            a, b2 = i * n + j, i * n + (j + 1) % n
            faces.append((a, a + n, b2 + n, b2))   # 法線が外向きになる向き
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    for poly in me.polygons:
        poly.use_smooth = True
    return o


def ellipse(c, rx, ry, n, wobble=None):
    out = []
    for i in range(n):
        a = 2 * math.pi * i / n
        k = 1.0 + (wobble(a) if wobble else 0.0)
        out.append(Vector((c.x + math.cos(a) * rx * k, c.y + math.sin(a) * ry * k, c.z)))
    return out


def pin_group(o, pred, name="pin"):
    vg = o.vertex_groups.new(name=name)
    idx = [v.index for v in o.data.vertices if pred(o.matrix_world @ v.co)]
    vg.add(idx, 1.0, "REPLACE")
    return vg


# ---------------------------------------------------------------- 布シミュレーション
def drape(objs, body, frames=36, stiff=12.0, bend=0.6, mass=0.25):
    col = body.modifiers.get("Collision") or body.modifiers.new("Collision", "COLLISION")
    body.collision.thickness_outer = 0.006
    body.collision.cloth_friction = 5.0
    for o in objs:
        m = o.modifiers.new("Cloth", "CLOTH")
        s = m.settings
        s.quality = 6
        s.mass = mass
        s.tension_stiffness = stiff
        s.compression_stiffness = stiff
        s.shear_stiffness = stiff * 0.5
        s.bending_stiffness = bend
        s.air_damping = 2.0
        if "pin" in o.vertex_groups:
            s.vertex_group_mass = "pin"
        m.collision_settings.collision_quality = 3
        m.collision_settings.distance_min = 0.006
        m.point_cache.frame_start = 1
        m.point_cache.frame_end = frames
    scene = bpy.context.scene
    for f in range(1, frames + 1):
        scene.frame_set(f)
    for o in objs:
        bpy.context.view_layer.objects.active = o
        with bpy.context.temp_override(object=o, active_object=o):
            bpy.ops.object.modifier_apply(modifier="Cloth")
    body.modifiers.remove(col)
    scene.frame_set(1)


# ---------------------------------------------------------------- ウェイト
def transfer_weights(o, body, pelvis_mix=0.0, L=None):
    for vg in body.vertex_groups:
        if vg.name not in o.vertex_groups:
            o.vertex_groups.new(name=vg.name)
    dt = o.modifiers.new("wt", "DATA_TRANSFER")
    dt.object = body
    dt.use_vert_data = True
    dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "POLYINTERP_NEAREST"
    dt.layers_vgroup_select_src = "ALL"
    dt.layers_vgroup_select_dst = "NAME"
    bpy.context.view_layer.objects.active = o
    with bpy.context.temp_override(object=o, active_object=o):
        bpy.ops.object.modifier_apply(modifier="wt")
    if pelvis_mix > 0.0 and "pelvis" in o.vertex_groups and L is not None:
        # 裾は脚に引っ張られすぎないよう、腰の骨へ寄せる
        pv = o.vertex_groups["pelvis"]
        legs = [o.vertex_groups[n] for n in ("thigh_l", "thigh_r", "calf_l", "calf_r") if n in o.vertex_groups]
        hz, fz = L["pelvis"].z, L["floor"]
        for v in o.data.vertices:
            t = max(0.0, min(1.0, (hz - (o.matrix_world @ v.co).z) / max(hz - fz, 0.01)))
            k = pelvis_mix * (0.4 + 0.6 * t)
            for g in v.groups:
                vg = o.vertex_groups[g.group]
                if vg in legs:
                    vg.add([v.index], g.weight * (1 - k), "REPLACE")
            pv.add([v.index], k, "ADD")
    for vg in list(o.vertex_groups):
        if vg.name == "pin":
            o.vertex_groups.remove(vg)
    am = o.modifiers.new("Armature", "ARMATURE")
    am.object = L["arm"] if L else body.find_armature()


def arm_weights(o, L, side):
    """袖：腕の線に沿って上腕・前腕のウェイトを付ける（体の近くの別の骨に吸われないように）。"""
    for vg in list(o.vertex_groups):
        o.vertex_groups.remove(vg)
    up = o.vertex_groups.new(name="upperarm_" + side)
    lo = o.vertex_groups.new(name="lowerarm_" + side)
    sh, el, wr = L["upperarm_" + side], L["lowerarm_" + side], L["hand_" + side]
    axis = (wr - sh)
    ln = axis.length
    for v in o.data.vertices:
        q = o.matrix_world @ v.co
        t = max(0.0, min(1.0, (q - sh).dot(axis) / (ln * ln)))
        te = (el - sh).length / ln
        w_lo = max(0.0, min(1.0, (t - te + 0.12) / 0.24))
        up.add([v.index], 1.0 - w_lo, "REPLACE")
        lo.add([v.index], w_lo, "REPLACE")
    am = o.modifiers.new("Armature", "ARMATURE")
    am.object = L["arm"]


def material(o, key):
    m = bpy.data.materials.new("garment_" + key)
    m.use_nodes = True
    o.data.materials.clear()
    o.data.materials.append(m)


# ---------------------------------------------------------------- 各パーツ
def kosode_body(body, L, length_z, n=56):
    """身頃：首から裾まで。肩は首へ向かって絞り、前は右前に重ねて V 衿を開ける。"""
    rings = []
    neck = L["neck_01"]
    sh_z = (L["upperarm_l"].z + L["upperarm_r"].z) / 2
    shoulder_w = abs(L["upperarm_l"].x - L["upperarm_r"].x) / 2 + 0.03
    zs = []
    z = neck.z - 0.01
    while z > length_z:
        zs.append(z)
        z -= 0.02 if z > sh_z - 0.08 else 0.045
    zs.append(length_z)
    for z in zs:
        if z > sh_z:
            t = (z - sh_z) / max(neck.z - sh_z, 0.01)
            c, rx, ry = section(body, sh_z - 0.05)
            k = t ** 2.2
            rx = shoulder_w * (1 - k) + 0.085 * k
            ry = (ry + 0.035) * (1 - k * 0.45)
            c = Vector((neck.x, c.y, z))
        else:
            c, rx, ry = section(body, max(z, L["thigh_l"].z - 0.05))
            rx = max(rx + 0.035, 0.16)
            ry = max(ry + 0.04, 0.12)
            c.z = z
        rings.append(ellipse(c, rx, ry, n))
    o = rings_to_mesh("kosode_body", rings)
    # V 衿（右前：着る人から見て左の身頃が上）
    bm = bmesh.new()
    bm.from_mesh(o.data)
    cut = []  # 衿は上から帯状の半衿を重ねる（切り抜くとギザギザになるため）
    bmesh.ops.delete(bm, geom=cut, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    pin_group(o, lambda q: q.z > sh_z - 0.12)
    return o


def sleeve(L, side, drop, n_len=10, n_w=8):
    """袖（袂）：腕の線を上辺に、下へ垂れる袋状の布。"""
    sh, wr = L["upperarm_" + side], L["hand_" + side]
    start = sh + (wr - sh) * -0.08
    end = sh + (wr - sh) * 0.9
    axis = (end - start).normalized()
    down = Vector((0, 0, -1))
    side_v = axis.cross(down).normalized()
    depth = 0.055
    verts, faces = [], []
    # 筒（腕の周り）＋袋（下へ垂れる）を、断面の多角形で作る
    prof = []
    for i in range(n_w):
        a = 2 * math.pi * i / n_w
        prof.append((math.cos(a) * depth, math.sin(a) * 0.06))
    rows = []
    for i in range(n_len + 1):
        t = i / n_len
        c = start + (end - start) * t
        row = []
        for (u, w) in prof:
            hang = max(0.0, -w) / 0.06 * drop          # 下側だけ大きく垂らす
            p = c + side_v * u + down * (w if w > 0 else -w * 0.0) + down * hang + Vector((0, 0, max(0.0, w)))
            row.append(p)
        rows.append(row)
    o = rings_to_mesh("sleeve_" + side, rows)
    pin_group(o, lambda q: (q - (start + axis * (q - start).dot(axis))).length < 0.075 and q.z >= (start + axis * (q - start).dot(axis)).z - 0.02)
    return o


def hakama(body, L, pleats=True, n=64):
    """袴：腰から足首へ広がる一枚の筒。前後に深いひだ（行灯袴風の見た目）。"""
    waist = L["pelvis"].z + 0.13
    ank = L["floor"] + 0.06
    c0, rx0, ry0 = section(body, waist)
    rx0 += 0.03
    ry0 += 0.03
    knee = L["calf_l"]
    leg_span = abs(L["foot_l"].x - L["foot_r"].x) / 2 + 0.16
    rings = []
    steps = 16
    for i in range(steps + 1):
        t = i / steps
        z = waist + (ank - waist) * t
        rx = (rx0 + 0.05) * (1 - t) + leg_span * t
        ry = (ry0 + 0.06) * (1 - t) + 0.2 * t
        wob = (lambda a, t=t: (0.07 + 0.05 * t) * math.sin(a * 12)) if pleats else None
        rings.append(ellipse(Vector((c0.x, c0.y, z)), rx, ry, n, wob))
    o = rings_to_mesh("hakama", rings)
    pin_group(o, lambda q: q.z > waist - 0.06)
    return [o]


def robe_skirt(body, L, n=48):
    """着物の裾：腰から足首まで、ほぼ真っ直ぐ落ちる筒（裾すぼまり）。"""
    top = L["pelvis"].z + 0.05
    bottom = L["floor"] + 0.03
    c0, rx0, ry0 = section(body, top)
    rings = []
    steps = 16
    for i in range(steps + 1):
        t = i / steps
        z = top + (bottom - top) * t
        span = abs(L["foot_l"].x - L["foot_r"].x) / 2 + 0.1
        rx = max((rx0 + 0.05) * (1.0 + 0.12 * math.sin(t * math.pi * 0.8)), span * (0.85 if t > 0.08 else 0.6))
        ry = (ry0 + 0.06) * (1.0 + 0.15 * math.sin(t * math.pi * 0.8))
        rings.append(ellipse(Vector((c0.x, c0.y, z)), rx, ry, n))
    o = rings_to_mesh("robe_skirt", rings)
    pin_group(o, lambda q: q.z > top - 0.05)
    return o


def obi(body, L, width, knot, n=40):
    z = L["spine_01"].z + 0.02
    c, rx, ry = section(body, z)
    rings = [ellipse(Vector((c.x, c.y, z + width / 2)), rx + 0.05, ry + 0.055, n),
             ellipse(Vector((c.x, c.y, z - width / 2)), rx + 0.05, ry + 0.055, n)]
    o = rings_to_mesh("obi", rings)
    objs = [o]
    if knot:
        bpy.ops.mesh.primitive_cube_add(size=1)
        k = bpy.context.object
        k.name = "obi_knot"
        k.scale = (0.3, 0.07, 0.22)
        k.location = (c.x, c.y + ry + 0.1, z + 0.02)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bev = k.modifiers.new("bev", "BEVEL"); bev.width = 0.025; bev.segments = 3
        bpy.ops.object.modifier_apply(modifier="bev")
        bpy.ops.object.shade_smooth()
        objs.append(k)
    return objs


def collar(body, L):
    """衿：V に沿った帯（白い半衿を見せる）。"""
    neck = L["neck_01"]
    pts = []
    for i in range(14):
        t = i / 13
        # 右前：左身頃の衿が上に重なる
        x = neck.x + (0.075 - 0.09 * t)
        z = neck.z + 0.015 - 0.2 * t
        y = neck.y - 0.075 - 0.075 * math.sin(t * math.pi * 0.6)
        pts.append(Vector((x, y, z)))
    rows = [[p + Vector((0, -0.004, 0)), p + Vector((0.04, -0.004, 0))] for p in pts]
    o = rings_to_mesh("eri", rows, closed=False)
    mirror = []
    for p in pts:
        mirror.append(Vector((2 * neck.x - p.x, p.y + 0.004, p.z)))
    rows2 = [[p, p + Vector((-0.04, 0.0, 0))] for p in mirror]
    o2 = rings_to_mesh("eri2", rows2, closed=False)
    return [o, o2]


def armor(body, L):
    """胴丸と草摺（漆塗りの小札を重ねた板）。"""
    objs = []
    top = L["spine_03"].z + 0.05
    bot = L["pelvis"].z + 0.02
    rings = []
    for i in range(7):
        t = i / 6
        z = top + (bot - top) * t
        c, rx, ry = section(body, z)
        rings.append(ellipse(Vector((c.x, c.y, z)), rx + 0.06, ry + 0.065, 32))
    o = rings_to_mesh("do", rings)
    objs.append(o)
    # 草摺：腰から下がる板 6 枚
    c, rx, ry = section(body, bot)
    for i in range(6):
        a = math.pi * (0.15 + i / 6 * 2)
        bpy.ops.mesh.primitive_cube_add(size=1)
        k = bpy.context.object
        k.name = "kusazuri_%d" % i
        k.scale = (0.17, 0.018, 0.22)
        k.location = (c.x + math.cos(a) * (rx + 0.08), c.y + math.sin(a) * (ry + 0.08), bot - 0.12)
        k.rotation_euler = (math.radians(8) * math.sin(a), 0, a + math.pi / 2)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        objs.append(k)
    return objs


def wrap_onto(o, target, offset):
    """布の表面に貼り付ける（衿・帯が布に埋もれないように）。"""
    sw = o.modifiers.new("wrap", "SHRINKWRAP")
    sw.target = target
    sw.wrap_method = "NEAREST_SURFACEPOINT"
    sw.wrap_mode = "OUTSIDE_SURFACE"
    sw.offset = offset
    bpy.context.view_layer.objects.active = o
    with bpy.context.temp_override(object=o, active_object=o):
        bpy.ops.object.modifier_apply(modifier="wrap")


def join(objs, name):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    j = bpy.context.object
    j.name = name
    return j


def body_for_wasou(body, variant, L):
    """和装用の体：服に隠れる胴・上腕・脚を消した複製（突き抜け防止。首元の V と前腕・足首は残す）。"""
    g = body.copy()
    g.data = body.data.copy()
    g.name = "%s_bodyw" % variant
    bpy.context.collection.objects.link(g)
    idx = {vg.name: vg.index for vg in g.vertex_groups}
    hide = [idx[n] for n in ("pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "upperarm_l",
                             "upperarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r") if n in idx]
    neck = L["neck_01"]
    ankle = L["floor"] + 0.16
    bm = bmesh.new()
    bm.from_mesh(g.data)
    deform = bm.verts.layers.deform.active
    kill = []
    for v in bm.verts:
        w = sum(v[deform].get(i, 0.0) for i in hide) if deform else 0.0
        q = g.matrix_world @ v.co
        keep_v = q.z > neck.z - 0.16 and abs(q.x - neck.x) < 0.11 and q.y < neck.y + 0.05   # 衿元
        if w > 0.55 and not keep_v and q.z > ankle:
            kill.append(v)
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(g.data)
    bm.free()
    return g


# ---------------------------------------------------------------- まとめ
def make_wasou(body, variant, female):
    L = landmarks(body)
    body_for_wasou(body, variant, L)
    knee_z = L["calf_l"].z
    hip_z = L["pelvis"].z
    # 小袖（男：腰丈で袴に入れる / 女：裾まで）
    kb = kosode_body(body, L, hip_z + 0.05 if not female else hip_z - 0.02)
    sl = sleeve(L, "l", 0.36 if female else 0.24)
    sr = sleeve(L, "r", 0.36 if female else 0.24)
    hk = hakama(body, L)
    rb = robe_skirt(body, L)
    drape([kb, sl, sr] + hk + [rb], body, stiff=10.0, bend=0.4)
    out = {}
    transfer_weights(kb, body, 0.0, L)
    arm_weights(sl, L, "l")
    arm_weights(sr, L, "r")
    transfer_weights(rb, body, 0.7, L)
    for h in hk:
        transfer_weights(h, body, 0.25, L)
    # 衿・帯・胴は布シミュなし（形が決まったもの）
    er = collar(body, L)
    for e in er:
        wrap_onto(e, kb, 0.004)
        transfer_weights(e, body, 0.0, L)
    ob = obi(body, L, 0.24 if female else 0.07, female)
    wrap_onto(ob[0], kb, 0.014)
    for x in ob:
        transfer_weights(x, body, 0.0, L)
    ar = armor(body, L)
    for x in ar:
        transfer_weights(x, body, 0.3, L)
    groups = {"kosode": [kb, sl, sr], "eri": er, "hakama": hk, "robe": [rb], "obi": ob, "armor": ar}
    for key, objs in groups.items():
        j = join(objs, "%s_garment_%s" % (variant, key))
        material(j, key)
        # 結合でモディファイアが重複しないように 1 つに
        mods = [m for m in j.modifiers if m.type == "ARMATURE"]
        for m in mods[1:]:
            j.modifiers.remove(m)
        out[key] = j
    return out
