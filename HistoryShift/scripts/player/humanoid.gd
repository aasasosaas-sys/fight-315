class_name Humanoid
extends Node3D
## プリミティブで組む人型＋手続きアニメーション。時代の衣装を色・小物（笠・兜・烏帽子・帽子）で表現。
## 原点は足元、身長約1.75m。

enum Outfit { AGENT, COMMONER, NOBLE, SAMURAI, ASHIGARU, MONK, WESTERN, SOLDIER, GUARDIAN, ANCIENT, POLICE, KIMONO }

var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var weapon: Node3D
var muzzle: Node3D

var speed := 0.0
var riding := false
var aiming := false
var crouch := 0.0         # 0..1 伏せ（町人パニック）
var _phase := 0.0
var _fall := 0.0
var _dying := false
var _hurt := 0.0

static var _meshes := {}
static var _matcache := {}


static func mat(c: Color, rough := 0.7, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var key := "%s%.2f%.2f%.2f" % [c.to_html(), rough, metal, emit]
	if _matcache.has(key):
		return _matcache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	_matcache[key] = m
	return m


static func mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m: Mesh
	match kind:
		"capsule":
			m = CapsuleMesh.new(); (m as CapsuleMesh).radius = 0.5; (m as CapsuleMesh).height = 2.0
		"sphere":
			m = SphereMesh.new(); (m as SphereMesh).radius = 0.5; (m as SphereMesh).height = 1.0
		"cyl":
			m = CylinderMesh.new(); (m as CylinderMesh).top_radius = 0.5; (m as CylinderMesh).bottom_radius = 0.5; (m as CylinderMesh).height = 1.0
		"cone":
			m = CylinderMesh.new(); (m as CylinderMesh).top_radius = 0.02; (m as CylinderMesh).bottom_radius = 0.5; (m as CylinderMesh).height = 1.0
		"torus":
			m = TorusMesh.new(); (m as TorusMesh).inner_radius = 0.35; (m as TorusMesh).outer_radius = 0.5
		"skirt":
			m = CylinderMesh.new(); (m as CylinderMesh).top_radius = 0.32; (m as CylinderMesh).bottom_radius = 0.5; (m as CylinderMesh).height = 1.0
		_:
			m = BoxMesh.new()
	_meshes[kind] = m
	return m


static func part(parent: Node3D, kind: String, material: Material, pos: Vector3, scl: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(kind)
	mi.material_override = material
	mi.position = pos
	mi.scale = scl
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _pivot(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = n
	p.position = pos
	parent.add_child(p)
	return p


static func outfit_for(era_id: String, role: String) -> int:
	# role: "enemy" "civilian" "npc" "guardian" "police"
	if role == "guardian":
		return Outfit.GUARDIAN
	match era_id:
		"jomon_kofun", "asuka_nara":
			return Outfit.ANCIENT if role != "npc" else Outfit.NOBLE
		"heian":
			return Outfit.SAMURAI if role == "enemy" else (Outfit.NOBLE if role == "npc" else Outfit.COMMONER)
		"kamakura_muromachi":
			return Outfit.SAMURAI if role == "enemy" else (Outfit.MONK if role == "npc" and randf() < 0.3 else Outfit.COMMONER)
		"sengoku":
			return Outfit.ASHIGARU if role == "enemy" else (Outfit.SAMURAI if role == "npc" else Outfit.COMMONER)
		"edo":
			return Outfit.SAMURAI if role in ["enemy", "npc"] else (Outfit.KIMONO if randf() < 0.5 else Outfit.COMMONER)
		"meiji_taisho":
			return Outfit.SOLDIER if role == "enemy" else (Outfit.WESTERN if role == "npc" or randf() < 0.4 else Outfit.KIMONO)
		"showa":
			return Outfit.SOLDIER if role == "enemy" else (Outfit.POLICE if role == "police" else Outfit.WESTERN)
	return Outfit.COMMONER


const MANNEQUIN := "res://assets/characters/kaykit/Mannequin_Medium.glb"
const ANIM_FILES := ["Rig_Medium_General", "Rig_Medium_MovementBasic", "Rig_Medium_MovementAdvanced", "Rig_Medium_CombatRanged", "Rig_Medium_Simulation", "Rig_Medium_Special"]
const LOOPS := ["Idle_A", "Idle_B", "Walking_A", "Walking_B", "Walking_C", "Running_A", "Running_B", "Running_HoldingRifle", "Running_HoldingBow",
	"Ranged_2H_Aiming", "Ranged_1H_Aiming", "Ranged_Bow_Aiming_Idle", "Ranged_Magic_Spellcasting", "Sit_Chair_Idle", "Crouching", "Cheering", "Waving",
	"Jump_Idle", "Skeletons_Idle", "Sneaking", "Walking_Backwards", "Sit_Floor_Idle"]
const UPPER_BONES := ["Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand"]
const SKEL := "%GeneralSkeleton:"
const REAL_DIR := "res://assets/characters/mh/"
const REAL_MALE := ["m01", "m02", "m03", "m04", "m05", "m06", "m07", "m08"]
const REAL_OLD := ["m09", "m10"]
const REAL_FEMALE := ["f01", "f02", "f03", "f04", "f05", "f06"]
const FEMALE_NAMES := ["卑弥呼", "推古", "持統", "光明", "紫式部", "清少納言", "北条政子", "日野富子", "お市", "ねね", "淀", "春日局",
	"和宮", "津田梅子", "与謝野晶子", "樋口一葉", "平塚らいてう", "市川房枝", "女", "娘", "姫", "妻", "母", "尼"]
static var _real_ok := -1
static var _lib: AnimationLibrary
static var _skinned_ok := -1

var skinned := false
var realistic := false
var _female_req := -1
var _tree: AnimationTree
var _skel: Skeleton3D
var _state := ""
var _aim_amount := 0.0


static func is_female_name(n: String) -> bool:
	for k in FEMALE_NAMES:
		if n.contains(k):
			return true
	return false


static func build(outfit: int, seed: int, armed: bool, female := -1) -> Humanoid:
	var h := Humanoid.new()
	h.name = "Humanoid"
	h._female_req = female
	if _skinned_ok == -1:
		_skinned_ok = 1 if ResourceLoader.exists(MANNEQUIN) else 0
	if _skinned_ok == 1:
		h._construct_skinned(outfit, seed, armed)
	else:
		h._construct(outfit, seed, armed)
	return h


static func anim_library() -> AnimationLibrary:
	if _lib:
		return _lib
	_lib = AnimationLibrary.new()
	var paths: Array = ["res://assets/characters/mocap/mocap.glb"]
	for f in ANIM_FILES:
		paths.append("res://assets/characters/kaykit/%s.glb" % f)
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var inst: Node = (load(path) as PackedScene).instantiate()
		var aps := inst.find_children("*", "AnimationPlayer", true, false)
		if aps.size() > 0:
			var ap: AnimationPlayer = aps[0]
			for n in ap.get_animation_list():
				if n == "T-Pose" or _lib.has_animation(n):
					continue
				var a: Animation = ap.get_animation(n).duplicate()
				var looped: bool = n in LOOPS or (n.begins_with("Mocap_") and not n in ["Mocap_Fall", "Mocap_Shoot"])
				a.loop_mode = Animation.LOOP_LINEAR if looped else Animation.LOOP_NONE
				_lib.add_animation(n, a)
		inst.free()
	return _lib


static func _anim_node(n: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = n
	return a


func _construct_skinned(outfit: int, seed: int, armed: bool) -> void:
	skinned = true
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var real_path := _pick_realistic(outfit, rng)
	var model: Node3D
	if real_path != "":
		realistic = true
		model = (load(real_path) as PackedScene).instantiate()
		add_child(model)
		_skel = model.find_children("*", "Skeleton3D", true, false)[0]
		var female := real_path.get_file().begins_with("f")
		set_meta("female", female)
		var h := _rest_height(model)
		# 時代ごとの日本人の平均身長（前近代 ≈ 男158/女146cm、近代 ≈ 男163/女151cm）
		var target := 1.72 if outfit == Outfit.AGENT else ((1.51 if female else 1.63) if outfit in MODERN else (1.46 if female else 1.58))
		target *= rng.randf_range(0.96, 1.04)
		model.scale = Vector3.ONE * (target / maxf(h, 0.5))
		_dress_realistic(model, outfit, rng, armed)
		_setup_tree(model, outfit, armed)
		return
	model = (load(MANNEQUIN) as PackedScene).instantiate()
	model.scale = Vector3.ONE * (1.75 / 2.2) * rng.randf_range(0.95, 1.05)
	add_child(model)
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	# 衣装の色
	var pal := _palette(outfit, rng)
	var glow := outfit == Outfit.AGENT or outfit == Outfit.GUARDIAN
	var skin := Color(0.93, 0.78, 0.64).lerp(Color(0.76, 0.56, 0.40), rng.randf())
	if outfit == Outfit.GUARDIAN:
		skin = Color(0.1, 0.08, 0.14)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		var c: Color = pal[0]
		if n.ends_with("Head"):
			c = skin
		elif n.contains("Leg"):
			c = pal[1]
		(mi as MeshInstance3D).material_override = mat(c, 0.75, 0.0)
	var m_acc := mat(pal[2], 0.3, 0.0, 3.0) if glow else mat(pal[2], 0.45, 0.6 if outfit == Outfit.SAMURAI else 0.0)
	var m_body := mat(pal[0], 0.8)
	var m_legs := mat(pal[1], 0.85)
	var m_hair := mat(Color(0.05, 0.04, 0.04), 0.5)
	# 小物（ボーンに追従）
	var head := _attach("Head")
	var chest := _attach("Chest")
	var hips_a := _attach("Hips")
	match outfit:
		Outfit.SAMURAI:
			part(head, "sphere", m_body, Vector3(0, 0.62, 0), Vector3(0.78, 0.5, 0.78))
			part(head, "box", m_acc, Vector3(0, 0.95, 0.28), Vector3(0.7, 0.3, 0.04), Vector3(-20, 0, 0))
			part(chest, "box", m_acc, Vector3(-0.42, 0.42, 0), Vector3(0.35, 0.06, 0.5), Vector3(0, 0, 25))
			part(chest, "box", m_acc, Vector3(0.42, 0.42, 0), Vector3(0.35, 0.06, 0.5), Vector3(0, 0, -25))
			part(hips_a, "skirt", m_acc, Vector3(0, -0.15, 0), Vector3(0.75, 0.45, 0.62))
		Outfit.ASHIGARU:
			part(head, "cone", m_acc, Vector3(0, 0.82, 0), Vector3(1.2, 0.22, 1.2))
			part(chest, "box", m_acc, Vector3(0, 0.15, 0.08), Vector3(0.62, 0.55, 0.45))
		Outfit.NOBLE:
			part(head, "cyl", m_hair, Vector3(0, 1.0, -0.05), Vector3(0.36, 0.45, 0.42), Vector3(-10, 0, 0))
			part(hips_a, "skirt", m_body, Vector3(0, -0.45, 0), Vector3(0.95, 0.9, 0.85))
		Outfit.KIMONO, Outfit.MONK, Outfit.ANCIENT:
			part(hips_a, "skirt", m_body if outfit != Outfit.MONK else m_legs, Vector3(0, -0.45, 0), Vector3(0.82, 0.95, 0.7))
			if outfit == Outfit.KIMONO:
				part(head, "sphere", m_hair, Vector3(0, 0.75, -0.18), Vector3(0.42, 0.32, 0.36))
				part(chest, "box", m_acc, Vector3(0, -0.15, 0), Vector3(0.66, 0.16, 0.5))
		Outfit.WESTERN, Outfit.SOLDIER, Outfit.POLICE:
			part(head, "cyl", m_legs, Vector3(0, 0.78, 0), Vector3(0.82, 0.03, 0.82))
			part(head, "cyl", m_legs, Vector3(0, 0.9, 0), Vector3(0.58, 0.2, 0.58))
		Outfit.GUARDIAN:
			part(head, "box", m_acc, Vector3(0, 0.38, 0.32), Vector3(0.5, 0.1, 0.05))
			part(chest, "box", m_acc, Vector3(0, 0.25, 0.3), Vector3(0.08, 0.5, 0.04))
		Outfit.AGENT:
			part(head, "box", m_acc, Vector3(0, 0.4, 0.33), Vector3(0.52, 0.12, 0.06))
			part(hips_a, "skirt", m_body, Vector3(0, -0.35, -0.02), Vector3(0.72, 0.8, 0.55))
		_:
			part(head, "sphere", m_hair, Vector3(0, 0.6, -0.04), Vector3(0.66, 0.5, 0.66))
	if armed:
		var hand := _attach("RightHand")
		weapon = Node3D.new()
		weapon.name = "Weapon"
		hand.add_child(weapon)
		var metal := mat(Color(0.12, 0.12, 0.13), 0.35, 0.9)
		weapon.rotation_degrees = Vector3(0, 0, 0)
		if glow:
			part(weapon, "box", metal, Vector3(0, 0.05, 0.35), Vector3(0.14, 0.22, 0.8))
			part(weapon, "box", m_acc, Vector3(0, 0.15, 0.4), Vector3(0.15, 0.04, 0.6))
		else:
			var wood := mat(Color(0.35, 0.22, 0.12), 0.7)
			part(weapon, "box", wood, Vector3(0, 0.0, 0.1), Vector3(0.1, 0.14, 0.9))
			part(weapon, "cyl", metal, Vector3(0, 0.05, 0.9), Vector3(0.06, 0.7, 0.06), Vector3(90, 0, 0))
		muzzle = Node3D.new()
		muzzle.position = Vector3(0, 0.08, 1.25)
		weapon.add_child(muzzle)
	_setup_tree(model, outfit, armed)


func _setup_tree(model: Node3D, outfit: int, armed: bool) -> void:
	_tree = AnimationTree.new()
	model.add_child(_tree)
	_tree.root_node = NodePath("..")
	_tree.add_animation_library("", anim_library())
	var bt := AnimationNodeBlendTree.new()
	var bs := AnimationNodeBlendSpace1D.new()
	var lib := anim_library()
	var mocap := lib.has_animation("Mocap_Walk")
	var idle_name := "Skeletons_Idle" if outfit == Outfit.GUARDIAN else "Idle_A"
	bs.add_blend_point(_anim_node(idle_name), 0.0)
	if mocap:
		var soldier := outfit in [Outfit.SOLDIER, Outfit.ASHIGARU, Outfit.SAMURAI]
		bs.add_blend_point(_anim_node("Mocap_March" if soldier and not armed else "Mocap_Walk"), 1.5)
		bs.add_blend_point(_anim_node("Mocap_Jog"), 3.6)
		bs.add_blend_point(_anim_node("Running_HoldingRifle" if armed else "Mocap_Run"), 6.0)
		bs.add_blend_point(_anim_node("Mocap_Run"), 9.5)
	else:
		bs.add_blend_point(_anim_node("Walking_A"), 1.8)
		bs.add_blend_point(_anim_node("Running_HoldingRifle" if armed else "Running_A"), 5.2)
		bs.add_blend_point(_anim_node("Running_B"), 9.5)
	bs.min_space = 0.0
	bs.max_space = 10.0
	bt.add_node("loco", bs, Vector2(0, 0))
	bt.add_node("aim", _anim_node("Ranged_2H_Aiming"), Vector2(0, 200))
	var upper := AnimationNodeBlend2.new()
	upper.filter_enabled = true
	for b in UPPER_BONES:
		upper.set_filter_path(NodePath(SKEL + b), true)
	bt.add_node("upper", upper, Vector2(200, 0))
	bt.connect_node("upper", 0, "loco")
	bt.connect_node("upper", 1, "aim")
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = 0.18
	for n in ["loco", "ride", "crouch", "dead", "jump"]:
		tr.add_input(n)
	bt.add_node("state", tr, Vector2(400, 0))
	bt.add_node("ride", _anim_node("Mocap_Sit" if mocap else "Sit_Chair_Idle"), Vector2(200, 200))
	bt.add_node("crouch", _anim_node("Crouching"), Vector2(200, 300))
	bt.add_node("dead", _anim_node("Mocap_Fall" if mocap else "Death_A"), Vector2(200, 400))
	bt.add_node("jump", _anim_node("Jump_Idle"), Vector2(200, 500))
	bt.connect_node("state", 0, "upper")
	bt.connect_node("state", 1, "ride")
	bt.connect_node("state", 2, "crouch")
	bt.connect_node("state", 3, "dead")
	bt.connect_node("state", 4, "jump")
	var hit := AnimationNodeOneShot.new()
	hit.filter_enabled = true
	for b in UPPER_BONES:
		hit.set_filter_path(NodePath(SKEL + b), true)
	hit.fadein_time = 0.05
	hit.fadeout_time = 0.15
	bt.add_node("hit", hit, Vector2(600, 0))
	bt.add_node("hitanim", _anim_node("Hit_A"), Vector2(400, 200))
	bt.connect_node("hit", 0, "state")
	bt.connect_node("hit", 1, "hitanim")
	bt.connect_node("output", 0, "hit")
	_tree.tree_root = bt
	_tree.active = true
	# 互換用のダミー関節（手続きアニメ用変数を参照するコードのため）
	hips = Node3D.new(); torso = hips; head = hips; arm_l = hips; arm_r = hips; leg_l = hips; leg_r = hips
	add_child(hips)


func _pick_realistic(outfit: int, rng: RandomNumberGenerator) -> String:
	if _real_ok == -1:
		_real_ok = 1 if ResourceLoader.exists(REAL_DIR + "m01.gltf") else 0
	if _real_ok == 0:
		return ""
	var female := false
	if _female_req >= 0:
		female = _female_req == 1
	elif outfit in [Outfit.KIMONO]:
		female = rng.randf() < 0.8
	elif outfit in [Outfit.COMMONER, Outfit.WESTERN, Outfit.ANCIENT, Outfit.NOBLE]:
		female = rng.randf() < 0.4
	var pool: Array = REAL_FEMALE if female else REAL_MALE
	if outfit == Outfit.MONK or (not female and outfit == Outfit.COMMONER and rng.randf() < 0.25):
		pool = REAL_OLD
	elif outfit in [Outfit.SOLDIER, Outfit.POLICE, Outfit.ASHIGARU]:
		pool = ["m03", "m01", "m05", "m07"]
	elif outfit == Outfit.AGENT:
		pool = ["m04"]
	var vname: String = pool[rng.randi() % pool.size()]
	var path := REAL_DIR + vname + ".gltf"
	return path if ResourceLoader.exists(path) else REAL_DIR + "m01.gltf"


static func _rest_height(model: Node3D) -> float:
	var aabb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	return aabb.end.y


## 実寸（メートル）で小物を付けるためのホルダー
func _holder(bone: String) -> Node3D:
	var ba := _attach(bone)
	var h := Node3D.new()
	var s: float = get_child(0).scale.x if get_child_count() > 0 else 1.0
	h.scale = Vector3.ONE / maxf(s, 0.01)
	ba.add_child(h)
	return h


func _tint(mi: MeshInstance3D, c: Color, rough := -1.0) -> void:
	for si in mi.mesh.get_surface_count():
		var base := mi.mesh.surface_get_material(si)
		if base is BaseMaterial3D:
			var m := (base as BaseMaterial3D).duplicate() as BaseMaterial3D
			m.albedo_color = c
			if rough >= 0.0:
				m.roughness = rough
			mi.set_surface_override_material(si, m)


## 肌：皮下散乱（光が薄く透ける）と、やや湿った反射
func _skin(mi: MeshInstance3D, tint: Color) -> void:
	for si in mi.mesh.get_surface_count():
		var base := mi.mesh.surface_get_material(si)
		if not (base is BaseMaterial3D):
			continue
		var m := (base as BaseMaterial3D).duplicate() as StandardMaterial3D
		if m == null:
			continue
		m.albedo_color = tint
		m.roughness = 0.52
		m.metallic_specular = 0.45
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = 0.35
		m.subsurf_scatter_skin_mode = true
		m.rim_enabled = true
		m.rim = 0.15
		m.rim_tint = 0.6
		mi.set_surface_override_material(si, m)


## 目：つやのある角膜
func _eyes(mi: MeshInstance3D) -> void:
	for si in mi.mesh.get_surface_count():
		var base := mi.mesh.surface_get_material(si)
		if base is StandardMaterial3D:
			var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.roughness = 0.08
			m.clearcoat_enabled = true
			m.clearcoat = 1.0
			m.clearcoat_roughness = 0.02
			mi.set_surface_override_material(si, m)


## 髪・眉・まつげ：半透明（ディザ）と異方性のつや
func _strands(mi: MeshInstance3D, c: Color, hair: bool) -> void:
	for si in mi.mesh.get_surface_count():
		var base := mi.mesh.surface_get_material(si)
		if not (base is StandardMaterial3D):
			continue
		var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		m.alpha_hash_scale = 1.0
		m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.6 if hair else 0.75
		if hair:
			m.anisotropy_enabled = true
			m.anisotropy = 0.3
			m.metallic_specular = 0.35
		mi.set_surface_override_material(si, m)


const MODERN := [Outfit.WESTERN, Outfit.SOLDIER, Outfit.POLICE, Outfit.AGENT, Outfit.GUARDIAN]
## 和装の組み合わせ（Blender で体型から作った衣服メッシュ: kosode / hakama / robe / armor）
const WASOU := {
	Outfit.SAMURAI: ["kosode", "hakama", "armor"], Outfit.ASHIGARU: ["kosode", "hakama", "armor"],
	Outfit.NOBLE: ["kosode", "robe"], Outfit.KIMONO: ["kosode", "robe"], Outfit.MONK: ["kosode", "robe"],
	Outfit.ANCIENT: ["kosode", "hakama"], Outfit.COMMONER: ["kosode", "hakama"],
}
static var _fabric_tex := {}


## 布地：織り目の凹凸と柄（無地・縞・格子・麻の葉風）
static func fabric(c: Color, pattern: String, rough := 0.88) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3(6, 6, 6)
	if pattern != "plain":
		m.albedo_texture = _pattern_tex(pattern)
	m.normal_enabled = true
	m.normal_texture = _pattern_tex("weave_n")
	m.normal_scale = 0.4
	return m


static func _pattern_tex(kind: String) -> Texture2D:
	if _fabric_tex.has(kind):
		return _fabric_tex[kind]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := 1.0
			match kind:
				"stripe": v = 1.0 if (x / 6) % 2 == 0 else 0.72
				"check": v = 1.0 if ((x / 8) + (y / 8)) % 2 == 0 else 0.78
				"asanoha":
					var d := absf(fmod(float(x + y), 16.0) - 8.0) + absf(fmod(float(x - y + 64), 16.0) - 8.0)
					v = 0.75 if d < 1.6 or x % 16 == 0 else 1.0
				"weave_n":
					var h := 0.5 + 0.5 * sin(x * PI / 2.0) * (1.0 if (y / 2) % 2 == 0 else -1.0)
					img.set_pixel(x, y, Color(0.5 + 0.12 * h, 0.5, 1.0))
					continue
			img.set_pixel(x, y, Color(v, v, v))
	var t := ImageTexture.create_from_image(img)
	_fabric_tex[kind] = t
	return t


func _dress_realistic(model: Node3D, outfit: int, rng: RandomNumberGenerator, armed: bool) -> void:
	var pal := _palette(outfit, rng)
	var glow := outfit == Outfit.AGENT or outfit == Outfit.GUARDIAN
	var modern := outfit in MODERN
	var wear: Array = WASOU.get(outfit, [])
	var hair_c := Color(0.035, 0.03, 0.028) if outfit != Outfit.MONK else Color(0.3, 0.3, 0.3)
	var pattern: String = ["plain", "plain", "stripe", "check", "asanoha"][rng.randi() % 5] if outfit in [Outfit.KIMONO, Outfit.COMMONER] else "plain"
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var n := String(mi.name).to_lower()
		if n.contains("_garment_"):
			var kind := n.get_slice("_garment_", 1)
			mi.visible = kind in wear
			if mi.visible:
				var c: Color = pal[0]
				match kind:
					"hakama", "robe":
						c = pal[1] if outfit != Outfit.KIMONO else pal[0]
					"armor":
						c = pal[2] if outfit == Outfit.SAMURAI else pal[2].darkened(0.2)
				var fm := fabric(c, pattern if kind != "armor" else "check", 0.6 if kind == "armor" else 0.88)
				if kind == "armor":
					fm.metallic = 0.25
					fm.uv1_scale = Vector3(14, 14, 14)
				mi.material_override = fm
			continue
		if n.ends_with("_body"):
			_skin(mi, Color(0.25, 0.22, 0.3) if outfit == Outfit.GUARDIAN else Color.WHITE)
			continue
		if n.contains("low-poly"):
			_eyes(mi)
			continue
		if n.contains("eyelash") or n.contains("eyebrow"):
			_strands(mi, Color(0.03, 0.025, 0.02), false)
			continue
		if n.contains("short") or n.contains("long") or n.contains("bob") or n.contains("ponytail") or n.contains("braid") or n.contains("afro"):
			_strands(mi, hair_c, true)
			if outfit == Outfit.MONK:
				mi.visible = false
			continue
		if n.contains("shoes"):
			# 洋装は革靴、和装は草履・草鞋の色
			_tint(mi, Color(0.12, 0.1, 0.09) if modern else Color(0.62, 0.52, 0.36), 0.8)
			continue
		# 洋服（明治・昭和のみ表示）
		mi.visible = modern
		if modern:
			var c2: Color = pal[0]
			if outfit == Outfit.WESTERN:
				c2 = Color(1, 1, 1).lerp(pal[0], 0.5)
			_tint(mi, c2.lightened(0.1) if not glow else c2, 0.85)
	var m_acc := mat(pal[2], 0.3, 0.0, 3.0) if glow else mat(pal[2], 0.5, 0.5 if outfit == Outfit.SAMURAI else 0.0)
	var m_legs := mat(pal[1], 0.9)
	var m_black := mat(Color(0.05, 0.05, 0.05), 0.5)
	var m_straw := mat(Color(0.62, 0.5, 0.3), 0.9)
	var m_lacquer := mat(pal[0].darkened(0.3), 0.25, 0.3)
	var head := _holder("Head")
	var chest := _holder("Chest")
	var male: bool = not get_meta("female", false)
	match outfit:
		Outfit.SAMURAI:
			part(head, "sphere", m_lacquer, Vector3(0, 0.1, -0.01), Vector3(0.25, 0.17, 0.27))       # 兜の鉢
			part(head, "cone", m_lacquer, Vector3(0, 0.05, -0.03), Vector3(0.4, 0.07, 0.4))          # 錣
			part(head, "box", m_acc, Vector3(0, 0.2, 0.12), Vector3(0.22, 0.09, 0.008), Vector3(-15, 0, 0))  # 鍬形
		Outfit.ASHIGARU:
			part(head, "cone", m_lacquer, Vector3(0, 0.15, 0), Vector3(0.46, 0.08, 0.46))              # 陣笠
		Outfit.NOBLE:
			part(head, "cyl", m_black, Vector3(0, 0.22, -0.02), Vector3(0.12, 0.24, 0.14), Vector3(-12, 0, 0))  # 烏帽子
		Outfit.KIMONO:
			part(chest, "box", m_acc, Vector3(0, -0.17, 0), Vector3(0.33, 0.11, 0.23))                # 帯
		Outfit.MONK:
			part(chest, "box", m_acc, Vector3(0.04, 0.0, 0.02), Vector3(0.4, 0.05, 0.27), Vector3(0, 0, -35))  # 袈裟
		Outfit.ANCIENT:
			part(head, "torus", m_black, Vector3(0, 0.08, 0), Vector3(0.22, 0.1, 0.22))              # 角髪の紐
		Outfit.COMMONER:
			if rng.randf() < 0.45:
				part(head, "cone", m_straw, Vector3(0, 0.15, 0), Vector3(0.44, 0.12, 0.44))             # 菅笠
			elif male:
				part(head, "cyl", m_black, Vector3(0, 0.15, -0.03), Vector3(0.035, 0.08, 0.035), Vector3(70, 0, 0))  # 髷
		Outfit.WESTERN:
			if rng.randf() < 0.6:
				part(head, "cyl", m_legs, Vector3(0, 0.13, 0), Vector3(0.32, 0.012, 0.32))
				part(head, "cyl", m_legs, Vector3(0, 0.18, 0), Vector3(0.19, 0.09, 0.19))
		Outfit.SOLDIER, Outfit.POLICE:
			part(head, "cyl", m_legs, Vector3(0, 0.15, 0), Vector3(0.21, 0.065, 0.21))
			part(head, "box", m_black, Vector3(0, 0.12, 0.1), Vector3(0.15, 0.01, 0.07))
		Outfit.GUARDIAN:
			part(head, "box", m_acc, Vector3(0, 0.08, 0.1), Vector3(0.16, 0.03, 0.02))
			part(chest, "box", m_acc, Vector3(0, 0.05, 0.14), Vector3(0.03, 0.3, 0.01))
		Outfit.AGENT:
			part(head, "box", m_acc, Vector3(0, 0.08, 0.1), Vector3(0.17, 0.03, 0.02))                # バイザー
	if outfit == Outfit.SAMURAI and male:
		part(head, "cyl", m_black, Vector3(0, 0.15, -0.03), Vector3(0.035, 0.08, 0.035), Vector3(70, 0, 0))
	if armed:
		var hand := _holder("RightHand")
		weapon = Node3D.new()
		weapon.name = "Weapon"
		hand.add_child(weapon)
		weapon.position = Vector3(0, 0.07, 0.03)
		weapon.rotation_degrees = Vector3(-90, 0, 0)
		var metal := mat(Color(0.12, 0.12, 0.13), 0.35, 0.9)
		if glow:
			part(weapon, "box", metal, Vector3(0, 0, 0.12), Vector3(0.05, 0.08, 0.36))
			part(weapon, "box", m_acc, Vector3(0, 0.04, 0.14), Vector3(0.052, 0.012, 0.26))
		else:
			var wood := mat(Color(0.35, 0.22, 0.12), 0.7)
			part(weapon, "box", wood, Vector3(0, -0.01, -0.05), Vector3(0.045, 0.07, 0.42))
			part(weapon, "cyl", metal, Vector3(0, 0.02, 0.38), Vector3(0.022, 0.62, 0.022), Vector3(90, 0, 0))
		muzzle = Node3D.new()
		muzzle.position = Vector3(0, 0.02, 0.7)
		weapon.add_child(muzzle)


func _attach(bone: String) -> Node3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	_skel.add_child(ba)
	return ba


func _palette(outfit: int, rng: RandomNumberGenerator) -> Array:
	match outfit:
		Outfit.AGENT: return [Color(0.11, 0.12, 0.16), Color(0.08, 0.08, 0.1), Effects.CYAN]
		Outfit.NOBLE: return [[Color(0.55, 0.18, 0.35), Color(0.2, 0.3, 0.6), Color(0.75, 0.55, 0.2), Color(0.3, 0.5, 0.35)][rng.randi() % 4], Color(0.88, 0.85, 0.78), Color(0.08, 0.08, 0.08)]
		Outfit.SAMURAI: return [[Color(0.6, 0.12, 0.1), Color(0.15, 0.18, 0.3), Color(0.22, 0.22, 0.22)][rng.randi() % 3], Color(0.2, 0.17, 0.14), Color(0.8, 0.65, 0.25)]
		Outfit.ASHIGARU: return [Color(0.24, 0.21, 0.17), Color(0.3, 0.26, 0.2), Color(0.32, 0.14, 0.1)]
		Outfit.MONK: return [Color(0.18, 0.17, 0.16), Color(0.85, 0.83, 0.78), Color(0.62, 0.45, 0.2)]
		Outfit.WESTERN: return [[Color(0.1, 0.1, 0.12), Color(0.25, 0.2, 0.17), Color(0.2, 0.22, 0.3)][rng.randi() % 3], Color(0.12, 0.12, 0.13), Color(0.95, 0.95, 0.95)]
		Outfit.SOLDIER: return [Color(0.36, 0.38, 0.26), Color(0.33, 0.34, 0.24), Color(0.2, 0.2, 0.15)]
		Outfit.GUARDIAN: return [Color(0.05, 0.05, 0.08), Color(0.04, 0.04, 0.06), Effects.GUARD]
		Outfit.ANCIENT: return [Color(0.8, 0.74, 0.6), Color(0.7, 0.64, 0.5), Color(0.55, 0.3, 0.2)]
		Outfit.POLICE: return [Color(0.08, 0.1, 0.2), Color(0.08, 0.1, 0.2), Color(0.85, 0.75, 0.3)]
		Outfit.KIMONO: return [[Color(0.7, 0.3, 0.35), Color(0.25, 0.35, 0.55), Color(0.4, 0.5, 0.35), Color(0.6, 0.5, 0.65)][rng.randi() % 4], Color(0.2, 0.15, 0.15), Color(0.9, 0.82, 0.5)]
	return [[Color(0.3, 0.35, 0.5), Color(0.45, 0.35, 0.25), Color(0.35, 0.42, 0.33), Color(0.55, 0.5, 0.42)][rng.randi() % 4], Color(0.25, 0.22, 0.2), Color(0.6, 0.55, 0.45)]


func _set_state(st: String) -> void:
	if st != _state and _tree:
		_state = st
		_tree.set("parameters/state/transition_request", st)


func _process_skinned(dt: float) -> void:
	if _dying:
		_set_state("dead")
		return
	if riding:
		_set_state("ride")
	elif crouch > 0.2:
		_set_state("crouch")
	else:
		_set_state("loco")
	_tree.set("parameters/loco/blend_position", speed)
	_aim_amount = move_toward(_aim_amount, 1.0 if aiming else 0.0, dt * 8.0)
	_tree.set("parameters/upper/blend_amount", _aim_amount)
	if _hurt >= 0.99:
		_tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_hurt = 0.98
	_hurt = move_toward(_hurt, 0.0, dt * 4.0)


func _construct(outfit: int, seed: int, armed: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var skin := Color(0.93, 0.78, 0.64).lerp(Color(0.76, 0.56, 0.40), rng.randf())
	var palette := {
		Outfit.AGENT: [Color(0.11, 0.12, 0.16), Color(0.08, 0.08, 0.1), Effects.CYAN],
		Outfit.NOBLE: [[Color(0.55, 0.18, 0.35), Color(0.2, 0.3, 0.6), Color(0.75, 0.55, 0.2), Color(0.3, 0.5, 0.35)][rng.randi() % 4], Color(0.88, 0.85, 0.78), Color(0.08, 0.08, 0.08)],
		Outfit.SAMURAI: [[Color(0.6, 0.12, 0.1), Color(0.15, 0.18, 0.3), Color(0.22, 0.22, 0.22)][rng.randi() % 3], Color(0.2, 0.17, 0.14), Color(0.8, 0.65, 0.25)],
		Outfit.ASHIGARU: [Color(0.24, 0.21, 0.17), Color(0.3, 0.26, 0.2), Color(0.32, 0.14, 0.1)],
		Outfit.MONK: [Color(0.18, 0.17, 0.16), Color(0.85, 0.83, 0.78), Color(0.62, 0.45, 0.2)],
		Outfit.WESTERN: [[Color(0.1, 0.1, 0.12), Color(0.25, 0.2, 0.17), Color(0.2, 0.22, 0.3)][rng.randi() % 3], Color(0.12, 0.12, 0.13), Color(0.95, 0.95, 0.95)],
		Outfit.SOLDIER: [Color(0.36, 0.38, 0.26), Color(0.33, 0.34, 0.24), Color(0.2, 0.2, 0.15)],
		Outfit.GUARDIAN: [Color(0.05, 0.05, 0.08), Color(0.04, 0.04, 0.06), Effects.GUARD],
		Outfit.ANCIENT: [Color(0.8, 0.74, 0.6), Color(0.7, 0.64, 0.5), Color(0.55, 0.3, 0.2)],
		Outfit.POLICE: [Color(0.08, 0.1, 0.2), Color(0.08, 0.1, 0.2), Color(0.85, 0.75, 0.3)],
		Outfit.KIMONO: [[Color(0.7, 0.3, 0.35), Color(0.25, 0.35, 0.55), Color(0.4, 0.5, 0.35), Color(0.6, 0.5, 0.65)][rng.randi() % 4], Color(0.2, 0.15, 0.15), Color(0.9, 0.82, 0.5)],
	}
	var pal: Array = palette.get(outfit, [[Color(0.3, 0.35, 0.5), Color(0.45, 0.35, 0.25), Color(0.35, 0.42, 0.33), Color(0.55, 0.5, 0.42)][rng.randi() % 4], Color(0.25, 0.22, 0.2), Color(0.6, 0.55, 0.45)])
	var glow := outfit == Outfit.AGENT or outfit == Outfit.GUARDIAN
	var m_skin := mat(skin, 0.6)
	var m_body := mat(pal[0], 0.8)
	var m_legs := mat(pal[1], 0.85)
	var m_acc := mat(pal[2], 0.3, 0.0, 3.0) if glow else mat(pal[2], 0.45, 0.6 if outfit == Outfit.SAMURAI else 0.0)
	var m_hair := mat(Color(0.05, 0.04, 0.04), 0.5)
	if outfit == Outfit.GUARDIAN:
		m_skin = mat(Color(0.1, 0.08, 0.14), 0.2, 0.5)

	hips = _pivot(self, "Hips", Vector3(0, 0.95, 0))
	torso = _pivot(hips, "Torso", Vector3.ZERO)
	part(torso, "capsule", m_body, Vector3(0, 0.3, 0), Vector3(0.42, 0.33, 0.26))
	part(torso, "box", m_acc, Vector3(0, 0.05, 0), Vector3(0.44, 0.06, 0.28))
	if outfit in [Outfit.NOBLE, Outfit.MONK, Outfit.ANCIENT, Outfit.KIMONO]:
		part(torso, "skirt", m_body if outfit != Outfit.MONK else m_legs, Vector3(0, -0.42, 0), Vector3(0.5, 0.85, 0.42))
	if outfit == Outfit.SAMURAI:   # 大鎧の肩
		part(torso, "box", m_acc, Vector3(-0.26, 0.5, 0), Vector3(0.18, 0.04, 0.26), Vector3(0, 0, 20))
		part(torso, "box", m_acc, Vector3(0.26, 0.5, 0), Vector3(0.18, 0.04, 0.26), Vector3(0, 0, -20))
	head = _pivot(torso, "Head", Vector3(0, 0.68, 0))
	part(head, "sphere", m_skin, Vector3(0, 0.1, 0), Vector3(0.22, 0.25, 0.23))
	part(head, "sphere", m_hair, Vector3(0, 0.16, -0.02), Vector3(0.235, 0.2, 0.235))
	match outfit:
		Outfit.SAMURAI:
			part(head, "sphere", m_body, Vector3(0, 0.19, 0), Vector3(0.3, 0.2, 0.3))
			part(head, "box", m_acc, Vector3(0, 0.33, 0.08), Vector3(0.28, 0.12, 0.02), Vector3(-20, 0, 0))
		Outfit.ASHIGARU:
			part(head, "cone", m_acc, Vector3(0, 0.27, 0), Vector3(0.5, 0.1, 0.5))
		Outfit.NOBLE:
			part(head, "cyl", m_acc, Vector3(0, 0.34, -0.02), Vector3(0.14, 0.16, 0.16), Vector3(-10, 0, 0))
		Outfit.WESTERN, Outfit.SOLDIER, Outfit.POLICE:
			part(head, "cyl", m_legs, Vector3(0, 0.26, 0), Vector3(0.3, 0.015, 0.3))
			part(head, "cyl", m_legs, Vector3(0, 0.31, 0), Vector3(0.22, 0.07, 0.22))
		Outfit.MONK:
			part(head, "sphere", m_skin, Vector3(0, 0.16, -0.02), Vector3(0.24, 0.21, 0.24))
		Outfit.ANCIENT:
			part(head, "sphere", m_hair, Vector3(-0.13, 0.08, 0), Vector3(0.07, 0.12, 0.07))
			part(head, "sphere", m_hair, Vector3(0.13, 0.08, 0), Vector3(0.07, 0.12, 0.07))
		Outfit.GUARDIAN:
			part(head, "box", m_acc, Vector3(0, 0.12, 0.11), Vector3(0.18, 0.04, 0.02))
		Outfit.AGENT:
			part(head, "box", m_acc, Vector3(0, 0.13, 0.105), Vector3(0.19, 0.05, 0.03))
		Outfit.KIMONO:
			part(head, "sphere", m_hair, Vector3(0, 0.25, -0.06), Vector3(0.16, 0.12, 0.14))

	arm_l = _pivot(torso, "ArmL", Vector3(-0.27, 0.55, 0))
	arm_r = _pivot(torso, "ArmR", Vector3(0.27, 0.55, 0))
	for arm in [arm_l, arm_r]:
		part(arm, "capsule", m_body, Vector3(0, -0.28, 0), Vector3(0.12, 0.3, 0.12))
		part(arm, "sphere", m_skin, Vector3(0, -0.6, 0), Vector3(0.1, 0.1, 0.1))
	leg_l = _pivot(hips, "LegL", Vector3(-0.11, 0, 0))
	leg_r = _pivot(hips, "LegR", Vector3(0.11, 0, 0))
	for leg in [leg_l, leg_r]:
		part(leg, "capsule", m_legs, Vector3(0, -0.44, 0), Vector3(0.15, 0.45, 0.15))
		part(leg, "box", m_hair, Vector3(0, -0.9, 0.05), Vector3(0.13, 0.08, 0.25))
	if outfit == Outfit.AGENT:  # コート
		part(torso, "skirt", m_body, Vector3(0, -0.3, -0.02), Vector3(0.46, 0.6, 0.34))

	if armed:
		weapon = _pivot(arm_r, "Weapon", Vector3(0, -0.6, 0.05))
		var metal := mat(Color(0.12, 0.12, 0.13), 0.35, 0.9)
		if glow:
			part(weapon, "box", metal, Vector3(0, 0, 0.18), Vector3(0.07, 0.1, 0.42))
			part(weapon, "box", m_acc, Vector3(0, 0.04, 0.2), Vector3(0.075, 0.02, 0.3))
		else:
			var wood := mat(Color(0.35, 0.22, 0.12), 0.7)
			part(weapon, "box", wood, Vector3(0, 0, 0.1), Vector3(0.06, 0.08, 0.5))
			part(weapon, "cyl", metal, Vector3(0, 0.03, 0.55), Vector3(0.03, 0.35, 0.03), Vector3(90, 0, 0))
		muzzle = _pivot(weapon, "Muzzle", Vector3(0, 0.03, 0.75))


func die() -> void:
	_dying = true


func hurt() -> void:
	_hurt = 1.0


func _process(dt: float) -> void:
	if skinned:
		_process_skinned(dt)
		return
	if _dying:
		_fall = move_toward(_fall, 1.0, dt * 2.5)
		rotation.x = -deg_to_rad(85.0) * smoothstep(0.0, 1.0, _fall)
		position.y = 0.2 * _fall
		return
	_hurt = move_toward(_hurt, 0.0, dt * 4.0)
	if riding:
		leg_l.rotation_degrees = Vector3(-70, 0, -25)
		leg_r.rotation_degrees = Vector3(-70, 0, 25)
		arm_l.rotation_degrees = Vector3(-45, 0, 0)
		arm_r.rotation_degrees = Vector3(-90, 0, 0) if aiming else Vector3(-45, 0, 0)
		hips.position.y = 0.95 + sin(Time.get_ticks_msec() * 0.012) * 0.03 * clampf(speed / 10.0, 0, 1)
		return
	var s := clampf(speed / 7.0, 0.0, 1.0)
	if speed > 0.2:
		_phase += dt * lerpf(4.0, 11.0, s)
	var swing := sin(_phase) * lerpf(0.0, 50.0, clampf(speed / 3.0, 0, 1)) * (0.6 + 0.4 * s)
	leg_l.rotation_degrees = Vector3(swing, 0, 0)
	leg_r.rotation_degrees = Vector3(-swing, 0, 0)
	arm_l.rotation_degrees = Vector3(-swing * 0.8, 0, -4)
	arm_r.rotation_degrees = Vector3(-88, 0, 0) if aiming else Vector3(swing * 0.8, 0, 4)
	torso.rotation_degrees = Vector3(lerpf(0, 12, s) + crouch * 40.0 - _hurt * 15.0, 0.0 if aiming else sin(_phase) * 4.0 * s, 0)
	hips.position.y = 0.95 + absf(cos(_phase)) * 0.06 * s - crouch * 0.35
	if crouch > 0.01:
		leg_l.rotation_degrees.x -= crouch * 60.0
		leg_r.rotation_degrees.x -= crouch * 60.0
		arm_l.rotation_degrees = Vector3(-150 * crouch, 0, 10)
		arm_r.rotation_degrees = Vector3(-150 * crouch, 0, -10)
