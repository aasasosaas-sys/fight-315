class_name AnimeFace
extends RefCounted
## アニメ調（VRoid）の顔・体つきに個性と年齢を与える。
## 素体が 5 体しかないので、群衆で同じ顔が並ばないよう、種（seed）から
##   顔の形（頬・顎・顔の長さ・目の間隔／大きさ／つり目・たれ目・眉・口）を頂点の歪みで、
##   肌の色・瞳の色・眉／睫毛の色・髪の色（白髪）を素材の色で、
##   髭・皺・頬紅・そばかす・黒子・傷を顔の上に重ねる描画（face_overlay.gdshader）で、
##   背丈・頭身・猫背・瞳の大きさを骨（SkeletonModifier3D）で、
##   眼鏡・眼帯・仙人髭を頭の骨に付ける小物で
## 変える。
##   var p := AnimeFace.apply(model, seed, {"age": "elder", "female": false})
## opts:
##   "age": "child" | "young" | "adult" | "elder"（既定: 若者・大人が多めの乱択）
##   "female": bool（既定: 素体から推定）
##   "modern": bool（明治以降。眼鏡が出る）
##   "fixed": {パラメータ名: 値}（選ばれた値を上書き。返り値と同じ名前）
## 返り値: 選ばれたパラメータ（Dictionary）。"height" は Skeleton3D の拡縮として適用済み
## （呼び出し側が model.scale を決めた後も効く）。

const DIR := "res://assets/characters/face/"
const FEMALE_BASES := ["HairSample_Female", "Sendagaya_Shino"]
const MOD_NAME := "AnimeFaceMod"
const ACC_NAME := "AnimeFaceAcc"

## 瞳（日本人らしい焦茶〜黒）
const IRIS := [
	Color(0.22, 0.12, 0.08), Color(0.28, 0.16, 0.1), Color(0.34, 0.2, 0.12),
	Color(0.15, 0.1, 0.09), Color(0.1, 0.08, 0.09), Color(0.38, 0.24, 0.14),
]
## 肌（色白 → 日焼けした農民・漁師）。テクスチャに掛け合わせる
const SKIN := {
	"fair": Color(1.0, 0.985, 0.975), "light": Color(0.985, 0.94, 0.9), "medium": Color(0.955, 0.875, 0.8),
	"tan": Color(0.9, 0.77, 0.66), "deep": Color(0.82, 0.66, 0.54),
}
## 黒髪の色味（暗いテクスチャへの掛け色）: 青み黒 / 黒 / 焦茶 / 栗
const HAIR_TINTS := [Color(1.0, 1.0, 1.0), Color(0.82, 0.8, 0.8), Color(0.9, 0.88, 0.86), Color(1.18, 1.0, 0.88), Color(1.3, 1.06, 0.9)]
const BEARDS := ["none", "stubble", "mustache", "goatee", "full", "dojo", "mustache_goatee"]
const MOODS := {
	"neutral": {},
	"gentle": {"BRW_Sorrow": 0.18, "MTH_Fun": 0.22},
	"stern": {"BRW_Angry": 0.32, "EYE_Angry": 0.12},
	"calm": {"EYE_Close": 0.22, "BRW_Fun": 0.15},
	"cheerful": {"MTH_Fun": 0.4, "BRW_Joy": 0.2},
	"worried": {"BRW_Sorrow": 0.4},
	"sharp": {"EYE_Angry": 0.22, "BRW_Angry": 0.15},
}

static var _info_cache := {}
static var _mesh_cache := {}
static var _tex_cache := {}
static var _overlay_shader: Shader


## 種から個性を選び、model（AnimeChar.build の戻り値）へ適用する
static func apply(root: Node3D, seed: int, opts := {}) -> Dictionary:
	var sk := _skeleton(root)
	if sk == null:
		return {}
	var base := root.scene_file_path.get_file().get_basename()
	var female: bool = bool(opts["female"]) if opts.has("female") else base in FEMALE_BASES
	var p := roll(seed, String(opts.get("age", "")), female, bool(opts.get("modern", false)))
	var fixed: Dictionary = opts.get("fixed", {})
	for k in fixed:
		p[k] = fixed[k]
	p["base"] = base
	var face := _find_mesh(sk, "Face")
	if face:
		_apply_face(face, sk, p)
	_apply_body_skin(sk, p)
	_apply_hair(sk, p)
	_apply_bones(sk, p)
	_apply_accessories(sk, face, p)
	return p


## パラメータだけを選ぶ（適用はしない）
static func roll(seed: int, age := "", female := false, modern := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed * 7919 + 17)
	if age == "":
		var r := rng.randf()
		age = "child" if r < 0.1 else ("young" if r < 0.45 else ("adult" if r < 0.85 else "elder"))
	var child := age == "child"
	var elder := age == "elder"
	var p := {"age": age, "female": female}
	# 背丈・頭身
	p["height"] = rng.randf_range(0.7, 0.8) if child else (rng.randf_range(0.93, 0.97) if elder else rng.randf_range(0.97, 1.03))
	p["head"] = rng.randf_range(1.14, 1.2) if child else rng.randf_range(0.97, 1.03)
	p["stoop"] = rng.randf_range(8.0, 16.0) if elder else 0.0
	# 顔の形（-1..1、0.5 刻み: 形の違う顔メッシュの数を抑える）
	p["jaw"] = _q(rng.randf_range(-1.0, 1.0) + (0.6 if child else 0.0) + (0.3 if not female and age != "young" else 0.0) - (0.3 if female else 0.0))
	p["face_len"] = _q(rng.randf_range(-1.0, 1.0) - (1.0 if child else 0.0) + (0.3 if elder else 0.0))
	p["chin"] = _q(rng.randf_range(-1.0, 1.0) - (0.5 if child else 0.0))
	p["cheek"] = _q(rng.randf_range(-1.0, 1.0) + (0.8 if child else 0.0) - (0.4 if elder else 0.0))
	p["eye_gap"] = _q(rng.randf_range(-1.0, 1.0))
	p["eye_h"] = _q(rng.randf_range(-1.0, 1.0) + (0.6 if child else 0.0) - (0.4 if elder else 0.0))
	p["eye_tilt"] = _q(rng.randf_range(-1.0, 1.0) - (0.7 if elder else 0.0))
	p["eye_y"] = _q(rng.randf_range(-1.0, 1.0))
	p["nose"] = _q(rng.randf_range(-1.0, 1.0) - (0.6 if child else 0.0) - (0.3 if female else 0.0))
	p["mouth_w"] = _q(rng.randf_range(-1.0, 1.0) - (0.5 if child else 0.0))
	p["brow_y"] = _q(rng.randf_range(-1.0, 1.0))
	p["brow_thick"] = _q(rng.randf_range(-1.0, 1.0) + (0.4 if not female else -0.4))
	p["brow_angle"] = _q(rng.randf_range(-1.0, 1.0) + (0.2 if not female else 0.0))
	p["iris_scale"] = rng.randf_range(1.04, 1.12) if child else rng.randf_range(0.9, 1.06)
	# 色
	p["iris"] = IRIS[rng.randi() % IRIS.size()]
	p["highlight"] = rng.randf_range(0.55, 0.8) if elder else rng.randf_range(0.8, 1.0)
	var tones: Array = ["fair", "light", "light", "medium", "medium", "tan", "deep"]
	if female:
		tones = ["fair", "fair", "light", "light", "medium", "tan"]
	if child:
		tones = ["fair", "light", "light", "medium", "tan"]
	p["skin"] = tones[rng.randi() % tones.size()]
	# 髪: 白髪の度合い 0 黒 / 1 胡麻塩 / 2 白
	var gray := 0
	if elder:
		gray = 1 if rng.randf() < 0.45 else 2
	elif age == "adult" and rng.randf() < 0.12:
		gray = 1
	p["hair_gray"] = gray
	p["hair_tint"] = HAIR_TINTS[rng.randi() % HAIR_TINTS.size()]
	p["lash"] = rng.randf_range(0.0, 1.0)
	p["blush"] = rng.randf_range(0.55, 0.9) if child else (rng.randf_range(0.25, 0.6) if female else (rng.randf_range(0.0, 0.25) if rng.randf() < 0.4 else 0.0))
	p["blush_lines"] = 1.0 if child and rng.randf() < 0.6 else 0.0
	p["freckles"] = rng.randf_range(0.5, 1.0) if rng.randf() < (0.18 if child else 0.06) else 0.0
	p["wrinkles"] = rng.randf_range(0.6, 1.0) if elder else (rng.randf_range(0.15, 0.35) if age == "adult" and rng.randf() < 0.35 else 0.0)
	p["mole"] = rng.randi_range(1, 4) if rng.randf() < 0.14 else 0
	p["lid"] = rng.randf_range(0.5, 0.9) if rng.randf() < (0.45 if female else 0.3) else 0.0
	p["beni"] = rng.randf_range(0.4, 0.9) if female and not child and rng.randf() < 0.55 else 0.0
	# 髭（男の大人・老人）
	var beard := "none"
	var stubble := 0.0
	if not female and not child and age != "young":
		var r2 := rng.randf()
		if elder:
			beard = "dojo" if r2 < 0.2 else ("goatee" if r2 < 0.42 else ("full" if r2 < 0.55 else ("mustache_goatee" if r2 < 0.7 else ("mustache" if r2 < 0.8 else "none"))))
		else:
			beard = "stubble" if r2 < 0.22 else ("mustache" if r2 < (0.4 if modern else 0.3) else ("goatee" if r2 < 0.38 else ("full" if r2 < 0.45 else ("mustache_goatee" if r2 < 0.52 else "none"))))
		if beard != "stubble" and rng.randf() < 0.25:
			stubble = rng.randf_range(0.4, 0.8)
	elif not female and age == "young" and rng.randf() < 0.12:
		stubble = rng.randf_range(0.3, 0.6)
	p["beard"] = beard
	p["stubble"] = stubble
	p["long_beard"] = elder and not female and beard in ["goatee", "dojo", "mustache_goatee"] and rng.randf() < 0.0  # 試作: fixed で明示したときだけ
	p["scar"] = (not female and not child and rng.randf() < 0.05)
	# 表情のくせ
	var moods: Array = ["neutral", "neutral", "gentle", "stern", "calm", "cheerful", "worried", "sharp"]
	if elder:
		moods = ["gentle", "calm", "calm", "stern", "neutral"]
	elif child:
		moods = ["neutral", "cheerful", "cheerful", "gentle", "worried"]
	p["mood"] = moods[rng.randi() % moods.size()]
	# 小物
	p["glasses"] = modern and not child and rng.randf() < (0.3 if elder else 0.12)
	p["eyepatch"] = not female and not child and not p["glasses"] and rng.randf() < 0.015
	p["_seed"] = seed
	return p


static func _q(v: float) -> float:
	return clampf(snappedf(v, 0.5), -1.0, 1.0)


static func _skeleton(root: Node) -> Skeleton3D:
	var s := root.get_node_or_null("%GeneralSkeleton")
	if s is Skeleton3D:
		return s
	var a := root.find_children("*", "Skeleton3D", true, false)
	return a[0] if a.size() > 0 else null


static func _find_mesh(sk: Node, n: String) -> MeshInstance3D:
	var c := sk.get_node_or_null(n)
	if c is MeshInstance3D:
		return c
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", true, false):
		if mi.name == n:
			return mi
	return null


# ---------------------------------------------------------------- face geometry

const K_SKIN := 0
const K_BROW := 1
const K_EYE := 2
const K_IRIS := 3
const K_MOUTH := 4
const K_OTHER := 5


static func _kind(mat_name: String) -> int:
	if "Face_00_SKIN" in mat_name or mat_name.ends_with("_SKIN"):
		return K_SKIN
	if "FaceBrow" in mat_name:
		return K_BROW
	if "EyeIris" in mat_name or "EyeHighlight" in mat_name:
		return K_IRIS
	if "EyeWhite" in mat_name or "FaceEyeline" in mat_name or "FaceEyelash" in mat_name or "EyeExtra" in mat_name:
		return K_EYE
	if "FaceMouth" in mat_name:
		return K_MOUTH
	return K_OTHER


## 素体の顔の目印（頭骨基準）と、首の継ぎ目から離れた度合い（継ぎ目は動かさない）
static func _info(src: ArrayMesh, sk: Skeleton3D) -> Dictionary:
	var key := src.get_instance_id()
	if _info_cache.has(key):
		return _info_cache[key]
	var info := {"ok": false}
	_info_cache[key] = info
	var hb := sk.find_bone("Head")
	if hb < 0 or src.get_surface_count() == 0:
		return info
	var H := sk.get_bone_global_rest(hb).origin
	var kinds: Array = []
	var verts: Array = []
	var names: Array = []
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
			return info   # ヘッドレス（ダミー描画）では頂点が読めない
		var m := src.surface_get_material(si)
		kinds.append(_kind(m.resource_name if m else ""))
		names.append(m.resource_name if m else "")
		verts.append(arr[Mesh.ARRAY_VERTEX])
	# 目: 虹彩の重心（+x 側）、白目の幅
	var ec := Vector3.ZERO
	var en := 0
	var ewmin := INF
	var ewmax := -INF
	var ezmax := -INF
	var mmin := Vector3(INF, INF, INF)
	var mmax := Vector3(-INF, -INF, -INF)
	var bc := Vector3.ZERO
	var bn := 0
	for si in kinds.size():
		var vs: PackedVector3Array = verts[si]
		var k: int = kinds[si]
		for v in vs:
			var d := v - H
			if k == K_IRIS and d.x > 0.0:
				ec += d
				en += 1
			elif k == K_MOUTH:
				mmin = mmin.min(d)
				mmax = mmax.max(d)
			elif k == K_BROW and d.x > 0.0:
				bc += d
				bn += 1
	if en == 0 or mmin.x == INF:
		return info
	ec /= en
	for si in kinds.size():
		if not "EyeWhite" in String(names[si]):
			continue
		for v in (verts[si] as PackedVector3Array):
			var d := v - H
			if d.x > 0.0 and absf(d.y - ec.y) < 0.04:
				ewmin = minf(ewmin, d.x)
				ewmax = maxf(ewmax, d.x)
	var eye_r := maxf((ewmax - ewmin) * 0.5, 0.008) if ewmax > ewmin else 0.016
	var mouth := Vector3(0.0, (mmin.y + mmax.y) * 0.5, mmax.z)
	# 顎先: 正面の中心線上でいちばん低い肌の点
	var chin := 0.0
	var face_w := 0.0
	var nose := -INF
	for si in kinds.size():
		if kinds[si] != K_SKIN:
			continue
		for v in (verts[si] as PackedVector3Array):
			var d := v - H
			if absf(d.x) < 0.01 and d.z > ec.z - 0.01:
				chin = minf(chin, d.y)
			if absf(d.y - mouth.y) < 0.01 and d.z > ec.z - 0.04:
				face_w = maxf(face_w, absf(d.x))
			if absf(d.x) < 0.006 and d.y > mouth.y and d.y < ec.y:
				nose = maxf(nose, d.z)
	# 鼻先の高さ（中心線で最も前に出た点）
	var nose_y := lerpf(mouth.y, ec.y, 0.45)
	for si in kinds.size():
		if kinds[si] != K_SKIN:
			continue
		for v in (verts[si] as PackedVector3Array):
			var d := v - H
			if absf(d.x) < 0.006 and d.y > mouth.y and d.y < ec.y and absf(d.z - nose) < 0.0005:
				nose_y = d.y
	# 首の継ぎ目（肌の開いた縁のうち、目より下で後ろ寄りのもの）
	var seam := PackedVector3Array()
	for si in kinds.size():
		if kinds[si] != K_SKIN:
			continue
		var arr2 := src.surface_get_arrays(si)
		var idx: PackedInt32Array = arr2[Mesh.ARRAY_INDEX]
		var vs2: PackedVector3Array = verts[si]
		var edges := {}
		for t in range(0, idx.size(), 3):
			for e in 3:
				var a: Vector3 = vs2[idx[t + e]].snapped(Vector3(1e-5, 1e-5, 1e-5))
				var b: Vector3 = vs2[idx[t + (e + 1) % 3]].snapped(Vector3(1e-5, 1e-5, 1e-5))
				var ek := [a, b] if (a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z)))) else [b, a]
				var ks := str(ek)
				edges[ks] = [ek, int(edges.get(ks, [null, 0])[1]) + 1]
		for ks in edges:
			var ent: Array = edges[ks]
			if int(ent[1]) == 1:
				for pv: Vector3 in ent[0]:
					var d := pv - H
					if d.y < ec.y - 0.02 and d.z < ec.z - 0.015:
						seam.append(pv)
	# 継ぎ目からの距離による重み（頂点ごと）
	var sw: Array = []
	for si in kinds.size():
		var vs3: PackedVector3Array = verts[si]
		var w := PackedFloat32Array()
		w.resize(vs3.size())
		for i in vs3.size():
			var v := vs3[i]
			var dmin := 1.0
			if v.y - H.y < ec.y + 0.01:
				for s in seam:
					dmin = minf(dmin, v.distance_squared_to(s))
				dmin = sqrt(dmin)
			w[i] = _ss(0.006, 0.03, dmin)
		sw.append(w)
	# 眉の中心
	bc = bc / maxf(bn, 1)
	info = {"ok": true, "H": H, "eye": ec, "eye_r": eye_r, "mouth": mouth, "chin": chin, "nose_y": nose_y,
		"face_w": maxf(face_w, 0.05), "brow": bc, "kinds": kinds, "sw": sw, "seam_n": seam.size()}
	_info_cache[key] = info
	return info


static func _ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 頂点の歪み（休止姿勢・頭骨基準）
static func _warp(v: Vector3, kind: int, w_seam: float, I: Dictionary, P: PackedFloat32Array) -> Vector3:
	if w_seam <= 0.0:
		return v
	var H: Vector3 = I.H
	var E: Vector3 = I.eye
	var er: float = I.eye_r
	var M: Vector3 = I.mouth
	var d := v - H
	var s := 1.0 if d.x >= 0.0 else -1.0
	var ax := absf(d.x)
	var dd := Vector3.ZERO
	var frontk := _ss(E.z - 0.06, E.z - 0.025, d.z)
	# 下顔（目の高さ → 口の高さ）
	var lower := _ss(E.y, M.y, d.y)
	dd.x += d.x * P[0] * 0.11 * lower * frontk                      # jaw: 顎の幅
	if d.y < E.y:
		dd.y += (d.y - E.y) * P[1] * 0.085 * frontk                    # face_len: 顔の長さ
	var gch := exp(-(d.x * d.x) / (0.022 * 0.022)) * _ss(M.y - 0.004, float(I.chin), d.y) * frontk
	dd.y -= P[2] * 0.005 * gch                                       # chin: 顎先
	dd.z += P[2] * 0.003 * gch
	var cy := (E.y + M.y) * 0.5
	var gc := exp(-((ax - E.x * 1.45) * (ax - E.x * 1.45) + (d.y - cy) * (d.y - cy)) / (0.022 * 0.022)) * frontk
	dd.x += s * P[3] * 0.0035 * gc                                   # cheek: 頬のふくらみ
	dd.z += P[3] * 0.002 * gc
	# 目
	var R := er * 1.9
	var ue := ax - E.x
	var ve := d.y - E.y
	var ge := exp(-(ue * ue + ve * ve) / (R * R)) * _ss(E.z - 0.04, E.z - 0.01, d.z)
	if ge > 0.002:
		var gk := ge if kind != K_IRIS else 1.0 * ge
		var dx := P[4] * 0.0035 * ge                                  # eye_gap
		var dy := P[7] * 0.0022 * ge                                  # eye_y
		var sy := P[5] * 0.11 * gk * (0.5 if kind == K_IRIS else 1.0) # eye_h: 縦の大きさ
		var th := P[6] * 0.15 * ge                                    # eye_tilt: つり目(+)／たれ目(-)
		var u2 := ue * cos(th) - ve * (1.0 + sy) * sin(th)
		var v2 := ue * sin(th) + ve * (1.0 + sy) * cos(th)
		dd.x += s * (u2 - ue + dx)
		dd.y += v2 - ve + dy
	# 鼻（高さ）
	var ny: float = I.nose_y
	var gn := exp(-(d.x * d.x) / (0.008 * 0.008) - (d.y - ny) * (d.y - ny) / (0.012 * 0.012)) * frontk
	dd.z += P[12] * 0.0025 * gn
	dd.y += P[12] * 0.0008 * gn
	# 口の幅
	var gm := exp(-(d.x * d.x) / (0.03 * 0.03) - (d.y - M.y) * (d.y - M.y) / (0.014 * 0.014)) * frontk
	dd.x += d.x * P[8] * 0.12 * gm
	# 眉（眉の面だけ）: 高さ・太さ・角度
	if kind == K_BROW:
		var B: Vector3 = I.brow
		var ub := ax - B.x
		var vb := (d.y - B.y) * (1.0 + P[10] * (0.45 if P[10] > 0.0 else 0.3))
		var tb := P[11] * 0.18
		var u3 := ub * cos(tb) - vb * sin(tb)
		var v3 := ub * sin(tb) + vb * cos(tb)
		dd.x += s * (u3 - ub)
		dd.y += (v3 - (d.y - B.y)) + P[9] * 0.0025
	return v + dd * w_seam


static func _sculpt(face: MeshInstance3D, sk: Skeleton3D, p: Dictionary) -> ArrayMesh:
	var src: ArrayMesh = face.get_meta("anime_face_src", face.mesh) as ArrayMesh
	if src == null:
		return null
	var I := _info(src, sk)
	if not bool(I.ok):
		return null
	var P := PackedFloat32Array([float(p.jaw), float(p.face_len), float(p.chin), float(p.cheek), float(p.eye_gap),
		float(p.eye_h), float(p.eye_tilt), float(p.eye_y), float(p.mouth_w), float(p.brow_y), float(p.brow_thick), float(p.brow_angle), float(p.get("nose", 0.0))])
	var ck := "%d|%s" % [src.get_instance_id(), str(P)]
	if _mesh_cache.has(ck):
		return _mesh_cache[ck]
	var H: Vector3 = I.H
	var kinds: Array = I.kinds
	var sws: Array = I.sw
	var out := ArrayMesh.new()
	out.blend_shape_mode = src.blend_shape_mode
	for bi in src.get_blend_shape_count():
		out.add_blend_shape(src.get_blend_shape_name(bi))
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var bsa := src.surface_get_blend_shape_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var k: int = kinds[si]
		var sw: PackedFloat32Array = sws[si]
		var nv := vs.size()
		var nvs := PackedVector3Array()
		nvs.resize(nv)
		var custom := PackedFloat32Array()
		custom.resize(nv * 4)
		for i in nv:
			nvs[i] = _warp(vs[i], k, sw[i], I, P)
			var r := vs[i] - H
			custom[i * 4] = r.x
			custom[i * 4 + 1] = r.y
			custom[i * 4 + 2] = r.z
			custom[i * 4 + 3] = float(k)
		var new_bs: Array = []
		for b in bsa:
			var barr: Array = (b as Array).duplicate()
			var bv: PackedVector3Array = barr[Mesh.ARRAY_VERTEX]
			for i in nv:
				if bv[i] == vs[i]:
					bv[i] = nvs[i]
				else:
					bv[i] = _warp(bv[i], k, sw[i], I, P)
			barr[Mesh.ARRAY_VERTEX] = bv
			new_bs.append(barr)
		arr[Mesh.ARRAY_VERTEX] = nvs
		arr[Mesh.ARRAY_CUSTOM0] = custom
		var flags := (src.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, new_bs, {}, flags)
		out.surface_set_material(si, src.surface_get_material(si))
		out.surface_set_name(si, src.surface_get_name(si))
	out.resource_name = src.resource_name
	_mesh_cache[ck] = out
	return out


# ---------------------------------------------------------------- face materials

static func _apply_face(face: MeshInstance3D, sk: Skeleton3D, p: Dictionary) -> void:
	if not face.has_meta("anime_face_src"):
		face.set_meta("anime_face_src", face.mesh)
	var src: ArrayMesh = face.get_meta("anime_face_src") as ArrayMesh
	var sculpted := _sculpt(face, sk, p)
	if sculpted:
		face.mesh = sculpted
	var I := _info(src, sk)
	var skin_c: Color = SKIN.get(String(p.skin), SKIN["light"])
	var elder := String(p.age) == "elder"
	var hair_c := _hair_color(p)
	var brow_c := hair_c.lerp(Color(0.3, 0.2, 0.17), 0.25) if int(p.hair_gray) == 0 else hair_c.darkened(0.15)
	var lash_c := Color(0.16, 0.1, 0.1).lerp(Color(0.05, 0.035, 0.04), float(p.lash))
	if bool(p.female):
		lash_c = lash_c.darkened(0.2)
	for si in face.mesh.get_surface_count():
		var m := face.mesh.surface_get_material(si)
		if not (m is ShaderMaterial):
			continue
		var k := _kind(m.resource_name)
		var mm := (m as ShaderMaterial).duplicate() as ShaderMaterial
		match k:
			K_SKIN:
				_tint(mm, skin_c)
				if sculpted and bool(I.ok):
					var ov := _overlay(I, p, hair_c)
					ov.next_pass = mm.next_pass
					mm.next_pass = ov
			K_BROW:
				mm.set_shader_parameter("_Color", brow_c)
				mm.set_shader_parameter("_ShadeColor", brow_c.darkened(0.2))
			K_IRIS:
				if "Highlight" in m.resource_name:
					mm.set_shader_parameter("_Color", Color(1, 1, 1, float(p.highlight)))
				else:
					var ic: Color = p.iris
					mm.set_shader_parameter("_MainTex", _iris_tex((m as ShaderMaterial).get_shader_parameter("_MainTex")))
					mm.set_shader_parameter("_ShadeTexture", mm.get_shader_parameter("_MainTex"))
					mm.set_shader_parameter("_Color", ic * 1.9)
					mm.set_shader_parameter("_ShadeColor", ic * 1.6)
			K_EYE:
				if "Eyeline" in m.resource_name or "Eyelash" in m.resource_name:
					mm.set_shader_parameter("_Color", lash_c)
					mm.set_shader_parameter("_ShadeColor", lash_c)
				elif "EyeWhite" in m.resource_name and elder:
					mm.set_shader_parameter("_Color", Color(0.97, 0.95, 0.9))
			K_MOUTH:
				_tint(mm, skin_c.lerp(Color.WHITE, 0.4))
		face.set_surface_override_material(si, mm)
	# 表情のくせ（ブレンドシェイプを少しだけ）
	var mood: Dictionary = MOODS.get(String(p.mood), {})
	for bi in face.mesh.get_blend_shape_count():
		var bn := String(face.mesh.get_blend_shape_name(bi))
		var suf := bn.get_slice("Fcl_", 1)
		face.set_blend_shape_value(bi, float(mood.get(suf, 0.0)))


static func _tint(mm: ShaderMaterial, c: Color) -> void:
	var a: Color = mm.get_shader_parameter("_Color")
	var b: Color = mm.get_shader_parameter("_ShadeColor")
	mm.set_shader_parameter("_Color", Color(a.r * c.r, a.g * c.g, a.b * c.b, a.a))
	mm.set_shader_parameter("_ShadeColor", Color(b.r * c.r, b.g * c.g, b.b * c.b, b.a))


## 虹彩のテクスチャを明るさだけにする（色は _Color で付ける）
static func _iris_tex(t: Texture2D) -> Texture2D:
	if t == null:
		return null
	var key := "iris|%d" % t.get_instance_id()
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := t.get_image()
	if img == null:
		return t
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.adjust_bcs(1.0, 1.0, 0.0)
	img.generate_mipmaps()
	var nt := ImageTexture.create_from_image(img)
	_tex_cache[key] = nt
	return nt


static func _overlay(I: Dictionary, p: Dictionary, hair_c: Color) -> ShaderMaterial:
	if _overlay_shader == null:
		_overlay_shader = load(DIR + "face_overlay.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _overlay_shader
	m.render_priority = -1
	var E: Vector3 = I.eye
	var M: Vector3 = I.mouth
	m.set_shader_parameter("eye", Vector3(E.x, E.y, E.z))
	m.set_shader_parameter("eye_r", float(I.eye_r))
	m.set_shader_parameter("mouth", Vector2(M.y, M.z))
	m.set_shader_parameter("chin_y", float(I.chin))
	m.set_shader_parameter("nose_y", float(I.nose_y))
	m.set_shader_parameter("face_w", float(I.face_w))
	m.set_shader_parameter("beard", BEARDS.find(String(p.beard)))
	m.set_shader_parameter("beard_col", hair_c)
	m.set_shader_parameter("stubble", float(p.stubble))
	m.set_shader_parameter("wrinkles", float(p.wrinkles))
	var sk: Color = SKIN.get(String(p.skin), SKIN["light"])
	m.set_shader_parameter("line_col", Color(0.62, 0.36, 0.3) * sk)
	m.set_shader_parameter("blush", float(p.blush))
	m.set_shader_parameter("blush_lines", float(p.blush_lines))
	m.set_shader_parameter("blush_col", Color(1.0, 0.42, 0.42) if not String(p.skin) in ["tan", "deep"] else Color(0.9, 0.36, 0.3))
	m.set_shader_parameter("freckles", float(p.freckles))
	m.set_shader_parameter("lid", float(p.get("lid", 0.0)))
	m.set_shader_parameter("lid_col", Color(0.5, 0.28, 0.24) * sk)
	m.set_shader_parameter("beni", float(p.get("beni", 0.0)))
	var F := E.x
	var mole := int(p.mole)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p.get("_seed", 0)) * 31 + 5
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	if mole > 0:
		var mp := Vector2.ZERO
		match mole:
			1: mp = Vector2(side * (E.x + F * 0.45), E.y - F * 0.5)            # 泣きぼくろ
			2: mp = Vector2(side * F * 0.55, M.y - F * 0.12)                   # 口元
			3: mp = Vector2(side * F * 0.95, (E.y + M.y) * 0.5)                # 頬
			_: mp = Vector2(side * F * 0.25, float(I.chin) + F * 0.35)         # 顎
		m.set_shader_parameter("mole", Vector4(mp.x, mp.y, F * 0.028, 1.0))
	if bool(p.scar):
		var a := Vector2(side * (E.x + F * 0.2), E.y - F * 0.35)
		var b := Vector2(side * (E.x + F * 0.75), E.y - F * 1.0)
		m.set_shader_parameter("scar", Vector4(a.x, a.y, b.x, b.y))
		m.set_shader_parameter("scar_on", 1.0)
	return m


# ---------------------------------------------------------------- body / hair

static func _apply_body_skin(sk: Skeleton3D, p: Dictionary) -> void:
	var c: Color = SKIN.get(String(p.skin), SKIN["light"])
	var has_anime_hair := sk.get_node_or_null("AnimeHair") != null
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", false, false):
		if mi.name == "Face" or mi.mesh == null or mi.material_override != null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if has_anime_hair and m and "HairBack" in m.resource_name:
				# 和装の体に差し替えた後も元の後ろ髪が残っていることがあるので隠す
				mi.set_surface_override_material(si, _hide_mat())
				continue
			if mi.get_surface_override_material(si) != null:
				continue
			if m is ShaderMaterial and "SKIN" in m.resource_name:
				var mm := (m as ShaderMaterial).duplicate() as ShaderMaterial
				_tint(mm, c)
				mi.set_surface_override_material(si, mm)


static var _hide: ShaderMaterial


static func _hide_mat() -> ShaderMaterial:
	if _hide == null:
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvoid fragment() { discard; }\n"
		_hide = ShaderMaterial.new()
		_hide.shader = sh
	return _hide


static func _hair_color(p: Dictionary) -> Color:
	var g := int(p.hair_gray)
	if g == 2:
		return Color(0.86, 0.86, 0.88)
	if g == 1:
		return Color(0.5, 0.5, 0.53)
	var t: Color = p.hair_tint
	return Color(0.09 * t.r, 0.085 * t.g, 0.1 * t.b)


## 白髪テクスチャ（暗い髪テクスチャを明るく・灰色に）
static func _gray_tex(t: Texture2D, level: int) -> Texture2D:
	if t == null:
		return null
	var key := "gray%d|%d" % [level, t.get_instance_id()]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := t.get_image()
	if img == null:
		return t
	img = img.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	# 明るさ（平均）を目標へ
	var small := img.duplicate() as Image
	small.resize(8, 8, Image.INTERPOLATE_BILINEAR)
	var avg := 0.0
	for y in 8:
		for x in 8:
			avg += small.get_pixel(x, y).get_luminance()
	avg = maxf(avg / 64.0, 0.02)
	var target := 0.78 if level == 2 else 0.42
	img.adjust_bcs(target / avg, 0.85 if level == 2 else 1.1, 0.0)
	img.generate_mipmaps()
	var nt := ImageTexture.create_from_image(img)
	_tex_cache[key] = nt
	return nt


static func _apply_hair(sk: Skeleton3D, p: Dictionary) -> void:
	var g := int(p.hair_gray)
	var tint: Color = p.hair_tint
	var skin_c: Color = SKIN.get(String(p.skin), SKIN["light"])
	var ah := sk.get_node_or_null("AnimeHair") as MeshInstance3D
	if ah and ah.mesh:
		var names: Array = ah.mesh.get_meta("surf_mats", [])
		for si in ah.mesh.get_surface_count():
			var m := ah.get_active_material(si) as ShaderMaterial
			if m == null:
				continue
			var n := String(names[si]) if si < names.size() else "hair"
			var mm := m.duplicate() as ShaderMaterial
			var ol: ShaderMaterial = (m.next_pass as ShaderMaterial).duplicate() as ShaderMaterial if m.next_pass is ShaderMaterial else null
			if n.begins_with("hair"):
				var c := Color(1, 1, 1) if g > 0 else tint
				if n == "hair_buzz":
					c = c * 1.5
				for t in [mm, ol]:
					if t == null:
						continue
					var tm := t as ShaderMaterial
					if g > 0:
						tm.set_shader_parameter("_MainTex", _gray_tex(m.get_shader_parameter("_MainTex"), g))
						tm.set_shader_parameter("_ShadeTexture", _gray_tex(m.get_shader_parameter("_ShadeTexture"), g))
						tm.set_shader_parameter("_OutlineColor", Color(0.32, 0.3, 0.34) if g == 2 else Color(0.14, 0.13, 0.16))
						tm.set_shader_parameter("_RimColor", Color(0.05, 0.05, 0.08))
					tm.set_shader_parameter("_Color", c)
					tm.set_shader_parameter("_ShadeColor", c * (Color(0.8, 0.8, 0.92) if g > 0 else Color(1, 1, 1)))
			elif n.begins_with("skin"):
				_tint(mm, skin_c)
			if ol:
				mm.next_pass = ol
			ah.set_surface_override_material(si, mm)
	# 元の VRoid 髪（AnimeHair を使わない場合）
	var vh := _find_mesh(sk, "Hair001")
	if vh and vh.visible and vh.mesh and g > 0:
		for si in vh.mesh.get_surface_count():
			var m2 := vh.get_active_material(si) as ShaderMaterial
			if m2 == null:
				continue
			var mm2 := m2.duplicate() as ShaderMaterial
			mm2.set_shader_parameter("_MainTex", _gray_tex(m2.get_shader_parameter("_MainTex"), g))
			mm2.set_shader_parameter("_ShadeTexture", _gray_tex(m2.get_shader_parameter("_ShadeTexture"), g))
			mm2.set_shader_parameter("_Color", Color.WHITE)
			mm2.set_shader_parameter("_ShadeColor", Color(0.8, 0.8, 0.9))
			vh.set_surface_override_material(si, mm2)


# ---------------------------------------------------------------- bones

## アニメーションの後に骨へ掛ける補正（拡縮・猫背・腰の高さ）
class Mod extends SkeletonModifier3D:
	var bones := PackedInt32Array()
	var scales: Array[Vector3] = []
	var rots: Array[Quaternion] = []
	var hips := -1
	var hips_drop := 0.0

	func _process_modification_with_delta(_delta: float) -> void:
		var s := get_skeleton()
		if s == null:
			return
		for i in bones.size():
			var b := bones[i]
			if rots[i] != Quaternion.IDENTITY:
				s.set_bone_pose_rotation(b, s.get_bone_pose_rotation(b) * rots[i])
			if scales[i] != Vector3.ONE:
				s.set_bone_pose_scale(b, scales[i])
		if hips >= 0 and hips_drop != 0.0:
			var hp := s.get_bone_pose_position(hips)
			s.set_bone_pose_position(hips, hp - Vector3(0, hips_drop, 0))


static func _apply_bones(sk: Skeleton3D, p: Dictionary) -> void:
	var old := sk.get_node_or_null(MOD_NAME)
	if old:
		sk.remove_child(old)
		old.free()
	var h := float(p.height)
	if not sk.has_meta("anime_face_scale0"):
		sk.set_meta("anime_face_scale0", sk.scale)
	var s0: Vector3 = sk.get_meta("anime_face_scale0")
	sk.scale = s0 * h
	var mod := Mod.new()
	mod.name = MOD_NAME
	var child := String(p.age) == "child"
	var add := func(bname: String, scl: Vector3, pitch_deg: float) -> void:
		var bi := sk.find_bone(bname)
		if bi < 0:
			return
		mod.bones.append(bi)
		mod.scales.append(scl)
		var q := Quaternion.IDENTITY
		if pitch_deg != 0.0:
			var rq := sk.get_bone_global_rest(bi).basis.get_rotation_quaternion()
			q = rq.inverse() * Quaternion(Vector3.RIGHT, deg_to_rad(pitch_deg)) * rq
		mod.rots.append(q)
	var hs := float(p.head)
	var st := float(p.stoop)
	add.call("Head", Vector3.ONE * hs, -st * 0.25)
	if st > 0.0:
		add.call("Spine", Vector3.ONE, st * 0.4)
		add.call("Chest", Vector3.ONE, st * 0.35)
		add.call("UpperChest", Vector3.ONE, st * 0.3)
		add.call("Neck", Vector3.ONE, -st * 0.45)
		add.call("LeftUpperLeg", Vector3.ONE, -st * 0.25)
		add.call("RightUpperLeg", Vector3.ONE, -st * 0.25)
		add.call("LeftLowerLeg", Vector3.ONE, st * 0.4)
		add.call("RightLowerLeg", Vector3.ONE, st * 0.4)
	var iris := float(p.iris_scale) / hs if hs > 0.0 else 1.0
	add.call("LeftEye", Vector3.ONE * float(p.iris_scale), 0.0)
	add.call("RightEye", Vector3.ONE * float(p.iris_scale), 0.0)
	if child:
		var leg := 0.9
		add.call("LeftUpperLeg", Vector3.ONE * leg, 0.0)
		add.call("RightUpperLeg", Vector3.ONE * leg, 0.0)
		add.call("LeftUpperArm", Vector3.ONE * 0.93, 0.0)
		add.call("RightUpperArm", Vector3.ONE * 0.93, 0.0)
		var hb := sk.find_bone("Hips")
		var fb := sk.find_bone("LeftFoot")
		var ub := sk.find_bone("LeftUpperLeg")
		if hb >= 0 and fb >= 0 and ub >= 0:
			var legl := sk.get_bone_global_rest(ub).origin.y - sk.get_bone_global_rest(fb).origin.y
			mod.hips = hb
			mod.hips_drop = legl * (1.0 - leg)
	elif st > 0.0:
		var hb2 := sk.find_bone("Hips")
		if hb2 >= 0:
			mod.hips = hb2
			mod.hips_drop = 0.012 * st / 12.0
	sk.add_child(mod)
	p["_iris_rel"] = iris


# ---------------------------------------------------------------- accessories

static func _toon_mat(c: Color, outline := true, width := 0.06) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://addons/Godot-MToon-Shader/mtoon.gdshader")
	var pr := {"_Color": c, "_ShadeColor": c * Color(0.7, 0.68, 0.8), "_ShadeToony": 0.9, "_ShadeShift": 0.0,
		"_IndirectLightIntensity": 0.2, "_OutlineWidthMode": 1.0, "_OutlineWidth": width,
		"_OutlineColor": c * Color(0.3, 0.28, 0.32), "_OutlineColorMode": 0.0, "_OutlineLightingMix": 1.0}
	for k in pr:
		m.set_shader_parameter(k, pr[k])
	if outline:
		var ol := ShaderMaterial.new()
		ol.shader = load("res://addons/Godot-MToon-Shader/mtoon_outline.gdshader")
		for k in pr:
			ol.set_shader_parameter(k, pr[k])
		m.next_pass = ol
	return m


static func _apply_accessories(sk: Skeleton3D, face: MeshInstance3D, p: Dictionary) -> void:
	var old := sk.get_node_or_null(ACC_NAME)
	if old:
		sk.remove_child(old)
		old.free()
	var want := bool(p.glasses) or bool(p.eyepatch) or bool(p.long_beard)
	if not want or face == null:
		return
	var src: ArrayMesh = face.get_meta("anime_face_src", face.mesh) as ArrayMesh
	var I := _info(src, sk) if src else {"ok": false}
	if not bool(I.get("ok", false)):
		return
	var hb := sk.find_bone("Head")
	var ba := BoneAttachment3D.new()
	ba.name = ACC_NAME
	sk.add_child(ba)
	ba.bone_name = "Head"
	ba.bone_idx = hb
	# 子は「休止姿勢の骨格空間・頭骨原点基準」で置けるようにする
	var space := Node3D.new()
	var rest := sk.get_bone_global_rest(hb)
	space.transform = Transform3D(rest.basis.inverse(), Vector3.ZERO)
	ba.add_child(space)
	var E: Vector3 = I.eye
	var er: float = I.eye_r
	# 歪み後の目の位置
	var P := PackedFloat32Array([float(p.jaw), float(p.face_len), float(p.chin), float(p.cheek), float(p.eye_gap),
		float(p.eye_h), float(p.eye_tilt), float(p.eye_y), float(p.mouth_w), float(p.brow_y), float(p.brow_thick), float(p.brow_angle), float(p.get("nose", 0.0))])
	var H: Vector3 = I.H
	var Ew := _warp(H + E, K_EYE, 1.0, I, P) - H
	var front_z := E.z + er * 0.9
	if bool(p.glasses):
		var frame := _toon_mat(Color(0.12, 0.1, 0.1) if bool(p.female) or int(p.get("_seed", 0)) % 3 != 0 else Color(0.62, 0.48, 0.24), true, 0.04)
		for sd in [-1.0, 1.0]:
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = er * 1.18
			tm.outer_radius = er * 1.18 + 0.0016
			tm.rings = 32
			tm.ring_segments = 6
			ring.mesh = tm
			ring.material_override = frame
			ring.rotation_degrees = Vector3(90, 0, 0)
			ring.position = Vector3(sd * Ew.x, Ew.y - er * 0.05, front_z + 0.004)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			space.add_child(ring)
			# つる（耳へ）
			var arm := MeshInstance3D.new()
			var bm := BoxMesh.new()
			var fw: float = float(I.face_w)
			var len := front_z - (E.z - 0.07)
			bm.size = Vector3(0.0018, 0.0018, len)
			arm.mesh = bm
			arm.material_override = frame
			arm.position = Vector3(sd * (fw * 0.98), Ew.y, front_z - len * 0.5)
			arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			space.add_child(arm)
			var hinge := MeshInstance3D.new()
			var hm := BoxMesh.new()
			hm.size = Vector3(absf(fw * 0.98 - (Ew.x + er * 1.18)) + 0.002, 0.0018, 0.0018)
			hinge.mesh = hm
			hinge.material_override = frame
			hinge.position = Vector3(sd * (Ew.x + er * 1.18 + fw * 0.98) * 0.5, Ew.y, front_z + 0.003)
			space.add_child(hinge)
		var bridge := MeshInstance3D.new()
		var brm := BoxMesh.new()
		brm.size = Vector3(maxf(Ew.x * 2.0 - er * 2.36, 0.004), 0.0016, 0.0016)
		bridge.mesh = brm
		bridge.material_override = frame
		bridge.position = Vector3(0, Ew.y + er * 0.25, front_z + 0.006)
		space.add_child(bridge)
	if bool(p.eyepatch):
		var sd2 := 1.0 if int(p.get("_seed", 0)) % 2 == 0 else -1.0
		var patch := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = er * 1.45
		sm.height = er * 2.6
		sm.radial_segments = 24
		sm.rings = 8
		patch.mesh = sm
		patch.scale = Vector3(1.0, 1.0, 0.25)
		patch.material_override = _toon_mat(Color(0.08, 0.07, 0.08), true, 0.05)
		patch.position = Vector3(sd2 * Ew.x, Ew.y, front_z - 0.002)
		space.add_child(patch)
		var strap := MeshInstance3D.new()
		var tm2 := TorusMesh.new()
		var fw2: float = float(I.face_w) * 1.12
		tm2.inner_radius = fw2
		tm2.outer_radius = fw2 + 0.0025
		tm2.rings = 48
		tm2.ring_segments = 4
		strap.mesh = tm2
		strap.material_override = patch.material_override
		strap.position = Vector3(0, Ew.y + 0.01, (E.z - 0.06 + front_z) * 0.5)
		strap.rotation_degrees = Vector3(0, 0, sd2 * 22.0)
		strap.scale = Vector3(1.0, 1.0, (front_z - E.z + 0.1) / (2.0 * fw2))
		space.add_child(strap)
	if bool(p.long_beard):
		var bmesh := _long_beard_mesh(float(I.chin), float(I.mouth.z), E.x, float(p.get("_seed", 0)))
		var bmi := MeshInstance3D.new()
		bmi.mesh = bmesh
		var hc := _hair_color(p)
		bmi.material_override = _toon_mat(hc, true, 0.05)
		space.add_child(bmi)


## 仙人の顎髭（顎先から垂れる、先の細い房）
static func _long_beard_mesh(chin_y: float, mouth_z: float, F: float, sd: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sd) * 13 + 3
	var length := F * rng.randf_range(1.6, 2.6)
	var top_y := chin_y + F * 0.3
	var z0 := mouth_z - F * 0.32
	var w0 := F * 0.5
	var rings := 8
	var seg := 12
	var pts: Array = []
	for r in rings + 1:
		var t := float(r) / rings
		var y := top_y - t * length
		var z := z0 - t * F * 0.1 + t * t * F * 0.35
		var w := w0 * (1.0 - t * 0.8) * (1.0 + 0.3 * sin(t * PI))
		var d := w * 0.65
		var ring: Array = []
		for s in seg:
			var a := TAU * s / seg
			ring.append(Vector3(cos(a) * w, y, z + sin(a) * d))
		pts.append(ring)
	for r in rings:
		for s in seg:
			var a0: Vector3 = pts[r][s]
			var a1: Vector3 = pts[r][(s + 1) % seg]
			var b0: Vector3 = pts[r + 1][s]
			var b1: Vector3 = pts[r + 1][(s + 1) % seg]
			for v in [a0, b0, a1, a1, b0, b1]:
				st.add_vertex(v)
	var tip := Vector3(0, top_y - length - F * 0.35, z0 + F * 0.3)
	for s in seg:
		st.add_vertex(pts[rings][s])
		st.add_vertex(tip)
		st.add_vertex(pts[rings][(s + 1) % seg])
	st.generate_normals()
	return st.commit()
