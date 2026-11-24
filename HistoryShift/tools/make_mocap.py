"""CMU モーションキャプチャ（BVH）からゲーム用アニメーションを作る（Blender bpy ヘッドレス）。

- ループ素材（歩き・走りなど）は姿勢が最も近い2フレームを自動で探して1周期を切り出し、
  腰の水平移動を取り除いてその場の動き（in-place）にする。
- 座り・射撃・転倒などは指定の方法で区間を選ぶ。
- すべてを1体のアーマチュアの NLA に積んで mocap.glb に書き出す（Godot 側で人型プロファイルへリターゲット）。

出典: CMU Graphics Lab Motion Capture Database（http://mocap.cs.cmu.edu）
      BVH 変換: Bruce Hahne / cgspeed。CMU と変換者はいずれも自由な利用を認めている。
使い方: python make_mocap.py <BVHのdataディレクトリ> <出力.glb>
"""
import math
import os
import sys

import bpy

# (出力名, ファイル, 種別, パラメータ)
CLIPS = [
    ("Mocap_Idle", "140/140_06.bvh", "window", {"start": 2.0, "len": 6.0}),
    ("Mocap_Stand", "007/07_01.bvh", "window", {"start": 0.0, "len": 0.6}),
    ("Mocap_Walk", "007/07_01.bvh", "loop", {"min": 0.9, "max": 1.4}),
    ("Mocap_SlowWalk", "007/07_04.bvh", "loop", {"min": 1.1, "max": 1.8}),
    ("Mocap_Jog", "002/02_03.bvh", "loop", {"min": 0.55, "max": 0.95}),
    ("Mocap_Run", "009/09_01.bvh", "loop", {"min": 0.5, "max": 0.85}),
    ("Mocap_March", "020/20_06.bvh", "loop", {"min": 0.9, "max": 1.4}),
    ("Mocap_Sit", "013/13_01.bvh", "lowest", {"len": 2.0}),
    ("Mocap_Shoot", "080/80_03.bvh", "window", {"start": 0.4, "len": 0.45, "frac": True}),
    ("Mocap_Fall", "090/90_16.bvh", "until_low", {}),
]
FPS = 30


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


def import_bvh(path):
    before = set(bpy.data.objects)
    bpy.ops.import_anim.bvh(filepath=path, global_scale=0.056444, frame_start=0, use_fps_scale=True,
                            update_scene_fps=False, update_scene_duration=False, rotate_mode="NATIVE",
                            axis_forward="-Z", axis_up="Y")
    arm = [o for o in bpy.data.objects if o not in before and o.type == "ARMATURE"][0]
    return arm


def fcurves(act):
    """Blender 4.4+ のレイヤー化アクションにも対応して F カーブ一覧を返す。"""
    try:
        return list(act.fcurves)
    except AttributeError:
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    out.extend(cb.fcurves)
        return out


def rot_curves(act):
    return [fc for fc in fcurves(act) if "rotation" in fc.data_path]


def pose_dist(curves, a, b):
    return sum(abs(fc.evaluate(a) - fc.evaluate(b)) for fc in curves)


def frame_range(act):
    return [int(x) for x in act.frame_range]


def find_loop(act, tmin, tmax):
    curves = rot_curves(act)
    f0, f1 = frame_range(act)
    best = (1e18, f0, f0 + int(tmin * FPS))
    for s in range(f0 + int(0.5 * FPS), max(f0 + int(0.5 * FPS) + 1, f1 - int(tmax * FPS)), 2):
        for e in range(s + int(tmin * FPS), min(f1, s + int(tmax * FPS)) + 1):
            d = pose_dist(curves, s, e)
            if d < best[0]:
                best = (d, s, e)
    return best[1], best[2]


def hips_height_curve(act):
    for fc in fcurves(act):
        if fc.data_path.endswith('"Hips"].location') and fc.array_index == 2:
            return fc
    for fc in fcurves(act):
        if fc.data_path.endswith('"Hips"].location') and fc.array_index == 1:
            return fc
    return None


def trim(act, s, e):
    for fc in fcurves(act):
        pts = [(k.co[0], k.co[1]) for k in fc.keyframe_points if s <= k.co[0] <= e]
        vals = [(f - s, fc.evaluate(f)) for f in range(int(s), int(e) + 1)] if not pts else [(f - s, v) for f, v in pts]
        while fc.keyframe_points:
            fc.keyframe_points.remove(fc.keyframe_points[0], fast=True)
        fc.keyframe_points.add(len(vals))
        for i, (f, v) in enumerate(vals):
            fc.keyframe_points[i].co = (f, v)
            fc.keyframe_points[i].interpolation = "LINEAR"
        fc.update()


def make_inplace(act):
    for fc in fcurves(act):
        if fc.data_path.endswith('"Hips"].location') and fc.array_index in (0, 1):
            first = fc.keyframe_points[0].co[1] if fc.keyframe_points else 0.0
            for k in fc.keyframe_points:
                k.co[1] = first
            fc.update()


# 他の骨格（MakeHuman / KayKit）と同じ構成に簡略化した骨格：鎖骨・腰椎・首を省く
SIMPLE = {
    "Hips": None, "Spine": "Hips", "Spine1": "Spine", "Head": "Spine1",
    "LeftArm": "Spine1", "LeftForeArm": "LeftArm", "LeftHand": "LeftForeArm",
    "RightArm": "Spine1", "RightForeArm": "RightArm", "RightHand": "RightForeArm",
    "LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg", "LeftFoot": "LeftLeg", "LeftToeBase": "LeftFoot",
    "RightUpLeg": "Hips", "RightLeg": "RightUpLeg", "RightFoot": "RightLeg", "RightToeBase": "RightFoot",
}


def rebake_simplified(src):
    """CMU 骨格の動きを、立った高さが正しい簡略骨格へワールド空間で焼き直す。"""
    from mathutils import Matrix, Vector
    mw = src.matrix_world.copy()
    rest = {b.name: (mw @ b.matrix_local, b.length) for b in src.data.bones}
    # 立っている時（Idle）の腰の高さを測り、簡略骨格の休止姿勢の腰をその高さに置く
    tracks0 = list(src.animation_data.nla_tracks)
    for t2 in tracks0:
        t2.mute = True
    src.animation_data.action = tracks0[0].strips[0].action
    hz = []
    fz = []
    for f in range(0, 120, 6):
        bpy.context.scene.frame_set(f)
        hz.append((src.matrix_world @ src.pose.bones["Hips"].matrix).translation.z)
        fz.append(min((src.matrix_world @ src.pose.bones[n].matrix).translation.z for n in ("LeftToeBase", "RightToeBase")))
    src.animation_data.action = None
    stand_hips = sum(hz) / len(hz) - sum(fz) / len(fz) + 0.03
    rest_hips = (mw @ src.data.bones["Hips"].head_local).z
    lift = Matrix.Translation(Vector((0, 0, stand_hips - rest_hips)))
    print("stand hips", stand_hips, "rest hips", rest_hips)
    bpy.ops.object.armature_add(enter_editmode=True)
    dst = bpy.context.object
    dst.name = "Mocap"
    eb = dst.data.edit_bones
    eb.remove(eb[0])
    for n in SIMPLE:
        m, length = rest[n]
        b = eb.new(n)
        b.head = (0, 0, 0)
        b.tail = (0, max(length, 0.03), 0)
        b.matrix = lift @ m
    for n, p in SIMPLE.items():
        if p:
            eb[n].parent = eb[p]
            eb[n].use_connect = False
    bpy.ops.object.mode_set(mode="POSE")
    for n in SIMPLE:
        c = dst.pose.bones[n].constraints.new("COPY_TRANSFORMS")
        c.target = src
        c.subtarget = n
        c.target_space = "WORLD"
        c.owner_space = "WORLD"
    # 元データの腰の高さは絶対値（休止姿勢の腰が原点）なので、簡略骨格の休止姿勢だけを床基準に持ち上げる
    tracks = list(src.animation_data.nla_tracks)
    dst.animation_data_create()
    for tr in tracks:
        act = tr.strips[0].action
        for t2 in tracks:
            t2.mute = True
        src.animation_data.action = act
        f0, f1 = [int(x) for x in act.frame_range]
        bpy.context.view_layer.objects.active = dst
        bpy.ops.nla.bake(frame_start=f0, frame_end=f1, only_selected=False, visual_keying=True,
                         clear_constraints=False, use_current_action=False, bake_types={"POSE"})
        baked = dst.animation_data.action
        baked.name = act.name
        dst.animation_data.action = None
        nt = dst.animation_data.nla_tracks.new()
        nt.name = act.name
        nt.strips.new(act.name, 0, baked)
        src.animation_data.action = None
    for pb in dst.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
    bpy.ops.object.mode_set(mode="OBJECT")
    for tr in list(src.animation_data.nla_tracks):
        src.animation_data.nla_tracks.remove(tr)
    bpy.data.objects.remove(src, do_unlink=True)
    return dst


def main():
    data_dir = sys.argv[1]
    out = sys.argv[2]
    clear()
    base = None
    for name, rel, kind, p in CLIPS:
        arm = import_bvh(os.path.join(data_dir, rel))
        act = arm.animation_data.action
        f0, f1 = frame_range(act)
        if kind == "loop":
            s, e = find_loop(act, p["min"], p["max"])
            trim(act, s, e)
            make_inplace(act)
        elif kind == "window":
            if p.get("frac"):
                s = f0 + int((f1 - f0) * p["start"])
                e = s + int((f1 - f0) * p["len"])
            else:
                s = f0 + int(p["start"] * FPS)
                e = min(f1, s + int(p["len"] * FPS))
            trim(act, s, e)
            make_inplace(act)
        elif kind == "lowest":
            hc = hips_height_curve(act)
            n = int(p["len"] * FPS)
            best = min(range(f0, max(f0 + 1, f1 - n)), key=lambda f: sum(hc.evaluate(f + i) for i in range(0, n, 5)))
            trim(act, best, best + n)
            make_inplace(act)
        elif kind == "until_low":
            hc = hips_height_curve(act)
            low = min(range(f0, f1), key=lambda f: hc.evaluate(f))
            trim(act, f0, min(f1, low + 10))
        act.name = name
        print("CLIP", name, frame_range(act))
        if base is None:
            base = arm
            base.name = "Mocap"
            base.animation_data.action = None
        else:
            arm.animation_data.action = None
            bpy.data.objects.remove(arm, do_unlink=True)
        tr = base.animation_data.nla_tracks.new()
        tr.name = name
        tr.strips.new(name, 0, act)
    base.name = "CMUSrc"
    simple = rebake_simplified(base)
    # 書き出し用に小さな板ポリを付ける（スキンなしだと glTF でアーマチュアが落ちることがある）
    bpy.ops.mesh.primitive_plane_add(size=0.01)
    dummy = bpy.context.object
    dummy.name = "MocapDummy"
    dummy.parent = simple
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_yup=True, export_skins=True)
    print("EXPORTED", out)


if __name__ == "__main__":
    main()
