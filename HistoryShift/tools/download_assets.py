#!/usr/bin/env python3
"""Poly Haven (CC0) から素材を自動ダウンロードして Godot プロジェクトに配置する。

使い方（HistoryShift フォルダで実行）:
    python3 Tools/download_assets.py            # textures + hdri + models(core)
    python3 Tools/download_assets.py --full     # 大きい樹木・船モデルも含める（数百MB）
    python3 Tools/download_assets.py --only textures hdri

すべて CC0（パブリックドメイン相当）。クレジット不要だが CREDITS.md に一覧を出力する。
ゲーム本体は素材がなくても手続き生成で動く。素材があれば自動で差し替わる。
"""
import argparse, json, os, sys, time, urllib.request

API = "https://api.polyhaven.com"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "polyhaven")
UA = {"User-Agent": "HistoryShiftAssetFetcher/1.0"}

# ゲーム内キー -> Poly Haven ID
TEXTURES = {
    "grass": "leafy_grass", "forest": "forest_ground_04", "rock": "rocky_terrain_02",
    "dirt": "stony_dirt_path", "sand": "coast_sand_01", "cobble": "cobblestone_floor_01",
    "asphalt": "asphalt_02", "plaster": "painted_plaster_wall", "wood": "wood_planks",
    "darkwood": "wood_plank_wall", "rooftile": "grey_roof_tiles", "thatch": "thatch_roof_angled",
    "stonewall": "japanese_stone_wall", "brick": "brick_wall_02", "concrete": "concrete_floor_02",
    "tatami": "tatami_mat", "bamboo": "bamboo_wall",
}
HDRIS = {"day": "autumn_field_puresky", "clear": "farm_field_puresky",
         "hazy": "hilly_terrain_01_puresky", "evening": "evening_road_01_puresky"}
MODELS_CORE = ["shrub_01", "shrub_02", "boulder_01", "rock_07", "rock_moss_set_01", "fern_02",
               "grass_medium_01", "tree_stump_01", "antique_katana_01", "katana_stand_01",
               "Barrel_01", "wooden_crate_01", "wooden_bucket_01", "wicker_basket_01", "stone_fire_pit",
               "cannon_01", "street_lamp_01", "covered_car", "service_pistol", "horse_statue_01",
               "Lantern_01", "treasure_chest"]
MODELS_FULL = ["island_tree_01", "island_tree_02", "dutch_ship_medium", "modular_electricity_poles",
               "modular_wooden_pier", "bolt_action_rifle_7_62", "dead_tree_trunk", "wooden_lantern_01"]


def get_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)


def download(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return False
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r, open(dest + ".part", "wb") as f:
                while True:
                    b = r.read(1 << 20)
                    if not b: break
                    f.write(b)
            os.replace(dest + ".part", dest)
            return True
        except Exception as e:
            print(f"  retry {attempt + 1}: {e}")
            time.sleep(2 ** attempt)
    raise RuntimeError(f"failed: {url}")


def fetch_textures(credits, res):
    for key, pid in TEXTURES.items():
        files = get_json(f"{API}/files/{pid}")
        for kind, mapname in [("diff", "Diffuse"), ("nor_gl", "nor_gl"), ("rough", "Rough")]:
            entry = files.get(mapname, {}).get(res, {}).get("jpg") or files.get(mapname, {}).get(res, {}).get("png")
            if not entry: continue
            ext = os.path.splitext(entry["url"])[1]
            if download(entry["url"], os.path.join(ROOT, "textures", f"{key}_{kind}{ext}")):
                print(f"texture {key} <- {pid} {kind}")
        credits.append(("texture", key, pid))


def fetch_hdris(credits, res):
    for key, pid in HDRIS.items():
        files = get_json(f"{API}/files/{pid}")
        entry = files["hdri"][res]["hdr"]
        if download(entry["url"], os.path.join(ROOT, "hdri", f"sky_{key}.hdr")):
            print(f"hdri {key} <- {pid}")
        credits.append(("hdri", key, pid))


def fetch_models(ids, credits, res):
    for pid in ids:
        files = get_json(f"{API}/files/{pid}")
        fbx = files["gltf"][res]["gltf"]
        base = os.path.join(ROOT, "models", pid)
        changed = download(fbx["url"], os.path.join(base, f"{pid}.gltf"))
        for rel, inc in fbx.get("include", {}).items():
            download(inc["url"], os.path.join(base, rel))
        if changed: print(f"model {pid}")
        credits.append(("model", pid, pid))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--full", action="store_true", help="大きいモデルも取得")
    ap.add_argument("--only", nargs="*", choices=["textures", "hdri", "models"])
    ap.add_argument("--res", default="1k", help="解像度 1k/2k/4k（テクスチャ・モデル）")
    a = ap.parse_args()
    parts = a.only or ["textures", "hdri", "models"]
    credits = []
    if "textures" in parts: fetch_textures(credits, a.res)
    if "hdri" in parts: fetch_hdris(credits, "1k" if a.res == "1k" else "2k")
    if "models" in parts: fetch_models(MODELS_CORE + (MODELS_FULL if a.full else []), credits, a.res)
    os.makedirs(ROOT, exist_ok=True)
    with open(os.path.join(ROOT, "CREDITS.md"), "w", encoding="utf-8") as f:
        f.write("# Poly Haven assets (CC0)\n\nhttps://polyhaven.com/license\n\n")
        for kind, key, pid in credits:
            f.write(f"- {kind}: `{key}` — https://polyhaven.com/a/{pid}\n")
    print("done.")


if __name__ == "__main__":
    sys.exit(main())
