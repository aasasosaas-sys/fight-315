"""リアルな人物モデル（MakeHuman / MPFB2, CC0）を Blender ヘッドレスで生成して glb に書き出す。

前提: Blender 5.x の bpy モジュール + MPFB2 拡張がインストール済み、MakeHuman system assets (CC0) が
MPFB のユーザーデータに配置済み（README 参照）。

使い方:
    python make_humans.py <出力ディレクトリ> [バリアント名 ...]
"""
import os
import sys
import json

import bpy
import addon_utils

addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)

from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402

import random

# 顔のパーツ（減↔増の対）。左右対称のものは l-/r- を同値で掛ける
FACE_PAIRS = [
    ("nose-hump-decr", "nose-hump-incr"), ("nose-point-width-decr", "nose-point-width-incr"),
    ("nose-flaring-decr", "nose-flaring-incr"), ("nose-base-down", "nose-base-up"),
    ("nose-nostrils-width-decr", "nose-nostrils-width-incr"), ("nose-compression-compress", "nose-compression-uncompress"),
    ("chin-width-decr", "chin-width-incr"), ("chin-prominent-decr", "chin-prominent-incr"),
    ("chin-height-decr", "chin-height-incr"), ("chin-jaw-drop-decr", "chin-jaw-drop-incr"),
    ("mouth-cupidsbow-decr", "mouth-cupidsbow-incr"), ("mouth-angles-down", "mouth-angles-up"),
    ("mouth-lowerlip-height-decr", "mouth-lowerlip-height-incr"),
]
FACE_SYM = [
    ("cheek-bones-decr", "cheek-bones-incr"), ("cheek-volume-decr", "cheek-volume-incr"),
    ("eye-scale-decr", "eye-scale-incr"), ("eye-epicanthus-in", "eye-epicanthus-out"),
    ("eye-eyefold-down", "eye-eyefold-up"), ("eye-corner1-down", "eye-corner1-up"),
    ("ear-scale-decr", "ear-scale-incr"),
]
HEADS = ["head-oval", "head-round", "head-square", "head-rectangular", "head-diamond", "head-triangular"]


# 日本人（東アジア系）の顔立ちの基礎：蒙古ひだ・一重〜奥二重・低めの鼻筋・小鼻・頬骨
JAPANESE_BASE = [
    ("l-eye-epicanthus-in", 0.45, 0.85), ("r-eye-epicanthus-in", None, None),
    ("l-eye-eyefold-down", 0.25, 0.6), ("r-eye-eyefold-down", None, None),
    ("l-eye-height2-decr", 0.1, 0.35), ("r-eye-height2-decr", None, None),
    ("nose-hump-decr", 0.3, 0.65), ("nose-flaring-incr", 0.15, 0.4), ("nose-point-width-incr", 0.1, 0.35),
    ("l-cheek-bones-incr", 0.15, 0.4), ("r-cheek-bones-incr", None, None),
]
JP_EXCLUDE = {"eye-epicanthus-in", "eye-eyefold-down", "nose-hump-decr", "cheek-bones-decr", "cheek-bones-incr"}


def face_targets(rng):
    out = [{"target": rng.choice(["head-oval", "head-round", "head-square", "head-rectangular"]), "value": rng.uniform(0.2, 0.55)}]
    last = 0.0
    for name, lo, hi in JAPANESE_BASE:
        if lo is not None:
            last = rng.uniform(lo, hi)
        out.append({"target": name, "value": last})
    for a, b in FACE_PAIRS:
        if a in JP_EXCLUDE or b in JP_EXCLUDE or a.startswith("nose-hump"):
            continue
        if rng.random() < 0.6:
            out.append({"target": rng.choice((a, b)), "value": rng.uniform(0.1, 0.45)})
    for a, b in FACE_SYM:
        if a in JP_EXCLUDE or b in JP_EXCLUDE or a.startswith("eye-epicanthus") or a.startswith("eye-eyefold") or a.startswith("cheek-bones"):
            continue
        if rng.random() < 0.6:
            t, v = rng.choice((a, b)), rng.uniform(0.1, 0.4)
            out.append({"target": "l-" + t, "value": v})
            out.append({"target": "r-" + t, "value": v})
    return out


def make_variants():
    rng = random.Random(2026)
    v = {}
    male_hair = ["short01", "short02", "short03", "short04", "short02", "short04", "short03", "short01"]
    male_clothes = [["male_casualsuit01", "shoes01"], ["male_casualsuit02", "shoes02"], ["male_worksuit01", "shoes06"],
                    ["male_elegantsuit01", "shoes03"], ["male_casualsuit04", "shoes01"], ["male_casualsuit05", "shoes02"],
                    ["male_casualsuit06", "shoes03"], ["male_casualsuit03", "shoes01"]]
    for i in range(8):
        v["m%02d" % (i + 1)] = {"gender": 1.0, "age": rng.uniform(0.42, 0.68), "muscle": rng.uniform(0.45, 0.7),
                                "weight": rng.uniform(0.4, 0.6), "height": rng.uniform(0.4, 0.55), "skin": "young_asian_male",
                                "hair": male_hair[i], "eyebrows": "eyebrow%03d" % rng.choice([1, 2, 3, 6, 7]),
                                "clothes": male_clothes[i], "targets": face_targets(rng)}
    for i in range(2):
        v["m%02d" % (i + 9)] = {"gender": 1.0, "age": rng.uniform(0.85, 0.95), "muscle": 0.4, "weight": rng.uniform(0.4, 0.55),
                                "height": 0.42, "skin": "old_asian_male", "hair": ["short01", "short03"][i],
                                "eyebrows": "eyebrow008", "clothes": [["male_casualsuit03", "shoes01"], ["male_worksuit01", "shoes06"]][i],
                                "targets": face_targets(rng)}
    female_hair = ["long01", "bob02", "ponytail01", "bob01", "braid01", "long01"]
    female_clothes = [["female_casualsuit01", "shoes05"], ["female_elegantsuit01", "shoes04"], ["female_casualsuit02", "shoes05"],
                      ["female_sportsuit01", "shoes04"], ["female_casualsuit01", "shoes05"], ["female_elegantsuit01", "shoes04"]]
    for i in range(6):
        v["f%02d" % (i + 1)] = {"gender": 0.0, "age": rng.uniform(0.42, 0.7), "muscle": rng.uniform(0.35, 0.5),
                                "weight": rng.uniform(0.4, 0.55), "height": rng.uniform(0.35, 0.5),
                                "skin": "middleage_asian_female", "hair": female_hair[i],
                                "eyebrows": "eyebrow%03d" % rng.choice([10, 11, 12]), "clothes": female_clothes[i],
                                "targets": face_targets(rng)}
    return v


VARIANTS = make_variants()


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build(name, v):
    info = HumanService._create_default_human_info_dict()
    info["name"] = name
    info["phenotype"].update({
        "gender": v["gender"], "age": v["age"], "muscle": v["muscle"], "weight": v["weight"],
        "height": v["height"], "proportions": 0.55,
        "race": {"asian": 1.0, "caucasian": 0.0, "african": 0.0},
    })
    info["rig"] = "game_engine"
    info["eyes"] = "low-poly.mhclo"
    info["eyebrows"] = v["eyebrows"] + ".mhclo"
    info["eyelashes"] = "eyelashes01.mhclo"
    info["hair"] = v["hair"] + ".mhclo"
    info["clothes"] = [c + ".mhclo" for c in v["clothes"]]
    info["targets"] = v.get("targets", [])
    info["skin_mhmat"] = os.path.join("skins", v["skin"], v["skin"] + ".mhmat")
    info["skin_material_type"] = "MAKESKIN"
    info["eyes_material_type"] = "MAKESKIN"
    info["clothes_material_type"] = "MAKESKIN"
    info["alternative_materials"] = {}
    settings = HumanService.get_default_deserialization_settings()
    settings["subdiv_levels"] = 0
    settings["override_skin_model"] = "MAKESKIN"
    basemesh = HumanService.deserialize_from_dict(info, settings)
    return basemesh


def bake_for_export():
    """シェイプキー（体型ターゲット）を確定し、サブディビジョンなどを外して書き出せる状態にする。"""
    for obj in list(bpy.data.objects):
        if obj.type != "MESH":
            continue
        bpy.context.view_layer.objects.active = obj
        if obj.data.shape_keys:
            obj.shape_key_add(name="__mix", from_mix=True)
            keys = obj.data.shape_keys.key_blocks
            mix = keys["__mix"]
            for kb in list(keys):
                if kb != mix:
                    obj.shape_key_remove(kb)
            obj.shape_key_remove(mix)
        for mod in list(obj.modifiers):
            if mod.type == "SUBSURF":
                obj.modifiers.remove(mod)
            elif mod.type == "MASK":
                # 服の下の体を消すマスクは使わない（和装・洋装を切り替えるため体は残す）
                obj.modifiers.remove(mod)


import bmesh

# 和装：体の一部を骨のウェイトで切り出して膨らませ、骨格で一緒に動く衣服にする
GARMENTS = {
    # 名前: (骨, 基本の膨らみ[m], 下へ行くほどの広がり[m], 脚を中央へ寄せる率)
    "kosode": (["spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r",
                "lowerarm_l", "lowerarm_r", "pelvis"], 0.016, 0.0, 0.0),
    "hakama": (["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"], 0.03, 0.09, 0.0),
    "robe": (["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"], 0.025, 0.05, 0.55),
    "armor": (["spine_01", "spine_02", "spine_03", "pelvis"], 0.055, 0.02, 0.0),
}


def find_body():
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name.lower().endswith("body"):
            return o
    for o in bpy.data.objects:
        if o.type == "MESH" and "body" in o.name.lower():
            return o
    return None


def make_garments(variant):
    body = find_body()
    if body is None:
        print("WARN no body for garments"); return
    hips_z = None
    for key, (bones, base, flare, pinch) in GARMENTS.items():
        g = body.copy()
        g.data = body.data.copy()
        g.name = "%s_garment_%s" % (variant, key)
        bpy.context.collection.objects.link(g)
        bm = bmesh.new()
        bm.from_mesh(g.data)
        deform = bm.verts.layers.deform.active
        idx = {vg.name: vg.index for vg in g.vertex_groups}
        want = [idx[b] for b in bones if b in idx]
        exclude = [idx[b] for b in ("hand_l", "hand_r", "head", "neck_01", "foot_l", "foot_r", "ball_l", "ball_r") if b in idx]
        kill = []
        zs = [v.co.z for v in bm.verts]
        top, bottom = max(zs), min(zs)
        if hips_z is None:
            hips_z = bottom + (top - bottom) * 0.52
        for v in bm.verts:
            w = sum(v[deform].get(i, 0.0) for i in want) if deform else 0.0
            ex = sum(v[deform].get(i, 0.0) for i in exclude) if deform else 0.0
            if w < 0.5 or ex > 0.25:
                kill.append(v)
        print("GARMENT", key, "groups", len(want), "/", len(bones), "kept", len(bm.verts) - len(kill), "of", len(bm.verts),
              [b for b in bones if b not in idx][:4])
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
        bm.normal_update()
        for v in bm.verts:
            t = max(0.0, min(1.0, (hips_z - v.co.z) / max(hips_z - bottom, 0.01)))
            off = base + flare * t
            v.co += v.normal * off
            if pinch > 0.0 and t > 0.0:
                v.co.x *= (1.0 - pinch * min(1.0, t * 1.4))
        bm.to_mesh(g.data)
        bm.free()
        g.data.materials.clear()
        m = bpy.data.materials.new("garment_" + key)
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8, 0.8, 0.8, 1)
        m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
        g.data.materials.append(m)
        for poly in g.data.polygons:
            poly.use_smooth = True


def shrink_textures(max_size=2048):
    for img in bpy.data.images:
        w, h = img.size
        if w > max_size or h > max_size:
            k = max_size / max(w, h)
            img.scale(max(1, int(w * k)), max(1, int(h * k)))


def export(path):
    shrink_textures()
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", export_texture_dir="textures",
                              export_skins=True, export_animations=False,
                              export_apply=False, export_yup=True, export_texcoords=True, export_normals=True,
                              export_materials="EXPORT", export_image_format="WEBP", export_image_quality=85)


def main():
    argv = sys.argv[1:]
    out = argv[0] if argv else os.path.abspath("humans_out")
    names = argv[1:] or list(VARIANTS)
    os.makedirs(out, exist_ok=True)
    for name in names:
        clear_scene()
        build(name, VARIANTS[name])
        bake_for_export()
        make_garments(name)
        path = os.path.join(out, name + ".gltf")
        export(path)
        print("EXPORTED", path, os.path.getsize(path))


if __name__ == "__main__":
    main()
