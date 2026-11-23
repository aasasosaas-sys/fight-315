class_name AnimeHair
extends RefCounted
## 時代別のアニメ調ヘアスタイル（黒髪）を VRoid（VRM）モデルへ付け替える。
## 元の VRoid 髪（Hair* メッシュと Body 内の HairBack 面）を隠し、
## assets/characters/hair/<style>.glb の髪メッシュ（モデル毎に頭へ合わせて生成済み）を
## 頭・首・胸・腰の骨へスキニングして MToon（輪郭線つき）で描く。
##   AnimeHair.apply(vrm_root, "chonmage")
## 生成元: Blender の手続き生成スクリプト（tools/hair/）。

const DIR := "res://assets/characters/hair/"
const NODE_NAME := "AnimeHair"

## スタイル名 → 説明（時代 / 性別）
const STYLES := {
	"chonmage": "江戸・武士/町人 男 月代＋丁髷",
	"chasen": "戦国 男 茶筅髷",
	"court_bun": "古代・平安 男 髻（烏帽子の下）",
	"zangiri": "明治以降 男 散切り（短髪）",
	"buzz": "近代 男 軍隊式の丸刈り",
	"suberakashi": "平安 女 垂髪（膝までの黒髪）",
	"shimada": "江戸 女 島田髷（櫛・簪）",
	"sokuhatsu": "明治・大正 女 束髪（庇髪＋リボン）",
	"bob": "昭和 女 おかっぱ/ボブ",
}

## 生成に使ったモデルの顔 AABB（頭骨基準）: 未知のモデルは最も近いものを拡縮して流用
const FACE_SIG := {
	"HairSample_Male": [Vector3(-0.111867, -0.051909, -0.028099), Vector3(0.223735, 0.246976, 0.149492)],
	"Sakurada_Fumiriya": [Vector3(-0.10773, -0.049997, -0.027065), Vector3(0.215492, 0.237877, 0.143986)],
	"HairSample_Female": [Vector3(-0.108238, -0.033172, -0.033235), Vector3(0.216477, 0.232133, 0.147813)],
	"Sendagaya_Shibu": [Vector3(-0.106963, -0.033172, -0.032223), Vector3(0.213925, 0.232133, 0.146802)],
	"Sendagaya_Shino": [Vector3(-0.108729, -0.033322, -0.033385), Vector3(0.217458, 0.233186, 0.148483)],
}

## 装身具の色（glb の材質名 → 色）
const ACC_COLORS := {
	"acc_white": Color(0.96, 0.95, 0.92),     # 元結（紙縒り）
	"acc_red": Color(0.78, 0.12, 0.16),       # 赤（鹿の子・紐）
	"acc_gold": Color(0.93, 0.74, 0.32),      # 金の簪
	"acc_comb": Color(0.36, 0.17, 0.09),      # 鼈甲／漆の櫛
	"acc_coral": Color(0.95, 0.42, 0.45),     # 珊瑚玉
	"acc_ribbon": Color(0.55, 0.13, 0.25),    # 大正のリボン（海老茶）
	"acc_purple": Color(0.42, 0.22, 0.55),
	"acc_black": Color(0.08, 0.07, 0.09),
}

static var _scene_cache := {}
static var _mat_cache := {}
static var _mesh_cache := {}
static var _hide_mat: ShaderMaterial


## vrm_root に style の髪を付ける（"" で元の髪へ戻す）。追加したメッシュを返す。
static func apply(vrm_root: Node3D, style: String, tint := Color(1, 1, 1)) -> MeshInstance3D:
	var sk := _skeleton(vrm_root)
	if sk == null:
		push_warning("AnimeHair: skeleton not found")
		return null
	var old := sk.get_node_or_null(NODE_NAME)
	if old:
		sk.remove_child(old)
		old.queue_free()
	_hide_original(vrm_root, style != "")
	if style == "":
		return null
	if not STYLES.has(style):
		push_warning("AnimeHair: unknown style " + style)
		return null
	var face := _face(vrm_root)
	var key := vrm_root.scene_file_path.get_file().get_basename()
	var hb := sk.find_bone("Head")
	var head_o := sk.get_bone_global_rest(hb).origin
	var fit := _fit(key, face, head_o)
	var mesh := _skinned_mesh(style, sk, fit)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = NODE_NAME
	mi.mesh = mesh
	mi.skin = _make_skin(sk)
	sk.add_child(mi)
	mi.skeleton = mi.get_path_to(sk)
	var skin_col := _skin_color(face)
	for si in mesh.get_surface_count():
		var mn := String(mesh.get_meta("surf_mats")[si])
		mi.set_surface_override_material(si, _material(mn, tint, skin_col))
	return mi


static func _skeleton(root: Node) -> Skeleton3D:
	var s := root.get_node_or_null("%GeneralSkeleton")
	if s is Skeleton3D:
		return s
	var a := root.find_children("*", "Skeleton3D", true, false)
	return a[0] if a.size() > 0 else null


static func _face(root: Node) -> MeshInstance3D:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "Face":
			return mi
	return null


## 元の髪を隠す（show=false で戻す）
static func _hide_original(root: Node, hide: bool) -> void:
	if _hide_mat == null:
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nvoid fragment() { discard; }\n"
		_hide_mat = ShaderMaterial.new()
		_hide_mat.shader = sh
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.name == NODE_NAME:
			continue
		if mi.name.begins_with("Hair"):
			mi.visible = not hide
			continue
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(si)
			if m and "HairBack" in m.resource_name:
				mi.set_surface_override_material(si, _hide_mat if hide else null)
	# 髪の揺れ骨は不要（隠したメッシュ用）
	var sec := root.get_node_or_null("secondary")
	if hide and sec and "spring_bones" in sec:
		var keep: Array = []
		for sb in sec.spring_bones:
			if sb and not ("Hair" in ",".join(sb.joint_nodes)):
				keep.append(sb)
		if keep.size() != sec.spring_bones.size():
			sec.spring_bones.assign(keep)


## どの生成メッシュをどう拡縮して使うか: {key, k, anchor_src, anchor_dst, head}
static func _fit(key: String, face: MeshInstance3D, head_o: Vector3) -> Dictionary:
	var fit := {"key": key, "k": 1.0, "src": Vector3.ZERO, "dst": Vector3.ZERO, "head": head_o}
	if FACE_SIG.has(key) or face == null:
		if not FACE_SIG.has(key):
			fit.key = "HairSample_Female"
		return fit
	var ab := face.get_aabb()
	var p := ab.position - head_o
	var best := ""
	var bd := INF
	for k in FACE_SIG:
		var d: float = (FACE_SIG[k][0] - p).length() + (FACE_SIG[k][1] - ab.size).length()
		if d < bd:
			bd = d
			best = k
	var sp: Vector3 = FACE_SIG[best][0]
	var ss: Vector3 = FACE_SIG[best][1]
	fit.key = best
	fit.k = (ab.size.x / ss.x + ab.size.y / ss.y + ab.size.z / ss.z) / 3.0
	fit.src = sp + ss * Vector3(0.5, 1.0, 0.5)
	fit.dst = p + ab.size * Vector3(0.5, 1.0, 0.5)
	return fit


static func _src_mesh(style: String, key: String) -> Mesh:
	var path := DIR + style + ".glb"
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path)
	var ps: PackedScene = _scene_cache[path]
	if ps == null:
		return null
	var inst := ps.instantiate()
	var node := inst.find_child(key, true, false)
	if not (node is MeshInstance3D):
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			node = c
			break
	var m: Mesh = (node as MeshInstance3D).mesh if node else null
	inst.free()
	return m


## 骨鎖（頭→腰）: スキニング先の骨
const CHAIN := ["Head", "Neck", "UpperChest", "Chest", "Spine", "Hips"]


static func _chain(sk: Skeleton3D) -> Array:
	var out: Array = []
	for n in CHAIN:
		var i := sk.find_bone(n)
		if i >= 0:
			out.append([n, sk.get_bone_global_rest(i).origin.y])
	return out


static func _make_skin(sk: Skeleton3D) -> Skin:
	var skin := Skin.new()
	for c in _chain(sk):
		var i := sk.find_bone(c[0])
		skin.add_named_bind(c[0], sk.get_bone_global_rest(i).affine_inverse())
	return skin


static func _skinned_mesh(style: String, sk: Skeleton3D, fit: Dictionary) -> ArrayMesh:
	var ck := "%s|%s|%s|%s|%s" % [style, fit.key, fit.k, fit.dst, fit.head]
	if _mesh_cache.has(ck):
		return _mesh_cache[ck]
	var src := _src_mesh(style, fit.key)
	if src == null:
		push_warning("AnimeHair: missing mesh for " + style)
		return null
	var chain := _chain(sk)
	var head_o: Vector3 = fit.head
	var out := ArrayMesh.new()
	var names: Array = []
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nv := verts.size()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		bones.resize(nv * 4)
		weights.resize(nv * 4)
		for vi in nv:
			var v: Vector3 = verts[vi]
			if fit.k != 1.0 or fit.dst != fit.src:
				v = fit.dst + (v - fit.src) * fit.k
			v += head_o
			verts[vi] = v
			var w := _weights(v, chain, head_o)
			bones[vi * 4] = w[0]
			bones[vi * 4 + 1] = w[1]
			weights[vi * 4] = w[2]
			weights[vi * 4 + 1] = 1.0 - w[2]
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m := src.surface_get_material(si)
		names.append(m.resource_name if m else "hair")
	out.set_meta("surf_mats", names)
	_mesh_cache[ck] = out
	return out


## 高さで骨鎖を線形補間: [骨0, 骨1, 骨0の重み]
static func _weights(v: Vector3, chain: Array, head_o: Vector3) -> Array:
	var top: float = head_o.y - 0.03
	if v.y >= top or chain.size() < 2:
		return [0, 0, 1.0]
	var prev_y := top
	for i in range(1, chain.size()):
		var y: float = chain[i][1]
		if v.y >= y:
			var a := (v.y - y) / maxf(prev_y - y, 0.001)
			return [i - 1, i, a]
		prev_y = y
	return [chain.size() - 1, chain.size() - 1, 1.0]


## 顔テクスチャの額付近から肌色を拾う（月代用）
static func _skin_color(face: MeshInstance3D) -> Color:
	var fallback := Color(1.0, 0.86, 0.78)
	if face == null or face.mesh == null:
		return fallback
	for si in face.mesh.get_surface_count():
		var m := face.mesh.surface_get_material(si)
		if not (m is ShaderMaterial) or not ("Face_00_SKIN" in m.resource_name):
			continue
		var tex: Texture2D = (m as ShaderMaterial).get_shader_parameter("_MainTex")
		if tex == null:
			return fallback
		var img := tex.get_image()
		if img == null:
			return fallback
		if img.is_compressed():
			img.decompress()
		var arr := face.mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var ab := face.get_aabb()
		var target := ab.position + ab.size * Vector3(0.5, 0.82, 1.0)
		var bi := 0
		var bd := INF
		for i in vs.size():
			var d := vs[i].distance_squared_to(target)
			if d < bd:
				bd = d
				bi = i
		var uv := uvs[bi]
		var x := clampi(int(uv.x * img.get_width()), 0, img.get_width() - 1)
		var y := clampi(int(uv.y * img.get_height()), 0, img.get_height() - 1)
		var c := img.get_pixel(x, y)
		var col: Color = (m as ShaderMaterial).get_shader_parameter("_Color")
		return Color(c.r * col.r, c.g * col.g, c.b * col.b)
	return fallback


static func _material(name: String, tint: Color, skin: Color) -> ShaderMaterial:
	var ck := "%s|%s|%s" % [name, tint, skin]
	if _mat_cache.has(ck):
		return _mat_cache[ck]
	var m := ShaderMaterial.new()
	m.shader = load("res://addons/Godot-MToon-Shader/mtoon.gdshader")
	var ol := ShaderMaterial.new()
	ol.shader = load("res://addons/Godot-MToon-Shader/mtoon_outline.gdshader")
	var p := {
		"_ShadeToony": 0.95, "_ShadeShift": 0.12, "_IndirectLightIntensity": 0.15,
		"_LightColorAttenuation": 0.0, "_OutlineWidthMode": 1.0, "_OutlineWidth": 0.09,
		"_OutlineColorMode": 0.0, "_OutlineLightingMix": 1.0,
		"_OutlineColor": Color(0.05, 0.04, 0.07), "_ReceiveShadowRate": 1.0,
	}
	if name == "hair" or name.begins_with("hair"):
		# 丸刈りは地肌が透けて少し明るい
		var t := tint * Color(1.5, 1.5, 1.5) if name == "hair_buzz" else tint
		p["_Color"] = t
		p["_ShadeColor"] = t
		p["_MainTex"] = load(DIR + "hair_lit.png")
		p["_ShadeTexture"] = load(DIR + "hair_shade.png")
		p["_RimColor"] = Color(0.10, 0.10, 0.16)
		p["_RimFresnelPower"] = 4.0
		p["_RimLightingMix"] = 1.0
	elif name.begins_with("skin"):
		# 月代: 肌色をわずかに青く（剃り跡）
		var c := skin.lerp(Color(0.60, 0.68, 0.80), 0.25)
		p["_Color"] = c
		p["_ShadeColor"] = c * Color(0.86, 0.72, 0.76)
		p["_ShadeShift"] = -0.6
		p["_OutlineColor"] = Color(0.27, 0.09, 0.12)
		p["_OutlineWidth"] = 0.075
	else:
		var c: Color = ACC_COLORS.get(name, Color(0.8, 0.8, 0.8))
		p["_Color"] = c
		p["_ShadeColor"] = c * Color(0.6, 0.55, 0.7)
		p["_ShadeShift"] = -0.2
		p["_OutlineWidth"] = 0.06
		p["_OutlineColor"] = c * Color(0.25, 0.22, 0.28)
	for k in p:
		m.set_shader_parameter(k, p[k])
		ol.set_shader_parameter(k, p[k])
	m.next_pass = ol
	_mat_cache[ck] = m
	return m
