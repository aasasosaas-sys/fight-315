"""VRoid（VRM）のアニメ素体に、布シミュレーションの和装を着せて書き出す（Blender bpy ヘッドレス）。

- VRM を glTF として読み込み、元の服（Tops/Bottoms/Shoes/Accessory）の面を体から取り除く
- kimono.py の型紙＋布シミュで小袖・袂・半衿・袴・裾・帯・胴を作り、体のウェイトを写す
- 服に隠れる体の部分を消した「和装用の体」も作る
- 人型の骨を Godot の人型プロファイル名（Hips, LeftUpperArm …）に改名して glb に書き出す
  （Godot 側では VRM の骨格へ名前で結び直す：scripts/player/anime_char.gd）

使い方: python vrm_wasou.py <入力.vrm> <出力.glb> <female 0/1>
"""
import json
import math
import os
import shutil
import struct
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kimono  # noqa: E402
import anime_garment  # noqa: E402

CLOTH_KEYS = ("_CLOTH",)


def vrm_human_bones(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    nodes = j["nodes"]
    ext = j.get("extensions", {})
    out = {}
    if "VRM" in ext:
        for hb in ext["VRM"]["humanoid"]["humanBones"]:
            out[nodes[hb["node"]]["name"]] = hb["bone"][0].upper() + hb["bone"][1:]
    elif "VRMC_vrm" in ext:
        for k, v in ext["VRMC_vrm"]["humanoid"]["humanBones"].items():
            out[nodes[v["node"]]["name"]] = k[0].upper() + k[1:]
    return out, "VRM" in ext


ARM_DOWN = 68.0   # 上腕を T ポーズから下ろす角度（度）
ELBOW = 12.0      # 肘を少し前に曲げる角度


def a_pose(arm):
    """上腕を下ろし肘を少し曲げる。各骨のワールド空間の変化（休止→ポーズ）を返す。"""
    from mathutils import Matrix
    mw = arm.matrix_world
    bpy.context.view_layer.objects.active = arm
    for sname, sgn in (("Left", 1.0), ("Right", -1.0)):
        for prof, ang, axis in (("UpperArm", ARM_DOWN, "Y"), ("LowerArm", ELBOW, "Z")):
            nm = kimono.NAMES.get(("upperarm_" if prof == "UpperArm" else "lowerarm_") + ("l" if sname == "Left" else "r"))
            pb = arm.pose.bones[nm]
            h = pb.head.copy()
            # 体の向き（正面 -Y、左 +X）基準：上腕は前後軸まわりに下へ、前腕は上下軸まわりに前へ
            a = math.radians(ang) * (sgn if prof == "UpperArm" else -sgn)
            r = Matrix.Rotation(a, 4, axis)
            # アーマチュア空間で回す（オブジェクトの回転を打ち消して世界の軸で回す）
            rw = mw.inverted() @ r @ mw
            rw3 = rw.to_3x3().to_4x4()
            pb.matrix = Matrix.Translation(h) @ rw3 @ Matrix.Translation(-h) @ pb.matrix
            bpy.context.view_layer.update()
    deltas = {}
    for pb in arm.pose.bones:
        deltas[pb.name] = mw @ pb.matrix @ pb.bone.matrix_local.inverted() @ mw.inverted()
    return deltas


def posed_copy(body):
    g = body.copy()
    g.data = body.data.copy()
    g.name = "BodyPosed"
    bpy.context.collection.objects.link(g)
    bpy.context.view_layer.objects.active = g
    for m in list(g.modifiers):
        if m.type == "ARMATURE":
            with bpy.context.temp_override(object=g, active_object=g):
                bpy.ops.object.modifier_apply(modifier=m.name)
    return g


def unpose(o, deltas):
    """A ポーズで作った布を休止姿勢へ戻す（線形ブレンドスキニングの逆変換）。"""
    from mathutils import Matrix
    names = {vg.index: vg.name for vg in o.vertex_groups}
    mw = o.matrix_world
    mwi = mw.inverted()
    for v in o.data.vertices:
        acc = Matrix(((0, 0, 0, 0),) * 4)
        tot = 0.0
        for g in v.groups:
            d = deltas.get(names.get(g.group))
            if d is not None and g.weight > 0:
                acc += d * g.weight
                tot += g.weight
        if tot <= 1e-6:
            continue
        m = acc * (1.0 / tot)
        v.co = mwi @ (m.inverted() @ (mw @ v.co))


def main():
    src, out, female = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    tmp = out + ".in.glb"
    shutil.copy(src, tmp)
    bpy.ops.import_scene.gltf(filepath=tmp)
    os.remove(tmp)
    human, vrm0 = vrm_human_bones(src)
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    body = bpy.data.objects["Body"]
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.name not in ("Body",) and not o.name.startswith(("Face", "Hair")):
            bpy.data.objects.remove(o, do_unlink=True)
    # 元の服の面を取り除く
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(body.data)
    cloth_idx = {i for i, m in enumerate(body.data.materials) if m and any(k in m.name for k in CLOTH_KEYS)}
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in cloth_idx], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(body.data)
    bm.free()
    # kimono.py は「正面が -Y」前提。VRM0 は +Y を向いて読み込まれるので一時的に回す
    # glTF から読み込んだアーマチュアは回転がクォータニオン指定なので、オイラーに切り替えてから回す
    arm.rotation_mode = "XYZ"
    if vrm0:
        arm.rotation_euler.z = math.pi
        bpy.context.view_layer.update()
    rev = {v: k for k, v in human.items()}
    side = {"l": "Left", "r": "Right"}
    mh = {"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Chest", "spine_03": "UpperChest",
          "neck_01": "Neck", "head": "Head"}
    for s, S in side.items():
        mh.update({"clavicle_" + s: S + "Shoulder", "upperarm_" + s: S + "UpperArm", "lowerarm_" + s: S + "LowerArm",
                   "hand_" + s: S + "Hand", "thigh_" + s: S + "UpperLeg", "calf_" + s: S + "LowerLeg",
                   "foot_" + s: S + "Foot"})
    kimono.NAMES.clear()
    for k, prof in mh.items():
        if prof in rev:
            kimono.NAMES[k] = rev[prof]
    if "UpperChest" not in rev:
        kimono.NAMES["spine_03"] = rev["Chest"]
    # 腕を下ろした姿勢（A ポーズ）にして、その体で布を作る
    deltas = a_pose(arm)
    body_p = posed_copy(body)
    kimono.USE_POSE = True
    kimono.ARM = arm
    L = kimono.landmarks(body_p)
    garments = anime_garment.make(body_p, L, female, body)
    kimono.USE_POSE = False
    if os.environ.get("WASOU_PREVIEW"):
        # 確認用：A ポーズのまま Blender（Cycles）で撮る
        import anime_costume
        anime_costume.preview(garments, body_p, L, os.environ["WASOU_PREVIEW"], os.environ.get("WASOU_PARTS", ""),
                              os.environ.get("WASOU_CAMS", "front,back,feet"))
    if os.environ.get("KEEP_POSE"):
        # 確認用：A ポーズのまま書き出す
        deltas = None
    for g in garments.values():
        if deltas:
            unpose(g, deltas)
    for o in arm.pose.bones:
        o.matrix_basis.identity()
    bpy.context.view_layer.update()
    bpy.data.objects.remove(body_p, do_unlink=True)
    bodyw = bpy.data.objects["w_bodyw"]
    bodywf = bpy.data.objects["w_bodywf"]
    # 書き出し用：服と和装用の体をアーマチュアの子にして、向きを元に戻す
    objs = list(garments.values()) + [bodyw, bodywf]
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = arm
        o.matrix_world = mw
        for m in o.modifiers:
            if m.type == "ARMATURE":
                m.object = arm
    arm.rotation_euler.z = 0.0
    bpy.context.view_layer.update()
    bpy.context.view_layer.update()
    # 骨（と頂点グループ）を人型プロファイル名に
    for b in arm.data.bones:
        if b.name in human:
            old = b.name
            b.name = human[old]
            for o in objs:
                vg = o.vertex_groups.get(old)
                if vg:
                    vg.name = b.name
    bodyw.name = "BodyW"
    bodywf.name = "BodyWF"
    for o in bpy.data.objects:
        o.select_set(o in objs or o == arm)
    bpy.context.view_layer.objects.active = arm
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o not in objs:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_skins=True,
                              export_animations=False, export_yup=True, export_apply=False)
    print("EXPORTED", out, {k: len(v.data.vertices) for k, v in garments.items()})


if __name__ == "__main__":
    main()
