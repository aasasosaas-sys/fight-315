import sys, os, math, random, importlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
from hairlib import *
import styles

OUT = "/home/user/fight-315/HistoryShift/assets/characters/hair/"
MODELS = ["HairSample_Male", "Sakurada_Fumiriya", "HairSample_Female", "Sendagaya_Shibu", "Sendagaya_Shino"]

want = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
style_names = [s for s in styles.STYLES if not want or s in want]
models = [m for m in MODELS if not any(w.startswith("model=") for w in want)] or MODELS
for w in want:
    if w.startswith("model="):
        models = w[6:].split(",")
        style_names = [s for s in styles.STYLES if s in want] or list(styles.STYLES)

data = {s: {} for s in style_names}
meta = {}
for m in models:
    head = Head(m)
    meta[m] = head
    for s in style_names:
        b = Builder()
        random.seed(sum(map(ord, s)) + 7)
        styles.STYLES[s](b, head)
        data[s][m] = b

bpy.ops.wm.read_factory_settings(use_empty=True)
for s in style_names:
    objs = []
    for m in models:
        objs.append(data[s][m].to_object(m))
    export_glb(objs, OUT + s + ".glb")
    for o in objs:
        bpy.data.objects.remove(o)
    print("exported", s)
