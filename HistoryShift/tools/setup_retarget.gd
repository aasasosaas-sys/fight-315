extends SceneTree
## KayKit アニメーションと MakeHuman 人物の骨格を Godot の人型プロファイル（SkeletonProfileHumanoid）へ
## 取り込み時にリターゲットする設定を書き込む。
## 実行: godot --headless --path . -s tools/setup_retarget.gd  →  その後 godot --headless --path . --import

const KAYKIT := {
	"Root": "root", "Hips": "hips", "Spine": "spine", "Chest": "chest", "Head": "head",
	"LeftUpperArm": "upperarm.l", "LeftLowerArm": "lowerarm.l", "LeftHand": "wrist.l",
	"RightUpperArm": "upperarm.r", "RightLowerArm": "lowerarm.r", "RightHand": "wrist.r",
	"LeftUpperLeg": "upperleg.l", "LeftLowerLeg": "lowerleg.l", "LeftFoot": "foot.l", "LeftToes": "toes.l",
	"RightUpperLeg": "upperleg.r", "RightLowerLeg": "lowerleg.r", "RightFoot": "foot.r", "RightToes": "toes.r",
}

const CMU := {
	"Hips": "Hips", "Spine": "Spine", "Chest": "Spine1", "Head": "Head",
	"LeftUpperArm": "LeftArm", "LeftLowerArm": "LeftForeArm", "LeftHand": "LeftHand",
	"RightUpperArm": "RightArm", "RightLowerArm": "RightForeArm", "RightHand": "RightHand",
	"LeftUpperLeg": "LeftUpLeg", "LeftLowerLeg": "LeftLeg", "LeftFoot": "LeftFoot", "LeftToes": "LeftToeBase",
	"RightUpperLeg": "RightUpLeg", "RightLowerLeg": "RightLeg", "RightFoot": "RightFoot", "RightToes": "RightToeBase",
}

const MH := {
	"Root": "Root", "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_03",
	"Head": "head",
	"LeftUpperArm": "upperarm_l", "LeftLowerArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightUpperArm": "upperarm_r", "RightLowerArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpperLeg": "thigh_l", "LeftLowerLeg": "calf_l", "LeftFoot": "foot_l", "LeftToes": "ball_l",
	"RightUpperLeg": "thigh_r", "RightLowerLeg": "calf_r", "RightFoot": "foot_r", "RightToes": "ball_r",
	"LeftThumbMetacarpal": "thumb_01_l", "LeftThumbProximal": "thumb_02_l", "LeftThumbDistal": "thumb_03_l",
	"LeftIndexProximal": "index_01_l", "LeftIndexIntermediate": "index_02_l", "LeftIndexDistal": "index_03_l",
	"LeftMiddleProximal": "middle_01_l", "LeftMiddleIntermediate": "middle_02_l", "LeftMiddleDistal": "middle_03_l",
	"LeftRingProximal": "ring_01_l", "LeftRingIntermediate": "ring_02_l", "LeftRingDistal": "ring_03_l",
	"LeftLittleProximal": "pinky_01_l", "LeftLittleIntermediate": "pinky_02_l", "LeftLittleDistal": "pinky_03_l",
	"RightThumbMetacarpal": "thumb_01_r", "RightThumbProximal": "thumb_02_r", "RightThumbDistal": "thumb_03_r",
	"RightIndexProximal": "index_01_r", "RightIndexIntermediate": "index_02_r", "RightIndexDistal": "index_03_r",
	"RightMiddleProximal": "middle_01_r", "RightMiddleIntermediate": "middle_02_r", "RightMiddleDistal": "middle_03_r",
	"RightRingProximal": "ring_01_r", "RightRingIntermediate": "ring_02_r", "RightRingDistal": "ring_03_r",
	"RightLittleProximal": "pinky_01_r", "RightLittleIntermediate": "pinky_02_r", "RightLittleDistal": "pinky_03_r",
}


func _make_map(table: Dictionary, path: String) -> BoneMap:
	var bm := BoneMap.new()
	bm.profile = SkeletonProfileHumanoid.new()
	for k in table:
		bm.set_skeleton_bone_name(k, table[k])
	ResourceSaver.save(bm, path)
	return load(path)


func _patch(glb: String, skel_path: String, bm: BoneMap) -> void:
	var ip := glb + ".import"
	var cfg := ConfigFile.new()
	if cfg.load(ip) != OK:
		print("skip (no .import yet): ", glb)
		return
	var sub: Dictionary = cfg.get_value("params", "_subresources", {})
	var nodes: Dictionary = sub.get("nodes", {})
	nodes["PATH:" + skel_path] = {
		"retarget/bone_map": bm,
		"retarget/bone_renamer/rename_bones": true,
		"retarget/rest_fixer/overwrite_axis": true,
		"retarget/rest_fixer/fix_silhouette/enable": OS.get_environment("FIXSIL") == "1",
		"retarget/rest_fixer/normalize_position_tracks": true,
	}
	sub["nodes"] = nodes
	cfg.set_value("params", "_subresources", sub)
	cfg.save(ip)
	print("patched ", glb)


func _initialize() -> void:
	var kk := _make_map(KAYKIT, "res://assets/characters/bonemap_kaykit.tres")
	var mh := _make_map(MH, "res://assets/characters/bonemap_mh.tres")
	var cmu := _make_map(CMU, "res://assets/characters/bonemap_cmu.tres")
	if FileAccess.file_exists("res://assets/characters/mocap/mocap.glb"):
		_patch("res://assets/characters/mocap/mocap.glb", "Mocap/Skeleton3D", cmu)
	for f in DirAccess.get_files_at("res://assets/characters/kaykit"):
		if f.ends_with(".glb"):
			_patch("res://assets/characters/kaykit/" + f, "Rig_Medium/Skeleton3D", kk)
	for f in DirAccess.get_files_at("res://assets/characters/mh"):
		if f.ends_with(".glb") or f.ends_with(".gltf"):
			_patch("res://assets/characters/mh/" + f, f.get_basename() + "/Skeleton3D", mh)
	quit()
