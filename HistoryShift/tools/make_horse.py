"""リアル寄りの馬を Blender（bpy）でヘッドレス生成し、骨格・歩様アニメーション付き glb に書き出す。

メタボールで有機的な体型を作り → メッシュ化・平滑化 → アーマチュアに自動ウェイトで結合 →
idle / walk / gallop を手続きキーフレームで作成。
使い方: python make_horse.py <出力.glb>
"""
import math
import sys

import bpy
from mathutils import Vector


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# 骨格（Blender: -Y が前、Z が上。最後に glTF で Y-up・-Z 前方に変換される）
BONES = {
    # name: (head, tail, parent)
    "root": ((0, 0, 0), (0, 0, 0.3), None),
    "spine": ((0, 0.75, 1.35), (0, 0.05, 1.42), "root"),
    "chest": ((0, 0.05, 1.42), (0, -0.6, 1.45), "spine"),
    "neck": ((0, -0.62, 1.5), (0, -0.95, 1.95), "chest"),
    "head": ((0, -0.95, 1.95), (0, -1.38, 1.62), "neck"),
    "tail": ((0, 0.95, 1.42), (0, 1.08, 0.75), "spine"),
}
LEGS = {
    # name: (x, 肩/腰の位置, 膝/飛節, 蹄)
    "fl": (-0.19, (-0.52, 1.15), (-0.5, 0.6), (-0.5, 0.1)),
    "fr": (0.19, (-0.52, 1.15), (-0.5, 0.6), (-0.5, 0.1)),
    "bl": (-0.2, (0.6, 1.2), (0.78, 0.55), (0.74, 0.1)),
    "br": (0.2, (0.6, 1.2), (0.78, 0.55), (0.74, 0.1)),
}
for k, (x, top, knee, foot) in LEGS.items():
    front = k.startswith("f")
    BONES["leg_up_" + k] = ((x, top[0], top[1]), (x, knee[0], knee[1]), "chest" if front else "spine")
    BONES["leg_lo_" + k] = ((x, knee[0], knee[1]), (x, foot[0], foot[1]), "leg_up_" + k)
    BONES["hoof_" + k] = ((x, foot[0], foot[1]), (x, foot[0] - 0.06, 0.0), "leg_lo_" + k)


def make_armature():
    bpy.ops.object.armature_add(enter_editmode=True)
    arm = bpy.context.object
    arm.name = "HorseRig"
    eb = arm.data.edit_bones
    eb.remove(eb[0])
    for name, (h, t, p) in BONES.items():
        b = eb.new(name)
        b.head = Vector(h)
        b.tail = Vector(t)
    for name, (h, t, p) in BONES.items():
        if p:
            eb[name].parent = eb[p]
            eb[name].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def ball(mb, co, r, s=(1, 1, 1), stiff=2.0):
    e = mb.elements.new(type="ELLIPSOID")
    e.co = Vector(co)
    e.radius = r
    e.size_x, e.size_y, e.size_z = s
    e.stiffness = stiff
    return e


def make_body():
    mbd = bpy.data.metaballs.new("HorseMB")
    mbd.resolution = 0.035
    mbd.render_resolution = 0.035
    obj = bpy.data.objects.new("HorseMBObj", mbd)
    bpy.context.collection.objects.link(obj)
    # 胴（樽型）・胸・尻：深く丸い胴
    for i in range(10):
        t = i / 9.0
        y = -0.5 + t * 1.15
        r = 0.4 + 0.06 * math.sin(t * math.pi)
        ball(mbd, (0, y, 1.27 + 0.03 * math.sin(t * math.pi)), r, (0.82, 1.0, 1.05))
    ball(mbd, (0, -0.6, 1.25), 0.4, (0.85, 0.9, 1.1))      # 胸
    ball(mbd, (0, -0.68, 1.05), 0.26, (0.8, 0.8, 1.0))     # 胸前
    ball(mbd, (0, 0.7, 1.33), 0.42, (0.9, 0.95, 1.0))      # 尻
    ball(mbd, (0, 0.78, 1.12), 0.32, (0.85, 0.9, 1.0))
    ball(mbd, (0, -0.3, 1.62), 0.18, (0.6, 1.4, 0.6))      # き甲
    # 首（付け根は太く、上に向かって細く）
    for i in range(9):
        t = i / 8.0
        p = Vector((0, -0.6, 1.42)).lerp(Vector((0, -0.92, 1.98)), t)
        ball(mbd, p + Vector((0, 0.04 * math.sin(t * math.pi), 0)), 0.34 - 0.18 * t, (0.62, 1.05, 1.2))
    # 頭（くさび形：額は広く鼻先へ細く、横は平ら）
    for i in range(8):
        t = i / 7.0
        p = Vector((0, -0.94, 2.02)).lerp(Vector((0, -1.32, 1.58)), t)
        ball(mbd, p, 0.2 - 0.075 * t, (0.62, 1.0, 1.12))
    ball(mbd, (0, -1.36, 1.55), 0.12, (0.78, 1.0, 0.95))    # 鼻先
    ball(mbd, (0, -1.0, 1.92), 0.15, (0.95, 0.9, 0.9))      # 頬
    # 耳
    for x in (-0.07, 0.07):
        ball(mbd, (x, -0.9, 2.14), 0.06, (0.5, 0.6, 1.7), 3.0)
    # 脚
    for k, (x, top, knee, foot) in LEGS.items():
        front = k.startswith("f")
        a, b, c = Vector((x, top[0], top[1])), Vector((x, knee[0], knee[1])), Vector((x, foot[0], foot[1]))
        thick = 0.23 if not front else 0.2
        for i in range(12):  # 上腕・大腿（太い→細い）
            t = i / 11.0
            ball(mbd, a.lerp(b, t), thick - (thick - 0.09) * t, (0.8, 1, 1), 1.6)
        for i in range(14):  # 管
            t = i / 13.0
            ball(mbd, b.lerp(c, t), 0.085 - 0.015 * math.sin(t * math.pi) + (0.02 if t > 0.85 else 0), (0.8, 1, 1), 1.6)
        ball(mbd, (x, foot[0] - 0.02, 0.07), 0.1, (1, 1.2, 0.8), 1.8)   # 蹄
    # 尻尾（付け根）
    for i in range(4):
        t = i / 3.0
        ball(mbd, Vector((0, 0.9, 1.45)).lerp(Vector((0, 1.1, 1.2)), t), 0.07 - 0.02 * t)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    body = bpy.context.object
    body.name = "HorseBody"
    # 平滑化・軽量化
    mod = body.modifiers.new("smooth", "SMOOTH")
    mod.factor = 0.6
    mod.iterations = 4
    bpy.ops.object.modifier_apply(modifier="smooth")
    dec = body.modifiers.new("dec", "DECIMATE")
    dec.ratio = 0.35
    bpy.ops.object.modifier_apply(modifier="dec")
    bpy.ops.object.shade_smooth()
    return body


def make_hair(arm):
    """たてがみと尾（メタボールの房）。"""
    mbd = bpy.data.metaballs.new("HairMB")
    mbd.resolution = 0.03
    mbd.render_resolution = 0.03
    obj = bpy.data.objects.new("HairMBObj", mbd)
    bpy.context.collection.objects.link(obj)
    # 尾：付け根から垂れ下がり、中ほどで膨らみ、先が細い
    for i in range(16):
        t = i / 15.0
        p = Vector((0, 0.98 + 0.22 * t - 0.1 * t * t, 1.42 - 0.95 * t))
        r = 0.06 + 0.07 * math.sin(min(1.0, t * 1.3) * math.pi * 0.9)
        ball(mbd, p, r, (0.75, 0.9, 1.3), 2.0)
    # たてがみ：首の上縁に沿って薄く
    for i in range(12):
        t = i / 11.0
        p = Vector((0, -0.66, 1.66)).lerp(Vector((0, -0.92, 2.1)), t)
        ball(mbd, p + Vector((0, 0.06, 0.03)), 0.075, (0.35, 1.0, 1.0), 2.2)
    ball(mbd, (0, -1.02, 2.08), 0.07, (0.5, 1.2, 0.6), 2.2)  # 前髪
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    hair = bpy.context.object
    hair.name = "HorseHair"
    mod = hair.modifiers.new("smooth", "SMOOTH"); mod.factor = 0.5; mod.iterations = 3
    bpy.ops.object.modifier_apply(modifier="smooth")
    dec = hair.modifiers.new("dec", "DECIMATE"); dec.ratio = 0.4
    bpy.ops.object.modifier_apply(modifier="dec")
    bpy.ops.object.shade_smooth()
    return [hair]


def material(name, color, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    return m


def bind(arm, meshes):
    for o in meshes:
        o.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")


def key_cycle(arm, action_name, length, fn):
    act = bpy.data.actions.new(action_name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for f in range(0, length + 1, 2):
        ph = f / length * 2 * math.pi
        for bname, rot in fn(ph).items():
            pb = arm.pose.bones[bname]
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = rot
            pb.keyframe_insert("rotation_euler", frame=f)
        rp = fn(ph).get("_root_z")
    # NLA に積む（glTF で個別アニメーションとして書き出すため）
    track = arm.animation_data.nla_tracks.new()
    track.name = action_name
    track.strips.new(action_name, 0, act)
    arm.animation_data.action = None
    return act


def leg_pose(ph, amp_up, amp_lo, offsets):
    out = {}
    for k, off in offsets.items():
        s = math.sin(ph + off)
        out["leg_up_" + k] = (amp_up * s, 0, 0)
        front = k.startswith("f")
        lo = max(0.0, -math.cos(ph + off)) * amp_lo
        out["leg_lo_" + k] = ((-lo if front else lo), 0, 0)
        out["hoof_" + k] = (0, 0, 0)
    return out


def animations(arm):
    def idle(ph):
        d = {"neck": (0.05 * math.sin(ph), 0, 0), "head": (0.04 * math.sin(ph * 2), 0, 0), "tail": (0, 0, 0.15 * math.sin(ph))}
        d.update(leg_pose(ph, 0, 0, {"fl": 0, "fr": 0, "bl": 0, "br": 0}))
        return d

    def walk(ph):
        d = {"neck": (0.08 * math.sin(ph * 2), 0, 0), "head": (-0.05 * math.sin(ph * 2), 0, 0), "tail": (0, 0, 0.1 * math.sin(ph))}
        d.update(leg_pose(ph, 0.35, 0.6, {"fl": 0, "fr": math.pi, "bl": math.pi * 0.5, "br": math.pi * 1.5}))
        return d

    def gallop(ph):
        d = {"neck": (0.18 * math.sin(ph), 0, 0), "head": (-0.1 * math.sin(ph), 0, 0), "tail": (0.3 + 0.15 * math.sin(ph), 0, 0),
             "spine": (0.06 * math.sin(ph), 0, 0)}
        d.update(leg_pose(ph, 0.75, 1.1, {"fl": 0, "fr": 0.35, "bl": math.pi, "br": math.pi + 0.35}))
        return d

    key_cycle(arm, "Idle", 96, idle)
    key_cycle(arm, "Walk", 32, walk)
    key_cycle(arm, "Gallop", 16, gallop)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "horse.glb"
    clear()
    bpy.context.scene.render.fps = 24
    arm = make_armature()
    body = make_body()
    hair = make_hair(arm)
    body.data.materials.append(material("coat", (0.28, 0.16, 0.08), 0.55))
    for h in hair:
        h.data.materials.append(material("hair", (0.04, 0.03, 0.025), 0.7))
    bind(arm, [body] + hair)
    animations(arm)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_skins=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_yup=True)
    print("EXPORTED", out)


if __name__ == "__main__":
    main()
