# Procedural anime hair (AnimeHair)

Generates `assets/characters/hair/<style>.glb` (one mesh per CC0 VRoid model, in head-bone-local
coordinates) and `hair_lit.png` / `hair_shade.png` (MToon lit/shade textures with the angel-ring band).

    # needs Blender 5.x as a Python module (bpy) + the VRMs copied as vrm/<Model>.glb next to the scripts
    python gen_tex.py
    python gen_hair.py              # all styles
    python gen_hair.py -- chonmage  # one style

Runtime: `AnimeHair.apply(vrm_root, "chonmage")` (scripts/player/anime_hair.gd).
