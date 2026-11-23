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

# 日本人らしい体格・年齢・髪型・服装のバリエーション
# clothes は MakeHuman system assets のフォルダ名（明治・昭和の洋装に使う。前近代の衣装は Godot 側で重ねる）
VARIANTS = {
    "m_young": {"gender": 1.0, "age": 0.45, "muscle": 0.55, "weight": 0.45, "height": 0.45, "skin": "young_asian_male",
                "hair": "short02", "eyebrows": "eyebrow001", "clothes": ["male_casualsuit01", "shoes01"]},
    "m_adult": {"gender": 1.0, "age": 0.6, "muscle": 0.6, "weight": 0.55, "height": 0.5, "skin": "young_asian_male",
                "hair": "short04", "eyebrows": "eyebrow007", "clothes": ["male_worksuit01", "shoes02"]},
    "m_suit": {"gender": 1.0, "age": 0.65, "muscle": 0.5, "weight": 0.5, "height": 0.5, "skin": "young_asian_male",
               "hair": "short02", "eyebrows": "eyebrow002", "clothes": ["male_elegantsuit01", "shoes03"]},
    "m_old": {"gender": 1.0, "age": 0.9, "muscle": 0.4, "weight": 0.45, "height": 0.4, "skin": "old_asian_male",
              "hair": "short01", "eyebrows": "eyebrow008", "clothes": ["male_casualsuit03", "shoes01"]},
    "m_soldier": {"gender": 1.0, "age": 0.5, "muscle": 0.7, "weight": 0.5, "height": 0.5, "skin": "young_asian_male",
                  "hair": "short03", "eyebrows": "eyebrow001", "clothes": ["male_worksuit01", "shoes06"]},
    "f_young": {"gender": 0.0, "age": 0.45, "muscle": 0.4, "weight": 0.45, "height": 0.4, "skin": "middleage_asian_female",
                "hair": "long01", "eyebrows": "eyebrow010", "clothes": ["female_casualsuit01", "shoes05"]},
    "f_adult": {"gender": 0.0, "age": 0.6, "muscle": 0.45, "weight": 0.5, "height": 0.4, "skin": "middleage_asian_female",
                "hair": "bob02", "eyebrows": "eyebrow011", "clothes": ["female_elegantsuit01", "shoes04"]},
    "f_tied": {"gender": 0.0, "age": 0.5, "muscle": 0.45, "weight": 0.45, "height": 0.42, "skin": "middleage_asian_female",
               "hair": "ponytail01", "eyebrows": "eyebrow012", "clothes": ["female_casualsuit02", "shoes05"]},
}


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
                with bpy.context.temp_override(object=obj):
                    try:
                        bpy.ops.object.modifier_apply(modifier=mod.name)
                    except RuntimeError:
                        obj.modifiers.remove(mod)


def shrink_textures(max_size=1024):
    for img in bpy.data.images:
        w, h = img.size
        if w > max_size or h > max_size:
            k = max_size / max(w, h)
            img.scale(max(1, int(w * k)), max(1, int(h * k)))


def export(path):
    shrink_textures()
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_skins=True, export_animations=False,
                              export_apply=False, export_yup=True, export_texcoords=True, export_normals=True,
                              export_materials="EXPORT", export_image_format="JPEG", export_jpeg_quality=85)


def main():
    argv = sys.argv[1:]
    out = argv[0] if argv else os.path.abspath("humans_out")
    names = argv[1:] or list(VARIANTS)
    os.makedirs(out, exist_ok=True)
    for name in names:
        clear_scene()
        build(name, VARIANTS[name])
        bake_for_export()
        path = os.path.join(out, name + ".glb")
        export(path)
        print("EXPORTED", path, os.path.getsize(path))


if __name__ == "__main__":
    main()
