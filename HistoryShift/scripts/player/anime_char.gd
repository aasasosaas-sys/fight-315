class_name AnimeChar
extends RefCounted
## アニメ調（VRoid / VRM）の人物を組み立てる。
## 素体（VRM）＋ 和装（tools/vrm_wasou.py で布シミュ済みの glb）＋ 色（MToon）＋ リターゲット済みアニメーション。

const VRM_DIR := "res://assets/characters/vrm/cc0/"
const WASOU_DIR := "res://assets/characters/vrm/wasou/"

## 服装ごとに見せる布（vrm_wasou.py が書き出すパーツ名）
const SETS := {
	"modern": [],
	"samurai": ["kosode", "eri", "haneri", "hakama", "obi", "armor"],
	"hakama": ["kosode", "eri", "haneri", "hakama", "obi"],
	"kimono": ["kosode", "eri", "haneri", "robe", "obi"],
	"_dbg_noeri": ["kosode", "hakama", "obi"],
	"_dbg_eri": ["eri", "haneri"],
	"_dbg_k": ["kosode"],
	"_dbg_ke": ["kosode", "eri"],
	"_dbg_o": ["obi"],
}

## 自然染料ふうの色（明るめのアニメ配色）。[地の色, 影の色]
const DYES := {
	"ai": [Color(0.22, 0.32, 0.55), Color(0.12, 0.16, 0.34)],        # 藍
	"kon": [Color(0.16, 0.18, 0.32), Color(0.08, 0.08, 0.18)],       # 紺
	"kaki": [Color(0.72, 0.42, 0.26), Color(0.48, 0.24, 0.16)],      # 柿渋
	"moegi": [Color(0.47, 0.6, 0.32), Color(0.27, 0.38, 0.22)],      # 萌黄
	"enji": [Color(0.62, 0.17, 0.22), Color(0.38, 0.08, 0.14)],      # 臙脂
	"sakura": [Color(0.95, 0.74, 0.78), Color(0.78, 0.52, 0.6)],     # 桜
	"kuchiba": [Color(0.72, 0.6, 0.38), Color(0.5, 0.4, 0.24)],      # 朽葉
	"shiro": [Color(0.96, 0.95, 0.92), Color(0.75, 0.76, 0.82)],     # 白（半衿）
	"kuro": [Color(0.14, 0.13, 0.14), Color(0.06, 0.06, 0.08)],      # 黒
	"kin": [Color(0.86, 0.68, 0.3), Color(0.58, 0.4, 0.16)],         # 金茶
	"nezumi": [Color(0.55, 0.55, 0.56), Color(0.36, 0.36, 0.42)],    # 鼠
}

## 服装 → パーツごとの色
const PALETTES := {
	"samurai": {"kosode": "kon", "eri": "kon", "haneri": "shiro", "hakama": "nezumi", "obi": "kuro", "armor": "enji"},
	"hakama": {"kosode": "ai", "eri": "ai", "haneri": "shiro", "hakama": "kuchiba", "obi": "kuro"},
	"kimono": {"kosode": "sakura", "eri": "enji", "haneri": "shiro", "robe": "sakura", "obi": "kin"},
}


static func build(base: String, outfit := "modern", palette: Dictionary = {}) -> Node3D:
	var n: Node3D = (load(VRM_DIR + base + ".vrm") as PackedScene).instantiate()
	_prepare(n)
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	if outfit != "modern":
		_dress(n, sk, base, outfit, palette if not palette.is_empty() else PALETTES.get(outfit, {}))
	var ap := AnimationPlayer.new()
	ap.name = "Anim"
	n.add_child(ap)
	ap.root_node = ap.get_path_to(n)
	sk.motion_scale = sk.get_bone_global_rest(sk.find_bone("Hips")).origin.y
	ap.add_animation_library("", Retarget.library_for(sk, base))
	return n


## 素体の下ごしらえ：ねじれ骨の拘束（アニメーションと競合）と、服の揺れ骨を外す
static func _prepare(n: Node3D) -> void:
	var bnc := n.get_node_or_null("BoneNodeConstraintApplier")
	if bnc:
		n.remove_child(bnc)
		bnc.free()
	var sec := n.get_node_or_null("secondary")
	if sec:
		var keep: Array = []
		for sb in sec.spring_bones:
			if sb and not "Tops" in ",".join(sb.joint_nodes):
				keep.append(sb)
		sec.spring_bones.assign(keep)


static func _dress(n: Node3D, sk: Skeleton3D, base: String, outfit: String, pal: Dictionary) -> void:
	var path := WASOU_DIR + base + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("和装がまだ生成されていません: " + path)
		return
	var src: Node = (load(path) as PackedScene).instantiate()
	var body: MeshInstance3D = sk.get_node_or_null("Body")
	var template: Material = null
	if body:
		template = body.mesh.surface_get_material(0)
	var show: Array = SETS.get(outfit, [])
	for mi: MeshInstance3D in src.find_children("*", "MeshInstance3D", true, false):
		var part := _part_name(mi.name)
		if part == "bodyw":
			if body:
				_swap_body(body, mi, sk)
			continue
		if not part in show:
			continue
		var g := MeshInstance3D.new()
		g.name = "Garment_" + part
		g.mesh = mi.mesh
		sk.add_child(g)
		g.skeleton = g.get_path_to(sk)
		g.skin = _rebind(mi, sk)
		g.extra_cull_margin = 2.0
		var dye: Array = DYES.get(pal.get(part, "ai"), DYES["ai"])
		g.material_override = _cloth_mat(template, dye[0], dye[1], not part in ["eri", "haneri"] and OS.get_environment("NO_OUTLINE") == "")
		if OS.get_environment("DBG_PART") == part:
			var dm := StandardMaterial3D.new()
			dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			dm.albedo_color = Color(1, 0, 1)
			dm.cull_mode = BaseMaterial3D.CULL_DISABLED
			g.material_override = dm
	src.free()


static func _part_name(node_name: String) -> String:
	var s := node_name.to_lower()
	if s.begins_with("bodyw"):
		return "bodyw"
	for k in ["kosode", "haneri", "eri", "hakama", "robe", "obi", "armor"]:
		if ("garment_" + k) in s:
			return k
	return s


## 書き出した glb のスキンを、VRM 骨格の同名の骨へ結び直す（休止姿勢は VRM 側のもの）
static func _rebind(mi: MeshInstance3D, sk: Skeleton3D) -> Skin:
	var old := mi.skin
	var src_sk: Skeleton3D = mi.get_node_or_null(mi.skeleton) as Skeleton3D
	# VRM0 は Godot への読み込み時に 180° 回される。glb 側の向きとの差を求めて補正する
	var fix := Transform3D.IDENTITY
	if src_sk:
		var a := src_sk.find_bone("LeftUpperArm")
		var b := sk.find_bone("LeftUpperArm")
		if a >= 0 and b >= 0 and signf(src_sk.get_bone_global_rest(a).origin.x) != signf(sk.get_bone_global_rest(b).origin.x):
			fix = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var s := Skin.new()
	for i in old.get_bind_count():
		var bname := String(old.get_bind_name(i))
		if bname == "" and src_sk:
			bname = src_sk.get_bone_name(old.get_bind_bone(i))
		var bi := sk.find_bone(bname)
		if bi < 0:
			# 親指の中節など、名前の違う指の骨は手の骨で代用
			bname = ("LeftHand" if bname.begins_with("Left") else "RightHand" if bname.begins_with("Right") else "Hips")
			bi = sk.find_bone(bname)
		s.add_named_bind(bname, sk.get_bone_global_rest(bi).inverse() * fix)
	return s


## 体を「和装用の体」（服に隠れる部分を除いたもの）に差し替え、元の素材を名前で引き継ぐ
static func _swap_body(body: MeshInstance3D, src: MeshInstance3D, sk: Skeleton3D) -> void:
	var mats := {}
	for i in body.mesh.get_surface_count():
		var m := body.mesh.surface_get_material(i)
		if m:
			mats[m.resource_name] = m
	var mesh: ArrayMesh = src.mesh.duplicate()
	for i in mesh.get_surface_count():
		var m2 := mesh.surface_get_material(i)
		if m2 and mats.has(m2.resource_name):
			mesh.surface_set_material(i, mats[m2.resource_name])
	body.mesh = mesh
	body.skin = _rebind(src, sk)
	body.extra_cull_margin = 2.0


## 布の MToon（素体の素材を雛形に、地の色・影の色を差し替え）
static func _cloth_mat(template: Material, lit: Color, shade: Color, outline := true) -> Material:
	if template is ShaderMaterial:
		var m := (template as ShaderMaterial).duplicate() as ShaderMaterial
		m.set_shader_parameter("_MainTex", null)
		m.set_shader_parameter("_ShadeTexture", null)
		m.set_shader_parameter("_BumpMap", null)
		m.set_shader_parameter("_Color", lit)
		m.set_shader_parameter("_ShadeColor", shade)
		m.set_shader_parameter("_ShadeToony", 0.85)
		m.set_shader_parameter("_ShadeShift", -0.1)
		if not outline:
			# 細い帯（衿など）は輪郭線が帯より太くなるので付けず、両面を描く
			m.next_pass = null
			var cull_off: Shader = load("res://addons/Godot-MToon-Shader/mtoon_cull_off.gdshader")
			if cull_off:
				var params := {}
				for u in m.shader.get_shader_uniform_list():
					params[u.name] = m.get_shader_parameter(u.name)
				m.shader = cull_off
				for k in params:
					m.set_shader_parameter(k, params[k])
		elif m.next_pass is ShaderMaterial:
			var ol := (m.next_pass as ShaderMaterial).duplicate() as ShaderMaterial
			ol.set_shader_parameter("_MainTex", null)
			ol.set_shader_parameter("_Color", lit)
			ol.set_shader_parameter("_OutlineColor", shade.darkened(0.5))
			# 画面空間の輪郭線（正面向きの面では押し出さない）：布のくぼみで線が表に突き出さない
			ol.set_shader_parameter("_OutlineWidthTexture", null)
			ol.set_shader_parameter("_OutlineWidthMode", 2.0)
			ol.set_shader_parameter("_OutlineWidth", 0.22)
			m.next_pass = ol
		return m
	var sm := StandardMaterial3D.new()
	sm.albedo_color = lit
	sm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return sm
