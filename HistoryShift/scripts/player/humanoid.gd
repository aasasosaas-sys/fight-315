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
static var force_variant := ""   # デバッグ用：人物モデルを固定
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


static func build(outfit: int, seed: int, armed: bool, female := -1, figure := "") -> Humanoid:
	var h := _make(outfit, seed, armed, female, figure)
	h._build_now()
	return h


## 遠くにいる間は組み立てない人物（町人・兵・歴史上の人物）。近づくと組み立て、遠ざかると見た目だけ捨てる
## （速さ・伏せ・倒れたなどの状態は Humanoid に残るので、組み立て直しても同じ姿・同じ状態に戻る）。
## prio：PRIORITY_TARGET（人物・ミッションの相手）＞ PRIORITY_GUARD（兵）＞ PRIORITY_CROWD（町人）。同時に組み立てる数の上限で優先する
static func build_streamed(outfit: int, seed: int, armed: bool, female := -1, figure := "", prio := PRIORITY_CROWD) -> Humanoid:
	var h := _make(outfit, seed, armed, female, figure)
	h.priority = prio
	if streaming_enabled:
		h.streamed = true
	else:
		h._build_now()
	return h


static func _make(outfit: int, seed: int, armed: bool, female: int, figure: String) -> Humanoid:
	var h := Humanoid.new()
	h.name = "Humanoid"
	h._female_req = female
	h._figure = figure
	h._args = [outfit, seed, armed]
	return h


## 見た目を組み立てる（build はすぐ、build_streamed は近づいたときに _build_some から）
func _build_now() -> void:
	if _built:
		return
	var t0 := Time.get_ticks_usec()
	if _skinned_ok == -1:
		_skinned_ok = 1 if ResourceLoader.exists(MANNEQUIN) else 0
	var outfit: int = _args[0]
	var seed: int = _args[1]
	var armed: bool = _args[2]
	if _skinned_ok == 1:
		_construct_skinned(outfit, seed, armed)
	else:
		_construct(outfit, seed, armed)
	_built = true
	_lod = -1
	_state = ""
	var us := Time.get_ticks_usec() - t0
	stat_builds += 1
	stat_build_usec += us
	stat_build_max_usec = maxi(stat_build_max_usec, us)
	if us > 60000 and OS.get_environment("HUMANOID_PROFILE") != "":
		print("  [Humanoid] slow build %.0fms outfit=%d figure=%s base=%s" % [us / 1000.0, outfit, _figure, get_meta("anime_base", "")])


## 見た目を捨てる（ノード・骨格・アニメーションの木）。状態の変数は残す
func _unbuild() -> void:
	if not _built:
		return
	# 木から外さずに消す（外した骨格に揺れ骨の更新が届くとエラーになる）。消えるのはこのフレームの終わり
	if _secondary and is_instance_valid(_secondary):
		var mod: Variant = _secondary.get("internal_modifier_node")
		if mod is SkeletonModifier3D:
			(mod as SkeletonModifier3D).active = false
	for c in get_children():
		c.queue_free()
	_skel = null
	_tree = null
	weapon = null
	muzzle = null
	hips = null; torso = null; head = null; arm_l = null; arm_r = null; leg_l = null; leg_r = null
	_anim_lib_override = null
	_mesh_list.clear()
	_secondary = null
	_built = false
	_lod = -1
	_state = ""
	stat_unbuilds += 1


func is_built() -> bool:
	return _built


func _enter_tree() -> void:
	if streamed and not (self in _streamed):
		_streamed.append(self)


func _exit_tree() -> void:
	if streamed:
		_streamed.erase(self)
		_queue.erase(self)


# ------------------------------------------------------------------ 人数・距離の管理（build_streamed の人物）
## 近づいたら組み立てる距離／遠ざかったら捨てる距離（m）・同時に組み立てておく上限
const STREAM_IN := 60.0
const STREAM_OUT := 120.0
const MAX_ACTIVE := 40
const PRIORITY_CROWD := 0
const PRIORITY_GUARD := 1
const PRIORITY_TARGET := 2
const PRIORITY_BONUS := 30.0          # 優先度 1 段で、これだけ近くにいるのと同じ扱い
## 遠い人物の手抜き（LOD）：揺れ骨を止める・影を落とさない・アニメーションを間引く距離（m）
const LOD_SPRING := 22.0
const LOD_SHADOW := 40.0
const LOD_ANIM := 45.0
const LOD_ANIM_FAR := 80.0
const BUILD_BUDGET_USEC := 8000       # 1 フレームに組み立てに使う時間（最低 1 人は組み立てる）
static var streaming_enabled := true  # false にすると build_streamed もすぐ組み立てる
static var _streamed: Array = []      # 登録中の Humanoid（build_streamed で作られ、木に入っているもの）
static var _queue: Array = []         # 組み立て待ち（近い・優先度の高い順）
static var _tick_frame := -1
static var _scan_t := 0.0
static var _warm_inst := {}           # 素体 → リターゲット用に読み込んだ素体（焼き直しが終わったら捨てる）
# ベンチマーク用の数
static var stat_builds := 0
static var stat_unbuilds := 0
static var stat_build_usec := 0
static var stat_build_max_usec := 0
static var stat_warm_usec := 0        # アニメーションの焼き直しに使った時間

var streamed := false
var priority := PRIORITY_CROWD
var _args: Array = []
var _built := false
var _lod := -1
var _dist := 0.0
var _anim_skip := 1
var _anim_n := 0
var _anim_acc := 0.0
var _mesh_list: Array = []
var _secondary: Node = null


## いまの優先度（持ち主がミッションの撃破対象になったら上げる）
func _prio() -> int:
	var p := get_parent()
	if p and p.get("mission_target") == true:
		return PRIORITY_TARGET
	return priority


func _score() -> float:
	return _dist - float(_prio()) * PRIORITY_BONUS


## 距離の基準：プレイヤー（乗り物に乗っていれば乗り物）。いなければ null（全員を組み立てる）
static func _focus() -> Variant:
	var p: Node3D = Game.player
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		return null
	var v: Variant = p.get("vehicle")
	if p.has_method("in_vehicle") and bool(p.call("in_vehicle")) and v is Node3D and is_instance_valid(v):
		return (v as Node3D).global_position
	return p.global_position


## 毎フレーム 1 回（最初に _process に来た登録済みの Humanoid が呼ぶ）
static func _stream_tick(dt: float) -> void:
	var f := Engine.get_process_frames()
	if f == _tick_frame:
		return
	_tick_frame = f
	var focus: Variant = _focus()
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_scan(focus)
	_build_some()


## 距離を測り、組み立てる人・捨てる人・LOD を決める
static func _scan(focus: Variant) -> void:
	_streamed = _streamed.filter(func(h: Variant) -> bool: return is_instance_valid(h) and (h as Humanoid).is_inside_tree())
	var cands: Array = []
	for h: Humanoid in _streamed:
		h._dist = 0.0 if focus == null else h.global_position.distance_to(focus as Vector3)
		if focus == null or h._dist < (STREAM_OUT if h._built else STREAM_IN):
			cands.append(h)
	cands.sort_custom(func(a: Humanoid, b: Humanoid) -> bool: return a._score() < b._score())
	var want := {}
	for i in cands.size():
		if focus != null and i >= MAX_ACTIVE:
			break
		want[cands[i]] = true
	_queue.clear()
	for h: Humanoid in cands:
		if want.has(h) and not h._built:
			_queue.append(h)
	for h: Humanoid in _streamed:
		if h._built and not want.has(h):
			h._unbuild()
		elif h._built:
			h._apply_lod()


## 待っている人を、フレームの予算の範囲で組み立てる（素体のアニメーションの焼き直しも少しずつ）
static func _build_some() -> void:
	var t0 := Time.get_ticks_usec()
	var built := 0
	var i := 0
	var warmed := false
	while i < _queue.size():
		var h: Humanoid = _queue[i]
		if not is_instance_valid(h) or not h.is_inside_tree() or h._built:
			_queue.remove_at(i)
			continue
		var used := Time.get_ticks_usec() - t0
		if (built > 0 or warmed) and used > BUILD_BUDGET_USEC:
			return
		var base := h.anime_base()
		if base != "" and not AnimeChar.prefetch_base(base):
			i += 1          # 素体を裏で読み込み中：ほかの人を先に
			continue
		if base != "" and not Retarget.is_ready(base):
			warmed = true
			if not _warm(base, maxi(BUILD_BUDGET_USEC - used, 2000)):
				return   # 続きは次のフレーム
			continue
		_queue.remove_at(i)
		h._build_now()
		h._apply_lod()
		built += 1


## 素体のアニメーションを少しずつ焼き直す。終わったら true
static func _warm(base: String, budget_usec: int) -> bool:
	var t0 := Time.get_ticks_usec()
	var inst: Node3D = _warm_inst.get(base, null)
	if inst == null:
		inst = AnimeChar.scene(AnimeChar.VRM_DIR + base + ".vrm").instantiate()
		_warm_inst[base] = inst
	var sks := inst.find_children("*", "Skeleton3D", true, false)
	var done := sks.is_empty() or Retarget.warm(sks[0] as Skeleton3D, base, budget_usec)
	if done:
		_warm_inst.erase(base)
		inst.free()
	stat_warm_usec += Time.get_ticks_usec() - t0
	return done


## この人物のアニメ素体の名前（組み立てる前に分かる。アニメ素体を使わない環境では ""）
func anime_base() -> String:
	if not anime or force_variant != "" or _args.is_empty():
		return ""
	if _skinned_ok == -1:
		_skinned_ok = 1 if ResourceLoader.exists(MANNEQUIN) else 0
	if _skinned_ok != 1:
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_args[1])
	var pick := _pick_anime(int(_args[0]), rng)
	var base := String(pick["base"])
	return base if ResourceLoader.exists(AnimeChar.VRM_DIR + base + ".vrm") else ""


## 遠い人物の手抜き：揺れ骨・影・アニメーションの更新頻度
func _apply_lod() -> void:
	if not _built or not streamed:
		return
	var lod := 0 if _dist < LOD_SPRING else (1 if _dist < LOD_SHADOW else (2 if _dist < LOD_ANIM else 3))
	if lod == _lod:
		return
	_lod = lod
	if _mesh_list.is_empty():
		_mesh_list = find_children("*", "MeshInstance3D", true, false)
		var sec := find_child("secondary", true, false)
		_secondary = sec
	# 揺れ骨（VRM の髪・袖の spring bone）
	if _secondary and is_instance_valid(_secondary):
		var mod: Variant = _secondary.get("internal_modifier_node")
		if mod is SkeletonModifier3D:
			(mod as SkeletonModifier3D).active = lod == 0
	# 影
	for mi: MeshInstance3D in _mesh_list:
		if not is_instance_valid(mi):
			continue
		if not mi.has_meta("lod_shadow0"):
			mi.set_meta("lod_shadow0", mi.cast_shadow)
		if lod >= 2:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mi.cast_shadow = mi.get_meta("lod_shadow0")
	# アニメーション：遠いほど間引いてまとめて進める
	_anim_skip = 1 if lod < 3 else (2 if _dist < LOD_ANIM_FAR else 4)
	if _tree:
		_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE if _anim_skip == 1 else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_anim_n = get_instance_id() % _anim_skip
		_anim_acc = 0.0


## アニメ素体の性別と素体の選び方（_construct_anime と anime_base で同じ乱数の使い方をする）
func _pick_anime(outfit: int, rng: RandomNumberGenerator) -> Dictionary:
	var female := false
	if _female_req >= 0:
		female = _female_req == 1
	elif outfit == Outfit.KIMONO:
		female = rng.randf() < 0.8
	elif outfit in [Outfit.COMMONER, Outfit.NOBLE, Outfit.ANCIENT, Outfit.WESTERN]:
		female = rng.randf() < 0.35
	var bases: Array = ANIME_FEMALE if female else ANIME_MALE
	var base: String = bases[rng.randi() % bases.size()]
	if outfit == Outfit.AGENT:
		base = "HairSample_Male"
	if _figure != "":
		var fs: Dictionary = Figures.spec_for(_figure)
		if not fs.is_empty():
			base = fs["base"]
	return {"female": female, "base": base}


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
				a.set_meta("src", path)
				_lib.add_animation(n, a)
		inst.free()
	return _lib


static func _anim_node(n: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = n
	return a


## アニメ調（VRoid）素体を使うか。素体がない環境では写実→KayKit→手作りの順に代わりを使う
static var anime := true
const ANIME_MALE := ["HairSample_Male", "Sakurada_Fumiriya", "Sendagaya_Shibu"]
const ANIME_FEMALE := ["Sendagaya_Shino", "HairSample_Female"]
var _anim_lib_override: AnimationLibrary
var _figure := ""   # 歴史上の人物名（専用の見た目：scripts/player/figures.gd）


## 服装（Outfit）→ アニメ素体の衣装・髪型・配色。未実装の衣装は近い時代の装いで代用
func _anime_spec(outfit: int, female: bool, rng: RandomNumberGenerator) -> Dictionary:
	var sets: Dictionary = AnimeChar.SETS
	var pick := func(names: Array) -> String:
		for nm in names:
			if sets.has(nm):
				return nm
		return "hakama"
	var dye := func(opts: Array) -> String:
		return opts[rng.randi() % opts.size()]
	match outfit:
		Outfit.AGENT:
			return {"outfit": "modern", "hair": ""}
		Outfit.GUARDIAN:
			return {"outfit": "modern", "hair": ""}
		Outfit.SAMURAI:
			return {"outfit": pick.call(["busho", "samurai"]), "hair": "chonmage",
				"pal": {"kosode": dye.call(["kon:kasuri:ai", "kuro:plain", "enji:plain", "ai:kasuri:shiro"]), "eri": "kuro", "haneri": "shiro",
					"hakama": dye.call(["nezumi:shima:kuro", "kuchiba:shima:kaki", "kon:shima:ai"]), "obi": "kuro", "armor": "enji"}}
		Outfit.ASHIGARU:
			return {"outfit": pick.call(["ashigaru", "hakama"]), "hair": "chasen",
				"pal": {"kosode": dye.call(["kaki:plain", "ai:plain", "kuchiba:plain"]), "eri": "kuro", "haneri": "shiro", "hakama": "kuchiba:plain", "obi": "kuro"}}
		Outfit.NOBLE:
			if female:
				return {"outfit": "kimono", "hair": "suberakashi",
					"pal": {"kosode": dye.call(["enji:asanoha:kin", "moegi:asanoha:shiro", "sakura:sakura_komon:shiro"]), "eri": "kin", "haneri": "shiro", "robe": dye.call(["enji:plain", "kon:plain"]), "obi": "kin:asanoha:enji"}}
			return {"outfit": "hakama", "hair": "court_bun",
				"pal": {"kosode": dye.call(["enji:asanoha:kin", "kon:asanoha:kin", "moegi:plain"]), "eri": "kin", "haneri": "shiro", "hakama": dye.call(["shiro:plain", "kon:plain"]), "obi": "kuro"}}
		Outfit.MONK:
			return {"outfit": "kimono", "hair": "buzz", "pal": {"kosode": "kuro:plain", "eri": "kuro", "haneri": "shiro", "robe": "kuro:plain", "obi": "nezumi"}}
		Outfit.ANCIENT:
			return {"outfit": "kimono", "hair": "suberakashi" if female else "court_bun",
				"pal": {"kosode": "shiro:plain", "eri": "kuchiba", "haneri": "shiro", "robe": "kuchiba:plain", "obi": "enji"}}
		Outfit.KIMONO:
			return {"outfit": "kimono", "hair": dye.call(["shimada", "shimada", "sokuhatsu"]) if female else "chonmage",
				"pal": {"kosode": dye.call(["sakura:sakura_komon:shiro", "ai:ichimatsu:shiro", "moegi:asanoha:shiro", "kaki:kasuri:shiro"]), "eri": dye.call(["enji", "kuro"]), "haneri": "shiro",
					"robe": "", "obi": dye.call(["kin:asanoha:enji", "enji:ichimatsu:kuro", "kuro:plain"])}}
		Outfit.WESTERN:
			return {"outfit": pick.call(["haikara" if female else "suit_meiji", "shosei", "hakama"]), "hair": "sokuhatsu" if female else "zangiri",
				"pal": {"kosode": "ai:plain", "eri": "kon", "haneri": "shiro", "hakama": "kon:plain", "obi": "kuro"}}
		Outfit.SOLDIER:
			return {"outfit": pick.call(["army", "hakama"]), "hair": "buzz", "pal": {"kosode": "kuchiba:plain", "eri": "kuchiba", "haneri": "shiro", "hakama": "kuchiba:plain", "obi": "kuro"}}
		Outfit.POLICE:
			return {"outfit": pick.call(["police", "army", "hakama"]), "hair": "zangiri", "pal": {"kosode": "kon:plain", "eri": "kon", "haneri": "shiro", "hakama": "kon:plain", "obi": "kuro"}}
	# 町人
	if female:
		return {"outfit": "kimono", "hair": "shimada",
			"pal": {"kosode": dye.call(["ai:kasuri:shiro", "kaki:ichimatsu:kuchiba", "moegi:plain"]), "eri": "kuro", "haneri": "shiro", "robe": "", "obi": "kuro:plain"}}
	return {"outfit": "hakama", "hair": "chonmage",
		"pal": {"kosode": dye.call(["ai:kasuri:shiro", "kaki:plain", "kuchiba:shima:kaki", "nezumi:plain"]), "eri": "kuro", "haneri": "shiro", "hakama": dye.call(["nezumi:shima:kuro", "kon:plain", "kuchiba:plain"]), "obi": "kuro"}}


## 町人・兵の顔の形の種類（素体・性別・年齢ごと）
const FACE_POOL := 4
static var _shadow_cache := {}        # 元の素材 → 修正力の素材（全員で共有）
static var _bt_cache := {}            # アニメーションの木の形 → AnimationNodeBlendTree（全員で共有）


## 「歴史の修正力」：墨のように黒い体に、紫に光る輪郭と目（主人公の現代服と見分けがつくように）
func _shadowify(model: Node3D) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(si)
			if m == null:
				m = mi.mesh.surface_get_material(si)
			if not (m is ShaderMaterial):
				continue
			if _shadow_cache.has(m):
				mi.set_surface_override_material(si, _shadow_cache[m])
				continue
			var mm := (m as ShaderMaterial).duplicate() as ShaderMaterial
			var eye := "eye" in m.resource_name.to_lower()
			mm.set_shader_parameter("_Color", Color(0.9, 0.3, 1.0) if eye else Color(0.09, 0.07, 0.13))
			mm.set_shader_parameter("_ShadeColor", Color(0.03, 0.02, 0.06))
			mm.set_shader_parameter("_RimColor", Color(0.75, 0.2, 1.0))
			mm.set_shader_parameter("_RimFresnelPower", 3.0)
			mm.set_shader_parameter("_RimLift", 0.15)
			if eye:
				mm.set_shader_parameter("_EmissionColor", Color(0.9, 0.3, 1.0))
			if mm.next_pass is ShaderMaterial:
				var ol := (mm.next_pass as ShaderMaterial).duplicate() as ShaderMaterial
				ol.set_shader_parameter("_OutlineColor", Color(0.8, 0.25, 1.0))
				ol.set_shader_parameter("_OutlineLightingMix", 0.0)
				mm.next_pass = ol
			_shadow_cache[m] = mm
			mi.set_surface_override_material(si, mm)


func _construct_anime(outfit: int, rng: RandomNumberGenerator, armed: bool) -> bool:
	var female := false
	if _female_req >= 0:
		female = _female_req == 1
	elif outfit == Outfit.KIMONO:
		female = rng.randf() < 0.8
	elif outfit in [Outfit.COMMONER, Outfit.NOBLE, Outfit.ANCIENT, Outfit.WESTERN]:
		female = rng.randf() < 0.35
	var bases: Array = ANIME_FEMALE if female else ANIME_MALE
	var base: String = bases[rng.randi() % bases.size()]
	if outfit == Outfit.AGENT:
		base = "HairSample_Male"   # （_pick_anime と同じ選び方。変えるときは両方）
	if not ResourceLoader.exists(AnimeChar.VRM_DIR + base + ".vrm"):
		return false
	var spec := _anime_spec(outfit, female, rng)
	var fs: Dictionary = Figures.spec_for(_figure) if _figure != "" else {}
	if not fs.is_empty():
		female = fs["female"]
		base = fs["base"]
		spec = {"outfit": fs["outfit"], "hair": "", "pal": fs["palette"]}
	var pal: Dictionary = spec.get("pal", {})
	if pal.get("robe", null) == "":
		pal["robe"] = pal.get("kosode", "ai")
	var model: Node3D = AnimeChar.build(base, spec.outfit, pal, spec.hair)
	if not fs.is_empty():
		Figures.decorate(model, fs, rng.randi())
	# 顔・年齢・体格の個人差（武装した者・兵には子どもを出さない）
	var combat := armed or outfit in [Outfit.SAMURAI, Outfit.ASHIGARU, Outfit.SOLDIER, Outfit.POLICE, Outfit.GUARDIAN, Outfit.AGENT]
	var fopts := {"female": female, "modern": outfit in MODERN}
	if combat:
		fopts["age"] = "young" if rng.randf() < 0.5 else "adult"
	if fs.is_empty():
		fopts["pool"] = FACE_POOL   # 町人・兵の顔の形は素体・年齢ごとに数種類から（顔メッシュを共有する）。色・髭・表情は一人ずつ
		set_meta("face", AnimeFace.apply(model, rng.randi(), fopts))
	if outfit == Outfit.GUARDIAN:
		_shadowify(model)
	# アニメ素体は自前のアニメーションプレイヤーを持つので、木（AnimationTree）だけで動かす
	var own := model.get_node_or_null("Anim")
	if own:
		_anim_lib_override = (own as AnimationPlayer).get_animation_library("")
		model.remove_child(own)
		own.free()
	add_child(model)
	realistic = true
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	set_meta("female", female)
	set_meta("anime_base", base)
	var h := _rest_height(model)
	var target := 1.72 if outfit == Outfit.AGENT else ((1.55 if female else 1.68) if outfit in MODERN else (1.5 if female else 1.62))
	target *= rng.randf_range(0.97, 1.03)
	model.scale = Figures.integration_scale(model, fs) if not fs.is_empty() else Vector3.ONE * (target / maxf(h, 0.5))
	if armed:
		var hand := _holder("RightHand")
		weapon = Node3D.new()
		weapon.name = "Weapon"
		hand.add_child(weapon)
		weapon.position = Vector3(0, 0.07, 0.03)
		weapon.rotation_degrees = Vector3(-90, 0, 0)
		var metal := mat(Color(0.12, 0.12, 0.13), 0.35, 0.9)
		var wood := mat(Color(0.35, 0.22, 0.12), 0.7)
		part(weapon, "box", wood, Vector3(0, -0.01, -0.05), Vector3(0.045, 0.07, 0.42))
		part(weapon, "cyl", metal, Vector3(0, 0.02, 0.38), Vector3(0.022, 0.62, 0.022), Vector3(90, 0, 0))
		muzzle = Node3D.new()
		muzzle.position = Vector3(0, 0.02, 0.7)
		weapon.add_child(muzzle)
	_setup_tree(model, outfit, armed)
	return true


func _construct_skinned(outfit: int, seed: int, armed: bool) -> void:
	skinned = true
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if anime and force_variant == "" and _construct_anime(outfit, rng, armed):
		return
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
		if Toon.enabled:
			_animeify(model, outfit, rng)
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
	var lib: AnimationLibrary = _anim_lib_override if _anim_lib_override else anim_library()
	_tree.add_animation_library("", lib)
	# 木の形（ノードの組み合わせ）は同じ形の人物で共有する（値は AnimationTree ごとに持つ）
	var bt_key := "%d|%s|%s|%s" % [lib.get_instance_id(), outfit == Outfit.GUARDIAN, outfit in [Outfit.SOLDIER, Outfit.ASHIGARU, Outfit.SAMURAI], armed]
	if _bt_cache.has(bt_key):
		_tree.tree_root = _bt_cache[bt_key]
		_tree.active = true
		hips = Node3D.new(); torso = hips; head = hips; arm_l = hips; arm_r = hips; leg_l = hips; leg_r = hips
		add_child(hips)
		return
	var bt := AnimationNodeBlendTree.new()
	var bs := AnimationNodeBlendSpace1D.new()
	var mocap := lib.has_animation("Mocap_Walk")
	var idle_name := "Skeletons_Idle" if outfit == Outfit.GUARDIAN else ("Mocap_Stand" if mocap else "Idle_A")
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
	_bt_cache[bt_key] = bt
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
	if force_variant != "":
		vname = force_variant.get_slice(",", 1 if female and force_variant.contains(",") else 0)
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
## 和装の組み合わせ（tools/kimono.py で布シミュレーションして作った衣服: kosode / eri / hakama / robe / obi / armor）
const WASOU := {
	Outfit.SAMURAI: ["kosode", "eri", "hakama", "obi", "armor"], Outfit.ASHIGARU: ["kosode", "hakama", "obi", "armor"],
	Outfit.NOBLE: ["kosode", "eri", "hakama"], Outfit.KIMONO: ["kosode", "eri", "robe", "obi"],
	Outfit.MONK: ["kosode", "eri", "robe"], Outfit.ANCIENT: ["kosode", "hakama"], Outfit.COMMONER: ["kosode", "eri", "hakama", "obi"],
}
## 自然染料の色（藍・紺・茶・墨・生成り・柿渋・鼠・萌黄・臙脂・浅葱）
const DYES := {
	"ai": Color(0.13, 0.2, 0.34), "kon": Color(0.08, 0.1, 0.18), "cha": Color(0.33, 0.23, 0.15), "sumi": Color(0.09, 0.09, 0.09),
	"kinari": Color(0.82, 0.77, 0.66), "kakishibu": Color(0.5, 0.3, 0.17), "nezumi": Color(0.42, 0.41, 0.39),
	"moegi": Color(0.42, 0.47, 0.25), "enji": Color(0.42, 0.11, 0.14), "asagi": Color(0.28, 0.48, 0.52), "shiro": Color(0.92, 0.9, 0.85),
}
static var _fabric_tex := {}


static func _gray_tex(path: String) -> Texture2D:
	if _fabric_tex.has(path):
		return _fabric_tex[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		var img: Image = (load(path) as Texture2D).get_image()
		if img:
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGB8)
			var lum := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
			var avg := 0.0
			for y in range(0, img.get_height(), 8):
				for x in range(0, img.get_width(), 8):
					avg += img.get_pixel(x, y).get_luminance()
			avg /= float((img.get_height() / 8) * (img.get_width() / 8))
			for y in img.get_height():
				for x in img.get_width():
					var v := clampf(img.get_pixel(x, y).get_luminance() / maxf(avg, 0.05) * 0.85, 0.0, 1.2)
					lum.set_pixel(x, y, Color(v, v, v))
			lum.generate_mipmaps()
			t = ImageTexture.create_from_image(lum)
	_fabric_tex[path] = t
	return t


static func _lamellar_tex(lace: Color) -> Texture2D:
	var key := "lam" + lace.to_html()
	if _fabric_tex.has(key):
		return _fabric_tex[key]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var lacquer := Color(0.07, 0.06, 0.06)
	for y in n:
		for x in n:
			var band := y % 16
			var c := lacquer.lerp(Color(0.16, 0.13, 0.11), float(band) / 16.0 * 0.6)
			if band < 2:
				c = Color(0.03, 0.03, 0.03)                      # 段の継ぎ目
			if (x % 8) < 2 and band >= 4 and band <= 12:
				c = lace                                          # 縅の糸
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_fabric_tex[key] = t
	return t


## 布地：スキャン素材（Poly Haven, CC0）の織り目・凹凸・粗さに、染料の色を掛ける
static func fabric(c: Color, kind: String, scale := 4.0) -> StandardMaterial3D:
	var base := "res://assets/polyhaven/textures/fab_%s_" % kind
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = _gray_tex(base + "diff.jpg")
	if ResourceLoader.exists(base + "nor_gl.jpg"):
		m.normal_enabled = true
		m.normal_texture = load(base + "nor_gl.jpg")
		m.normal_scale = 1.0
	if ResourceLoader.exists(base + "rough.jpg"):
		m.roughness_texture = load(base + "rough.jpg")
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 2.0
	m.uv1_scale = Vector3(scale, scale, scale)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## 時代・身分ごとの布と染め
func _garment_mat(outfit: int, kind: String, rng: RandomNumberGenerator) -> StandardMaterial3D:
	var pick := func(keys: Array) -> Color: return DYES[keys[rng.randi() % keys.size()]]
	match kind:
		"eri":
			return fabric(DYES["shiro"], "cotton", 8.0)
		"obi":
			if outfit == Outfit.KIMONO:
				return fabric(pick.call(["enji", "kinari", "moegi", "asagi"]), "brocade", 6.0)
			return fabric(pick.call(["cha", "sumi", "kon"]), "cotton", 8.0)
		"armor":
			# 漆塗りの小札（横の段）と色糸の縅（おどし）
			var lace: Color = pick.call(["enji", "kon", "moegi", "shiro"])
			var am := StandardMaterial3D.new()
			am.albedo_texture = _lamellar_tex(lace)
			am.albedo_color = Color(1, 1, 1)
			am.roughness = 0.35
			am.metallic = 0.1
			am.clearcoat_enabled = true
			am.clearcoat = 0.8
			am.clearcoat_roughness = 0.2
			am.uv1_triplanar = true
			am.uv1_scale = Vector3(3.5, 3.5, 3.5)
			am.cull_mode = BaseMaterial3D.CULL_DISABLED
			return am
		"hakama":
			match outfit:
				Outfit.NOBLE: return fabric(pick.call(["asagi", "moegi", "kinari"]), "silk", 5.0)
				Outfit.ANCIENT: return fabric(DYES["kinari"], "hemp", 4.0)
				Outfit.SAMURAI: return fabric(pick.call(["nezumi", "cha", "kon", "sumi"]), "linen", 5.0)
			return fabric(pick.call(["ai", "cha", "nezumi", "kakishibu"]), "hemp", 4.0)
		"robe":
			if outfit == Outfit.MONK:
				return fabric(DYES["sumi"], "linen", 5.0)
			return fabric(pick.call(["ai", "enji", "asagi", "moegi", "nezumi", "kakishibu"]), "cotton", 5.0)
		_:  # kosode
			match outfit:
				Outfit.NOBLE: return fabric(pick.call(["enji", "asagi", "moegi", "kinari"]), "brocade", 4.0)
				Outfit.MONK: return fabric(DYES["sumi"], "linen", 5.0)
				Outfit.ANCIENT: return fabric(DYES["kinari"], "hemp", 4.0)
				Outfit.SAMURAI: return fabric(pick.call(["kon", "ai", "kinari", "cha"]), "silk", 5.0)
				Outfit.KIMONO: return fabric(pick.call(["ai", "enji", "asagi", "moegi", "nezumi"]), "cotton", 5.0)
			return fabric(pick.call(["ai", "kon", "cha", "nezumi", "kakishibu", "kinari"]), "hemp", 4.0)


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
				mi.material_override = _garment_mat(outfit, kind, rng)
			continue
		if n.ends_with("_body") or n.ends_with("_bodyw"):
			# 和装では服の下を消した体（_bodyw）を使い、突き抜けを防ぐ
			var is_w := n.ends_with("_bodyw")
			mi.visible = is_w == (not wear.is_empty())
			if mi.visible:
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
			part(head, "sphere", m_lacquer, Vector3(0, 0.1, -0.005), Vector3(0.245, 0.15, 0.265))    # 兜の鉢
			part(head, "skirt", m_lacquer, Vector3(0, -0.01, -0.035), Vector3(0.44, 0.13, 0.44))       # 錣（裾広がりに垂れる）
			part(head, "box", m_acc, Vector3(-0.05, 0.2, 0.11), Vector3(0.012, 0.13, 0.006), Vector3(-10, 0, 22))  # 鍬形
			part(head, "box", m_acc, Vector3(0.05, 0.2, 0.11), Vector3(0.012, 0.13, 0.006), Vector3(-10, 0, -22))
		Outfit.ASHIGARU:
			part(head, "cone", m_lacquer, Vector3(0, 0.15, 0), Vector3(0.46, 0.08, 0.46))              # 陣笠
		Outfit.NOBLE:
			part(head, "cyl", m_black, Vector3(0, 0.22, -0.02), Vector3(0.12, 0.24, 0.14), Vector3(-12, 0, 0))  # 烏帽子
		Outfit.KIMONO:
			pass
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


const HAIR_LAYER := 1 << 1


## アニメ調：セル塗り＋輪郭線、写実的な目・眉・まつげを隠してアニメ顔を投影、肌は塗りつぶし
func _animeify(model: Node3D, outfit: int, rng: RandomNumberGenerator) -> void:
	var female: bool = get_meta("female", false)
	var skin := Color(1.0, 0.86, 0.77).lerp(Color(0.93, 0.75, 0.63), rng.randf())
	if outfit == Outfit.GUARDIAN:
		skin = Color(0.3, 0.27, 0.36)
	for node in find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible:
			continue
		var n := String(mi.name).to_lower()
		if n.contains("eyebrow") or n.contains("eyelash"):
			mi.visible = false
		elif n.contains("low-poly"):
			Toon.apply(mi, 0.0, Color(0.97, 0.96, 0.95))   # 白目（虹彩はデカールで描く）
		elif _under_attachment(mi):
			mi.layers = HAIR_LAYER                          # 帽子・兜などには顔を映さない
			Toon.apply(mi, 0.0035)
		elif n.ends_with("_body") or n.ends_with("_bodyw"):
			Toon.apply(mi, 0.0035, skin)
		elif n.contains("short") or n.contains("long") or n.contains("bob") or n.contains("ponytail") or n.contains("braid") or n.contains("afro"):
			mi.layers = HAIR_LAYER
			Toon.apply(mi, 0.0025)
		else:
			Toon.apply(mi, 0.0045)
	Toon.add_face(_holder("Head"), female, rng.randi() % 3, HAIR_LAYER)


func _under_attachment(n: Node) -> bool:
	var p := n.get_parent()
	while p and p != self:
		if p is BoneAttachment3D:
			return true
		p = p.get_parent()
	return false


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
	if streamed:
		_stream_tick(dt)
	if not _built:
		return
	if skinned:
		if _tree == null:
			return
		_process_skinned(dt)
		if _anim_skip > 1:
			_anim_acc += dt
			_anim_n += 1
			if _anim_n >= _anim_skip:
				_anim_n = 0
				_tree.advance(_anim_acc)
				_anim_acc = 0.0
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
