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
const UPPER_BONES := ["spine", "chest", "head", "upperarm.l", "lowerarm.l", "wrist.l", "hand.l", "upperarm.r", "lowerarm.r", "wrist.r", "hand.r"]
const SKEL := "Rig_Medium/Skeleton3D:"
static var _lib: AnimationLibrary
static var _skinned_ok := -1

var skinned := false
var _tree: AnimationTree
var _skel: Skeleton3D
var _state := ""
var _aim_amount := 0.0


static func build(outfit: int, seed: int, armed: bool) -> Humanoid:
	var h := Humanoid.new()
	h.name = "Humanoid"
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
	for f in ANIM_FILES:
		var path := "res://assets/characters/kaykit/%s.glb" % f
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
				a.loop_mode = Animation.LOOP_LINEAR if n in LOOPS else Animation.LOOP_NONE
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
	var model: Node3D = (load(MANNEQUIN) as PackedScene).instantiate()
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
	var head := _attach("head")
	var chest := _attach("chest")
	var hips_a := _attach("hips")
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
		var hand := _attach("hand.r")
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
	# アニメーションツリー
	_tree = AnimationTree.new()
	model.add_child(_tree)
	_tree.root_node = NodePath("..")
	_tree.add_animation_library("", anim_library())
	var bt := AnimationNodeBlendTree.new()
	var bs := AnimationNodeBlendSpace1D.new()
	var idle_name := "Skeletons_Idle" if outfit == Outfit.GUARDIAN else "Idle_A"
	bs.add_blend_point(_anim_node(idle_name), 0.0)
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
	bt.add_node("ride", _anim_node("Sit_Chair_Idle"), Vector2(200, 200))
	bt.add_node("crouch", _anim_node("Crouching"), Vector2(200, 300))
	bt.add_node("dead", _anim_node("Death_A"), Vector2(200, 400))
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
